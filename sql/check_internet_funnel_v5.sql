/*
Проверки нового V5. Каждый SELECT выполнять отдельно; таблицы не создаются.
Сначала проверить уникальность источников, затем сохранность и покрытия.
NULL / -1 не считаются реальными ключами. Разрез продуктов для анкет берётся
из анкетной ветки, для заявок — из TAS, а не из общего числа строк финала.
*/

-- 1. Исторический ключ TQS включает effective_from_dttm, а не только RK.
select questionnaire_rk, effective_from_dttm, count(*) as row_count
from dm_pik_fd_cdmr.tech_questionnaire_status
group by questionnaire_rk, effective_from_dttm
having count(*) > 1;

-- 2. TAS хранит последнее состояние; повторы пары ключей требуют разбора, не DISTINCT.
select coalesce(parent_application_rk, -1) as parent_application_rk,
       coalesce(application_rk, -1) as application_rk, count(*) as row_count
from dm_pik_fd_cdmr.tech_application_status
where level25_product_bp_nm in ('Потребкредит', 'Кредитные карты', 'Автокредит')
group by coalesce(parent_application_rk, -1), coalesce(application_rk, -1)
having count(*) > 1;

-- 3. Ключ строки итогового снимка; ожидается пустой результат при уникальной TAS.
select questionnaire_rk, parent_application_rk, application_rk, count(*) as row_count
from sbx_pre_orb_fd.man_prt_tif_v5_tech_internet_funnel
group by questionnaire_rk, parent_application_rk, application_rk
having count(*) > 1;

-- 4. Заполнение ключей; ожидается 0.
select count(*) as invalid_keys
from sbx_pre_orb_fd.man_prt_tif_v5_tech_internet_funnel
where questionnaire_rk is null or parent_application_rk is null or application_rk is null
   or (questionnaire_rk = -1 and parent_application_rk = -1 and application_rk = -1);

-- 5. Уже связанные пары не должны повторно попадать в оставшиеся заявки; ожидается 0.
select count(*) as repeated_linked_applications
from sbx_pre_orb_fd.man_prt_tif_v5_remaining_tas t
where exists (
    select 1 from sbx_pre_orb_fd.man_prt_tif_v5_questionnaire_funnel q
    where q.parent_application_rk = t.parent_application_rk
      and q.application_rk = t.application_rk
);

-- 6. При найденной связи флаг true; ожидается 0.
select count(*) as invalid_linked_flags
from sbx_pre_orb_fd.man_prt_tif_v5_tech_internet_funnel
where questionnaire_rk <> -1
  and (parent_application_rk <> -1 or application_rk <> -1)
  and quest_verification_flg is distinct from true;

-- 7. Без анкеты флаг NULL; ожидается 0.
select count(*) as invalid_missing_questionnaire_flags
from sbx_pre_orb_fd.man_prt_tif_v5_tech_internet_funnel
where questionnaire_rk = -1 and quest_verification_flg is not null;

-- 8. Все анкеты по продуктам готовой TQS, включая не имеющие номера.
select level25_product_bp_nm, count(distinct questionnaire_rk) as questionnaire_count
from sbx_pre_orb_fd.man_prt_tif_v5_questionnaire
group by level25_product_bp_nm;

-- 9. Связанные анкеты по исходному продукту TQS.
select level25_product_bp_nm, count(distinct questionnaire_rk) as linked_questionnaire_count
from sbx_pre_orb_fd.man_prt_tif_v5_matches
group by level25_product_bp_nm;

-- 10. Все заявочные пары по продуктам TAS.
select level25_product_bp_nm,
       count(distinct row(parent_application_rk, application_rk)) as application_count
from sbx_pre_orb_fd.man_prt_tif_v5_tas
group by level25_product_bp_nm;

-- 11. Связанные заявочные пары по исходному продукту TAS, как в знаменателе 10.
-- NULL-продукт источника показывается отдельной группой, без смены знаменателя.
select t.level25_product_bp_nm,
       count(distinct row(t.parent_application_rk, t.application_rk)) as linked_application_count
from sbx_pre_orb_fd.man_prt_tif_v5_tas t
where exists (
    select 1 from sbx_pre_orb_fd.man_prt_tif_v5_questionnaire_funnel f
    where f.parent_application_rk = t.parent_application_rk
      and f.application_rk = t.application_rk
)
group by t.level25_product_bp_nm;

-- 12. Пропавшие заявочные пары; ожидается пустой результат.
select t.parent_application_rk, t.application_rk
from sbx_pre_orb_fd.man_prt_tif_v5_tas t
where not exists (
    select 1 from sbx_pre_orb_fd.man_prt_tif_v5_tech_internet_funnel f
    where f.parent_application_rk = t.parent_application_rk
      and f.application_rk = t.application_rk
);

-- 13. Один номер на ID в мосте V5; ожидается пустой результат.
select questionnaire_id, count(*) as row_count
from sbx_pre_orb_fd.man_prt_tif_v5_questionnaire_numbers
group by questionnaire_id
having count(*) > 1;

-- 14. Текущая строка TQS по ID: ROW_NUMBER в intention не исправляет повторы TQS.
select questionnaire_id, count(*) as row_count
from sbx_pre_orb_fd.man_prt_tif_v5_questionnaire
group by questionnaire_id
having count(*) > 1;

-- 15. Повторы текущего ключа BDM для выбранных номеров; разбирать в источнике.
select app.application_rk, app.src_cd, count(*) as row_count
from bdm.application app
where app.effective_to_date = date '2999-12-31'
  and app.application_rk is not null and app.application_rk <> -1
  and exists (
      select 1 from sbx_pre_orb_fd.man_prt_tif_v5_questionnaire_numbers n
      where n.application_num = app.application_num
  )
group by app.application_rk, app.src_cd
having count(*) > 1;

-- 16. Разные непустые номера в RAW: сейчас по проверке пользователя пусто.
-- При появлении строк проверить номера, которые V5 оставил по приоритетам TQS.
select r.questionnaire_id, count(distinct r.application_num) as number_count
from rd_raw_orb.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention r
where r.application_num is not null
  and exists (
      select 1 from sbx_pre_orb_fd.man_prt_tif_v5_questionnaire_numbers n
      where n.questionnaire_id = r.questionnaire_id
  )
group by r.questionnaire_id
having count(distinct r.application_num) > 1;
