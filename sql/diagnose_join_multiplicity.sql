/*
Причины кратности связей. Каждый SELECT запускать ОТДЕЛЬНО, после построения V4.
Новые таблицы не создаются, исходные данные не меняются.
GROUP BY здесь считает нарушения/кратность, а не удаляет строки из прототипа.
Все проверки используют ту же отобранную базу анкет и те же пары номеров.
Непустой результат не всегда ошибка: несколько разных дочерних заявок — связь 1:N.
Дата в проверке 2 должна совпадать с фактическим P_BEGIN_DATE запуска.
*/

-- 1. Сколько NULL-продуктов фактически попало в выбранную TAS через блок EXISTS.
select count(*) as selected_tas_null_product_rows
from sbx_pre_orb_fd.man_prt_tif_tas
where level25_product_bp_nm is null;

-- 2. Сколько строк трёх продуктов исключил фильтр отсутствия обоих ключей.
select count(*) as tas_without_real_keys
from dm_pik_fd_cdmr.tech_application_status
where level25_product_bp_nm in ('Потребкредит', 'Кредитные карты', 'Автокредит')
  and (coalesce(application_dt, parent_application_dt) >= date '2025-01-01'
       or coalesce(application_dt, parent_application_dt) is null)
  and coalesce(parent_application_rk, -1) = -1
  and coalesce(application_rk, -1) = -1;

-- 3. Повторяется ли ОДНА И ТА ЖЕ пара ID/номер в исходной intention.
select r.questionnaire_id, r.application_num, count(*) as source_row_count
from rd_raw_orb.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention r
where r.application_num is not null
  and exists (
      select 1 from sbx_pre_orb_fd.man_prt_tif_questionnaire q
      where q.questionnaire_id = r.questionnaire_id
        and q.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
  )
group by r.questionnaire_id, r.application_num
having count(*) > 1;


-- 4. Несколько РАЗНЫХ номеров у одной анкеты после сворачивания одинаковых пар.
-- Это проверка текущей таблицы шага 1.3, где пара ID/номер уже уникальна.
-- NULL не считается вторым номером, если в ручной копии он оставлен в таблице.
select questionnaire_id, count(*) as different_application_numbers
from sbx_pre_orb_fd.man_prt_tif_questionnaire_numbers
where application_num is not null
group by questionnaire_id
having count(*) > 1;

-- 5. Нарушение уникальности текущего ключа BDM в исследуемых номерах.
select a.application_rk, a.src_cd, count(*) as current_bdm_rows
from bdm.application a
where a.effective_to_date = date '2999-12-31'
  and a.application_rk is not null and a.application_rk <> -1
  and exists (
      select 1 from sbx_pre_orb_fd.man_prt_tif_questionnaire_numbers n
      where n.application_num = a.application_num
  )
group by a.application_rk, a.src_cd
having count(*) > 1;

-- 6. Один номер в одном источнике находит несколько разных текущих RK BDM.
-- В запросе только один COUNT DISTINCT, повтор в HAVING — та же агрегация.
select a.application_num, a.src_cd,
       count(distinct a.application_rk) as different_bdm_keys
from bdm.application a
where a.effective_to_date = date '2999-12-31'
  and a.application_rk is not null and a.application_rk <> -1
  and exists (
      select 1 from sbx_pre_orb_fd.man_prt_tif_questionnaire_numbers n
      where n.application_num = a.application_num
  )
group by a.application_num, a.src_cd
having count(distinct a.application_rk) > 1;

-- 7. Что скрывает GROUP BY шага 1.4: несколько путей к одной связи анкета/BDM.
-- Смотреть совместно с 4–6 и 10: причина может быть в номерах, BDM или TQS.
select q.questionnaire_rk, q.level25_product_bp_nm,
       a.application_rk, a.src_cd, count(*) as path_count
from sbx_pre_orb_fd.man_prt_tif_questionnaire q
join sbx_pre_orb_fd.man_prt_tif_questionnaire_numbers n
  on n.questionnaire_id = q.questionnaire_id
join bdm.application a
  on a.application_num = n.application_num
 and a.effective_to_date = date '2999-12-31'
 and a.application_rk is not null and a.application_rk <> -1
where q.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
group by q.questionnaire_rk, q.level25_product_bp_nm, a.application_rk, a.src_cd
having count(*) > 1;

-- 8. Несколько РАЗНЫХ дочерних заявок одной УЗ. Это не повтор одной пары TAS.
select parent_application_rk, parent_src_cd,
       count(distinct application_rk) as different_child_applications
from sbx_pre_orb_fd.man_prt_tif_tas
where parent_application_rk <> -1 and application_rk <> -1
group by parent_application_rk, parent_src_cd
having count(distinct application_rk) > 1;

-- 9. Что скрывают GROUP BY шага 2.1: повтор ровно той же пары до их применения.
-- Сами разные дочки одного родителя в эту проверку повторов не попадают.
with candidates as (
    select b.questionnaire_rk, b.level25_product_bp_nm,
           t.parent_application_rk, t.application_rk
    from sbx_pre_orb_fd.man_prt_tif_kn_kk_bdm b
    join sbx_pre_orb_fd.man_prt_tif_tas t
      on b.bdm_application_rk = t.parent_application_rk
     and b.bdm_src_cd = t.parent_src_cd
    where t.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
       or t.level25_product_bp_nm is null
    union all
    select q.questionnaire_rk, q.level25_product_bp_nm,
           t.parent_application_rk, t.application_rk
    from sbx_pre_orb_fd.man_prt_tif_questionnaire q
    join sbx_pre_orb_fd.man_prt_tif_tas t
      on q.questionnaire_id = t.application_id
    where q.level25_product_bp_nm = 'Автокредит'
      and (t.level25_product_bp_nm = 'Автокредит' or t.level25_product_bp_nm is null)
)
select questionnaire_rk, level25_product_bp_nm,
       parent_application_rk, application_rk, count(*) as candidate_row_count
from candidates
group by questionnaire_rk, level25_product_bp_nm, parent_application_rk, application_rk
having count(*) > 1;

-- 10. Проверка самой текущей анкетной базы до остальных соединений.
select questionnaire_rk, level25_product_bp_nm, count(*) as current_questionnaire_rows
from sbx_pre_orb_fd.man_prt_tif_questionnaire
group by questionnaire_rk, level25_product_bp_nm
having count(*) > 1;

-- 11. У одного ID несколько текущих строк TQS (включая разные RK/продукты).
-- Это отдельно от проверки уникальности RK в 10.
select questionnaire_id, count(*) as current_rows_for_id
from sbx_pre_orb_fd.man_prt_tif_questionnaire
where level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
group by questionnaire_id
having count(*) > 1;
