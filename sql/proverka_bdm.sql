/*
ПРОВЕРКА КРАТНОСТИ ШАГА 1.4: АНКЕТА -> НОМЕР -> BDM.APPLICATION.
Каждый SELECT отдельно. Таблицы не создаются, рабочие скрипты не меняются.
Имена таблиц соответствуют скриншоту. Для V5 заменить man_prt_tif_questionnaire
и man_prt_tif_questionnaire_numbers на одноимённые таблицы man_prt_tif_v5_.
Дата текущей версии должна совпадать с p_max_date рабочего запуска.

Ключ application_rk не гарантирует уникальность поля application_num,
по которому выполняется JOIN. Фильтры IS NOT NULL / <> -1 не убирают повторы.
1 — повторы ровно той же выходной связи; ожидается пусто.
2 — номер находит несколько текущих строк BDM: это НЕ обязательно дубли;
    different_bdm_links>1 означает разные ключи/источники, их нельзя слепо схлопывать.
3 — сколько реально совпавших строк отсекают условия на RK; ожидаются нули.
4/5 — входные нарушения, способные размножить строки даже при корректной BDM.
Нулевой результат 3 показывает отсутствие влияния условий на этом срезе,
но не заменяет контракт источника: NOT NULL и отсутствие служебного RK=-1.
*/

-- 1. Повтор одной выходной связи, с текущими условиями рабочего JOIN.
select q.questionnaire_rk, q.level25_product_bp_nm,
       app.application_rk, app.src_cd, count(*) as duplicate_count
from sbx_pre_orb_fd.man_prt_tif_questionnaire q
inner join sbx_pre_orb_fd.man_prt_tif_questionnaire_numbers n
    on n.questionnaire_id = q.questionnaire_id
inner join bdm.application app
    on app.application_num = n.application_num
   and app.effective_to_date = date '2999-12-31'
   and app.application_rk is not null
   and app.application_rk <> -1
where q.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
group by q.questionnaire_rk, q.level25_product_bp_nm,
         app.application_rk, app.src_cd
having count(*) > 1
order by q.questionnaire_rk, q.level25_product_bp_nm, app.application_rk, app.src_cd;

-- 2. Кратность именно поиска по номеру, без размножения входами TIF.
select app.application_num,
       count(*) as current_bdm_rows,
       count(distinct row(app.application_rk, app.src_cd)) as different_bdm_links
from bdm.application app
where app.effective_to_date = date '2999-12-31'
  and app.application_rk is not null
  and app.application_rk <> -1
  and exists (
      select 1
      from sbx_pre_orb_fd.man_prt_tif_questionnaire_numbers n
      inner join sbx_pre_orb_fd.man_prt_tif_questionnaire q
          on q.questionnaire_id = n.questionnaire_id
      where n.application_num = app.application_num
        and q.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
  )
group by app.application_num
having count(*) > 1
order by app.application_num;

-- 3. Эти условия намеренно НЕ включены в WHERE: измеряем, что они отсекают.
-- Считаются строки BDM, а не количество путей из повторяющихся q/n.
select
    count(*) as matched_current_bdm_rows,
    count(case when app.application_rk is null then 1 end) as null_rk_rows,
    count(case when app.application_rk = -1 then 1 end) as sentinel_rk_rows
from bdm.application app
where app.effective_to_date = date '2999-12-31'
  and exists (
      select 1
      from sbx_pre_orb_fd.man_prt_tif_questionnaire_numbers n
      inner join sbx_pre_orb_fd.man_prt_tif_questionnaire q
          on q.questionnaire_id = n.questionnaire_id
      where n.application_num = app.application_num
        and q.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
  );

-- 4. Должна быть одна текущая строка анкеты на ID в рассматриваемой базе.
select q.questionnaire_id, count(*) as questionnaire_rows
from sbx_pre_orb_fd.man_prt_tif_questionnaire q
where q.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
  and exists (
      select 1 from sbx_pre_orb_fd.man_prt_tif_questionnaire_numbers n
      where n.questionnaire_id = q.questionnaire_id
  )
group by q.questionnaire_id
having count(*) > 1
order by q.questionnaire_id;

-- 5. После rn=1 в мосте должна быть одна строка на ID; ожидается пусто.
select n.questionnaire_id, count(*) as number_rows
from sbx_pre_orb_fd.man_prt_tif_questionnaire_numbers n
where exists (
    select 1 from sbx_pre_orb_fd.man_prt_tif_questionnaire q
    where q.questionnaire_id = n.questionnaire_id
      and q.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
)
group by n.questionnaire_id
having count(*) > 1
order by n.questionnaire_id;
