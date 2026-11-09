/*
СРАВНЕНИЕ СХОДИМОСТИ КН/КК: APPLICATION_NUM И COUNTERPARTY_RK.
Запускать ПО ПОРЯДКУ в одной сессии после построения V5.
Витрина и её таблицы не меняются; создаются четыре временные таблицы pg_temp.

Маршруты:
  APPLICATION_NUM: TQS -> intention (готовый мост V5) -> BDM.APPLICATION -> TAS.
  COUNTERPARTY_RK: TQS -> tech_questionnaire_x_customer по questionnaire_rk
    -> tech_customer_x_counterparty по customer_rk
    -> BDM.APPLICATION по counterparty_rk -> TAS.
Оба маршрута заканчиваются ОДИНАКОВО:
  BDM.application_rk = TAS.parent_application_rk,
  BDM.src_cd = TAS.parent_src_cd.
Прямой маршрут через TAS.application_rk здесь не добавляется.

Общая база: готовые таблицы V5 questionnaire / questionnaire_numbers / tas.
Отбор периода и продукта не пересчитывается. Если рабочие имена без v5_,
заменить эти три имени во всём файле. Взять таблицы одного запуска V5;
запускать сравнение при стабильных источниках. BDM для обоих маршрутов
считывается один раз в общий временный снимок. Поля TAS/анкеты не ранжируются.
NULL-продукты TAS сравниваются в той же базе, которая уже допущена в V5.

Макроподстановки:
  &db_sbx    — схема прототипа, по умолчанию sbx_pre_orb_fd.
  &p_db_cdmr — схема двух таблиц связей, предполагается dm_pik_fd_cdmr.
  &p_db_bdm  — схема APPLICATION, по умолчанию bdm.
  &p_max_date — текущая версия BDM, по умолчанию '2999-12-31'.

  &p_qc_current_condition — SQL-условие актуальности связи анкета/клиент,
      с алиасом qc. Из прежнего TQS известно условие:
      qc.effective_to_dttm = timestamp '2999-12-31'
  &p_cc_current_condition — SQL-условие актуальности связи клиент/контрагент,
      с алиасом cc. Поле/правило этой таблицы ПОКА НЕ ПОДТВЕРЖДЕНО.
      Если её контракт аналогичен TQXC, значение будет:
      cc.effective_to_dttm = timestamp '2999-12-31'
      Для подтверждённого неверсионного снимка можно указать true.
Условия подставляются как SQL без внешних кавычек. Не заменять их на true
только ради запуска: объединение всех исторических связей завысит кандидатов.
Схемы и названия полей актуальности сначала сверить по метаданным (SELECT 0).

DISTINCT в edges определяет множество различных связей для статистики;
он не исправляет исходники. Полные пути сохраняются в paths для контроля.
Несколько клиентов/контрагентов анкеты сохраняются без произвольного rn=1.
COUNTERPARTY_RK даёт кандидатов по клиенту: разные заявки одного клиента могут
не относиться к конкретной анкете. Рост процентов не доказывает корректность.

Результаты:
  0 — доступные поля/типы/схемы таблиц связей.
  1 — анкеты: общее число, связанные, процент по исходному продукту TQS.
  2 — пары TAS: общее число, связанные, процент по исходному продукту TAS.
  3 — какие анкеты покрывают оба маршрута, только один или ни один.
  4 — многозначность: число родителей и пар TAS на анкету.
  5 — примеры связей, найденных только через контрагента.
  6 — число исходных путей и различных связей: влияние повторных путей.
*/

-- SELECT 0. Необязательная проверка метаданных перед запуском расчёта.
select table_schema, table_name, column_name, data_type
from information_schema.columns
where table_name in ('tech_questionnaire_x_customer', 'tech_customer_x_counterparty')
order by table_schema, table_name, ordinal_position;

-- 1. Связи анкета -> клиент -> контрагент. Все текущие пути сохраняются.
drop table if exists pg_temp.man_prt_tif_cp_links;
create temporary table man_prt_tif_cp_links on commit preserve rows as (
select q.questionnaire_rk, q.level25_product_bp_nm,
       qc.customer_rk, cc.counterparty_rk
from &db_sbx.man_prt_tif_v5_questionnaire q
inner join &p_db_cdmr.tech_questionnaire_x_customer qc
    on qc.questionnaire_rk = q.questionnaire_rk
   and (&p_qc_current_condition)
inner join &p_db_cdmr.tech_customer_x_counterparty cc
    on cc.customer_rk = qc.customer_rk
   and (&p_cc_current_condition)
where q.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
  and qc.customer_rk is not null and qc.customer_rk <> -1
  and cc.counterparty_rk is not null and cc.counterparty_rk <> -1
) distributed by (questionnaire_rk);

-- 2. Общий снимок текущих заявок BDM, найденных хотя бы одним маршрутом.
drop table if exists pg_temp.man_prt_tif_cp_bdm;
create temporary table man_prt_tif_cp_bdm on commit preserve rows as (
select app.application_rk, app.src_cd, app.application_num, app.counterparty_rk
from &p_db_bdm.application app
where app.effective_to_date = cast(&p_max_date as date)
  and app.application_rk is not null and app.application_rk <> -1
  and (
      exists (
          select 1 from pg_temp.man_prt_tif_cp_links c
          where c.counterparty_rk = app.counterparty_rk
      )
      or exists (
          select 1
          from &db_sbx.man_prt_tif_v5_questionnaire_numbers n
          inner join &db_sbx.man_prt_tif_v5_questionnaire q
              on q.questionnaire_id = n.questionnaire_id
          where n.application_num = app.application_num
            and q.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
      )
  )
) distributed by (application_rk);

-- 3. Полные пути обоих маршрутов до одной и той же базы TAS.
drop table if exists pg_temp.man_prt_tif_cp_paths;
create temporary table man_prt_tif_cp_paths on commit preserve rows as (
select cast('APPLICATION_NUM' as text) as route,
       q.questionnaire_rk, q.level25_product_bp_nm as questionnaire_product,
       cast(null as bigint) as customer_rk, app.counterparty_rk,
       app.application_rk as bdm_application_rk, app.src_cd as bdm_src_cd,
       t.parent_application_rk, t.application_rk,
       t.level25_product_bp_nm as tas_product
from &db_sbx.man_prt_tif_v5_questionnaire q
inner join &db_sbx.man_prt_tif_v5_questionnaire_numbers n
    on n.questionnaire_id = q.questionnaire_id
inner join pg_temp.man_prt_tif_cp_bdm app
    on app.application_num = n.application_num
inner join &db_sbx.man_prt_tif_v5_tas t
    on t.parent_application_rk = app.application_rk
   and t.parent_src_cd = app.src_cd
where q.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
  and (t.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
       or t.level25_product_bp_nm is null)
union all
select cast('COUNTERPARTY_RK' as text),
       c.questionnaire_rk, c.level25_product_bp_nm,
       c.customer_rk, c.counterparty_rk,
       app.application_rk, app.src_cd,
       t.parent_application_rk, t.application_rk, t.level25_product_bp_nm
from pg_temp.man_prt_tif_cp_links c
inner join pg_temp.man_prt_tif_cp_bdm app
    on app.counterparty_rk = c.counterparty_rk
inner join &db_sbx.man_prt_tif_v5_tas t
    on t.parent_application_rk = app.application_rk
   and t.parent_src_cd = app.src_cd
where t.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
   or t.level25_product_bp_nm is null
) distributed by (questionnaire_rk);

-- 4. Множество связей для измерения покрытия, независимо от числа путей.
drop table if exists pg_temp.man_prt_tif_cp_edges;
create temporary table man_prt_tif_cp_edges on commit preserve rows as (
select distinct route, questionnaire_rk, questionnaire_product,
       parent_application_rk, application_rk, tas_product
from pg_temp.man_prt_tif_cp_paths
) distributed by (questionnaire_rk);

-- SELECT 1. Сходимость со стороны анкет, отдельно по продуктам TQS.
with products as (
    select cast('Потребкредит' as text) as product
    union all select cast('Кредитные карты' as text)
), routes as (
    select cast('APPLICATION_NUM' as text) as route
    union all select cast('COUNTERPARTY_RK' as text)
), totals as (
    select level25_product_bp_nm as product,
           count(distinct questionnaire_rk) as questionnaire_count
    from &db_sbx.man_prt_tif_v5_questionnaire
    where level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
    group by level25_product_bp_nm
), linked as (
    select route, questionnaire_product as product,
           count(distinct questionnaire_rk) as linked_questionnaire_count
    from pg_temp.man_prt_tif_cp_edges
    group by route, questionnaire_product
)
select p.product, r.route,
       coalesce(t.questionnaire_count, 0) as questionnaire_count,
       coalesce(l.linked_questionnaire_count, 0) as linked_questionnaire_count,
       round(100.0 * coalesce(l.linked_questionnaire_count, 0)
             / nullif(t.questionnaire_count, 0), 2) as questionnaire_link_pct
from products p cross join routes r
left join totals t on t.product = p.product
left join linked l on l.product = p.product and l.route = r.route
order by p.product, r.route;

-- SELECT 2. Обратная сходимость: пары TAS, отдельно по продуктам TAS.
-- NULL-продукт, если есть, остаётся отдельной группой с собственным знаменателем.
with products as (
    select cast('Потребкредит' as text) as product
    union select cast('Кредитные карты' as text)
    union select level25_product_bp_nm
          from &db_sbx.man_prt_tif_v5_tas where level25_product_bp_nm is null
), routes as (
    select cast('APPLICATION_NUM' as text) as route
    union all select cast('COUNTERPARTY_RK' as text)
), totals as (
    select level25_product_bp_nm as product,
           count(distinct row(parent_application_rk, application_rk)) as application_count
    from &db_sbx.man_prt_tif_v5_tas
    where level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
       or level25_product_bp_nm is null
    group by level25_product_bp_nm
), linked as (
    select route, tas_product as product,
           count(distinct row(parent_application_rk, application_rk)) as linked_application_count
    from pg_temp.man_prt_tif_cp_edges
    group by route, tas_product
)
select p.product, r.route,
       coalesce(t.application_count, 0) as application_count,
       coalesce(l.linked_application_count, 0) as linked_application_count,
       round(100.0 * coalesce(l.linked_application_count, 0)
             / nullif(t.application_count, 0), 2) as application_link_pct
from products p cross join routes r
left join totals t on t.product is not distinct from p.product
left join linked l on l.product is not distinct from p.product and l.route = r.route
order by p.product, r.route;

-- SELECT 3. Новые покрытые анкеты и потери относительно маршрута по номеру.
with q_entities as (
    select distinct questionnaire_rk, level25_product_bp_nm as product
    from &db_sbx.man_prt_tif_v5_questionnaire
    where level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
), flags as (
    select q.product, q.questionnaire_rk,
           exists (select 1 from pg_temp.man_prt_tif_cp_edges e
                   where e.route = 'APPLICATION_NUM'
                     and e.questionnaire_rk = q.questionnaire_rk
                     and e.questionnaire_product = q.product) as number_linked,
           exists (select 1 from pg_temp.man_prt_tif_cp_edges e
                   where e.route = 'COUNTERPARTY_RK'
                     and e.questionnaire_rk = q.questionnaire_rk
                     and e.questionnaire_product = q.product) as counterparty_linked
    from q_entities q
)
select product, count(*) as questionnaire_count,
       sum(case when number_linked and counterparty_linked then 1 else 0 end) as both_routes,
       sum(case when number_linked and not counterparty_linked then 1 else 0 end) as only_number,
       sum(case when not number_linked and counterparty_linked then 1 else 0 end) as only_counterparty,
       sum(case when not number_linked and not counterparty_linked then 1 else 0 end) as neither_route
from flags
group by product
order by product;

-- SELECT 4. Неоднозначность: несколько различных родителей/пар TAS на анкету.
with per_questionnaire as (
    select route, questionnaire_product, questionnaire_rk,
           count(distinct parent_application_rk) as parent_count,
           count(distinct row(parent_application_rk, application_rk)) as tas_pair_count
    from pg_temp.man_prt_tif_cp_edges
    group by route, questionnaire_product, questionnaire_rk
)
select route, questionnaire_product,
       count(*) as linked_questionnaire_count,
       sum(case when parent_count > 1 then 1 else 0 end) as questionnaires_with_multiple_parents,
       max(parent_count) as max_parents_per_questionnaire,
       max(tas_pair_count) as max_tas_pairs_per_questionnaire
from per_questionnaire
group by route, questionnaire_product
order by questionnaire_product, route;

-- SELECT 5. До 100 новых связей для предметной проверки правильности сопоставления.
select c.questionnaire_rk, c.questionnaire_product,
       c.parent_application_rk, c.application_rk, c.tas_product
from pg_temp.man_prt_tif_cp_edges c
where c.route = 'COUNTERPARTY_RK'
  and not exists (
      select 1 from pg_temp.man_prt_tif_cp_edges n
      where n.route = 'APPLICATION_NUM'
        and n.questionnaire_rk = c.questionnaire_rk
        and n.questionnaire_product = c.questionnaire_product
        and n.parent_application_rk = c.parent_application_rk
        and n.application_rk = c.application_rk
  )
order by c.questionnaire_product, c.questionnaire_rk,
         c.parent_application_rk, c.application_rk
limit 100;

-- SELECT 6. Сколько исходных путей приходится на множество найденных связей.
with paths as (
    select route, questionnaire_product, count(*) as raw_path_count
    from pg_temp.man_prt_tif_cp_paths
    group by route, questionnaire_product
), edges as (
    select route, questionnaire_product, count(*) as different_link_count
    from pg_temp.man_prt_tif_cp_edges
    group by route, questionnaire_product
)
select p.route, p.questionnaire_product, p.raw_path_count, e.different_link_count
from paths p
inner join edges e on e.route = p.route and e.questionnaire_product = p.questionnaire_product
order by p.questionnaire_product, p.route;
