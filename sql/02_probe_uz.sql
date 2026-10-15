/*
ЭТАП 2А. Проверяем первый участок связи: анкета -> bdm.application.
TAS пока не требуется. Полный путь до TAS этот этап НЕ доказывает.
Диалект: Greenplum. Рабочий источник анкет взят со скриншота:
sbx_pre_orb_fd.man_prt_tqs_questionnaire.
Если его нет, сначала требуется построить эту выборку по существующему ETL.
Не заменять источник анкет на TQS без проверки наличия application_num.

Префикс создаваемых таблиц: sbx_pre_orb_fd.man_qas_02_*.
Исходные таблицы и существующий ETL не изменяются.
Выполнять последовательно, одним соединением, с остановкой на ошибке.
На больших объемах сначала EXPLAIN SELECT-частей двух загрузок ниже.
*/

drop table if exists sbx_pre_orb_fd.man_qas_02_params;
create table sbx_pre_orb_fd.man_qas_02_params as
select
    date '2025-01-01' as begin_date,
    date '2999-12-31' as max_date,
    cast(10.0 as numeric) as min_coverage_pct
distributed randomly;

-- Префиксы восстановлены из макропеременных. Это диагностическая
-- классификация по источнику, не окончательная продуктовая классификация.
-- Проверка product_type_cd обязательна по результату 2 ниже.
drop table if exists sbx_pre_orb_fd.man_qas_02_source_rules;
create table sbx_pre_orb_fd.man_qas_02_source_rules as
select cast('KN' as text) as branch, cast('1376%' as text) as q_src_pattern,
       cast('MSCL' as text) as expected_app_src
union all select 'KK', '1383%', 'CCPP_CRCA'
union all select 'KK', '1383%', 'CCPP_BATR'
union all select 'AUTO', '1388%', 'ALPP'
distributed randomly;

-- Читаем только нужные поля. Здесь намеренно нет персональных данных.
-- Сохраняем исходные строковые ключи: не удаляем пробелы/нули молча.
-- В выборке со скриншота уже были отсечены тестовые анкеты и период < 2025.
-- Убедиться, что фактическая версия этой таблицы имеет те же фильтры.
drop table if exists sbx_pre_orb_fd.man_qas_02_q_raw;
create table sbx_pre_orb_fd.man_qas_02_q_raw as
select
    cast(q.questionnaire_id as text) as questionnaire_id,
    cast(q.application_num as text) as application_num,
    cast(q.src_cd as text) as q_src_cd,
    cast(q.product_type_cd as text) as product_type_cd,
    case
        when q.src_cd like '1376%' then 'KN'
        when q.src_cd like '1383%' then 'KK'
        when q.src_cd like '1388%' then 'AUTO'
        else 'OUT_OF_SCOPE'
    end as branch
from sbx_pre_orb_fd.man_prt_tqs_questionnaire q
distributed randomly;

-- Единица первой диагностики: (questionnaire_id, q_src_cd).
-- Это бизнес-ключ для исследования, а не подтвержденный PK TQS.
-- Статусы не размножают знаменатель; неоднозначные номера не выбираются
-- произвольно, а остаются в таблице соответствий и отдельном контроле.
drop table if exists sbx_pre_orb_fd.man_qas_02_q_entity;
create table sbx_pre_orb_fd.man_qas_02_q_entity as
select distinct questionnaire_id, q_src_cd, branch
from sbx_pre_orb_fd.man_qas_02_q_raw
where nullif(btrim(questionnaire_id), '') is not null
  and nullif(btrim(q_src_cd), '') is not null
distributed randomly;

drop table if exists sbx_pre_orb_fd.man_qas_02_q_num;
create table sbx_pre_orb_fd.man_qas_02_q_num as
select distinct questionnaire_id, q_src_cd, branch, application_num
from sbx_pre_orb_fd.man_qas_02_q_raw
where nullif(btrim(questionnaire_id), '') is not null
  and nullif(btrim(q_src_cd), '') is not null
  and nullif(btrim(application_num), '') is not null
distributed randomly;

-- В BDM поле effective_to_date подтверждено скриншотом.
-- Сначала сохраняем повторы, чтобы затем измерить их, а не спрятать.
drop table if exists sbx_pre_orb_fd.man_qas_02_app_raw;
create table sbx_pre_orb_fd.man_qas_02_app_raw as
select a.application_rk, a.application_num, a.src_cd as app_src_cd
from bdm.application a
cross join sbx_pre_orb_fd.man_qas_02_params p
where a.effective_to_date = p.max_date
  and a.application_begin_date >= p.begin_date
  and a.src_cd in ('MSSA', 'MSCL', 'CCPP_CRCA', 'CCPP_BATR')
distributed randomly;

drop table if exists sbx_pre_orb_fd.man_qas_02_app;
create table sbx_pre_orb_fd.man_qas_02_app as
select distinct application_rk, application_num, app_src_cd
from sbx_pre_orb_fd.man_qas_02_app_raw
where application_rk is not null
  and nullif(btrim(application_num), '') is not null
distributed randomly;

analyze sbx_pre_orb_fd.man_qas_02_q_num;
analyze sbx_pre_orb_fd.man_qas_02_app;

-- Сравниваем УЗ и прямой продуктовый источник в ОДНОЙ когорте.
-- Чужие продуктовые источники не добавляют покрытия ветке.
drop table if exists sbx_pre_orb_fd.man_qas_02_edges;
create table sbx_pre_orb_fd.man_qas_02_edges as
select distinct
    q.questionnaire_id, q.q_src_cd, q.branch, q.application_num,
    a.application_rk, a.app_src_cd
from sbx_pre_orb_fd.man_qas_02_q_num q
join sbx_pre_orb_fd.man_qas_02_app a
  on q.application_num = a.application_num
where q.branch in ('KN', 'KK')
  and (
      a.app_src_cd = 'MSSA'
      or exists (
          select 1
          from sbx_pre_orb_fd.man_qas_02_source_rules r
          where r.branch = q.branch and r.expected_app_src = a.app_src_cd
      )
  )
distributed randomly;

-- Сравниваем каждую группу источников и объединение прямых источников КК.
drop table if exists sbx_pre_orb_fd.man_qas_02_route_edges;
create table sbx_pre_orb_fd.man_qas_02_route_edges as
select distinct
    branch, questionnaire_id, q_src_cd,
    cast('UZ_MSSA' as text) as route, application_rk, app_src_cd
from sbx_pre_orb_fd.man_qas_02_edges
where app_src_cd = 'MSSA'
union all
select distinct
    branch, questionnaire_id, q_src_cd,
    'DIRECT_PRODUCT', application_rk, app_src_cd
from sbx_pre_orb_fd.man_qas_02_edges
where app_src_cd <> 'MSSA'
distributed randomly;

drop table if exists sbx_pre_orb_fd.man_qas_02_q_degree;
create table sbx_pre_orb_fd.man_qas_02_q_degree as
select branch, route, questionnaire_id, q_src_cd, count(*) as application_count
from sbx_pre_orb_fd.man_qas_02_route_edges
group by branch, route, questionnaire_id, q_src_cd
distributed randomly;

drop table if exists sbx_pre_orb_fd.man_qas_02_app_degree;
create table sbx_pre_orb_fd.man_qas_02_app_degree as
select branch, route, application_rk, app_src_cd, count(*) as questionnaire_count
from sbx_pre_orb_fd.man_qas_02_route_edges
group by branch, route, application_rk, app_src_cd
distributed randomly;

drop table if exists sbx_pre_orb_fd.man_qas_02_report;
create table sbx_pre_orb_fd.man_qas_02_report as
with routes as (
    select cast('UZ_MSSA' as text) as route
    union all select 'DIRECT_PRODUCT'
), branches as (
    select distinct branch
    from sbx_pre_orb_fd.man_qas_02_source_rules
    where branch in ('KN', 'KK')
), totals as (
    select b.branch, count(q.questionnaire_id) as q_total
    from branches b
    left join sbx_pre_orb_fd.man_qas_02_q_entity q on q.branch = b.branch
    group by b.branch
), matched as (
    select branch, route, count(*) as q_matched,
           sum(case when application_count > 1 then 1 else 0 end) as q_with_many_apps
    from sbx_pre_orb_fd.man_qas_02_q_degree
    group by branch, route
), matched_apps as (
    select branch, route, count(*) as app_matched,
           sum(case when questionnaire_count > 1 then 1 else 0 end) as apps_with_many_q
    from sbx_pre_orb_fd.man_qas_02_app_degree
    group by branch, route
), pairs as (
    select branch, route, count(*) as pair_count
    from sbx_pre_orb_fd.man_qas_02_route_edges
    group by branch, route
), many_to_many as (
    select e.branch, e.route, count(*) as many_to_many_pairs
    from sbx_pre_orb_fd.man_qas_02_route_edges e
    join sbx_pre_orb_fd.man_qas_02_q_degree q
      on q.branch = e.branch and q.route = e.route
     and q.questionnaire_id = e.questionnaire_id and q.q_src_cd = e.q_src_cd
    join sbx_pre_orb_fd.man_qas_02_app_degree a
      on a.branch = e.branch and a.route = e.route
     and a.application_rk = e.application_rk and a.app_src_cd = e.app_src_cd
    where q.application_count > 1 and a.questionnaire_count > 1
    group by e.branch, e.route
)
select
    t.branch, r.route, t.q_total,
    coalesce(m.q_matched, 0) as q_matched,
    t.q_total - coalesce(m.q_matched, 0) as q_unmatched,
    round(100.0 * coalesce(m.q_matched, 0) / nullif(t.q_total, 0), 2) as q_coverage_pct,
    coalesce(a.app_matched, 0) as app_matched,
    coalesce(p.pair_count, 0) as pair_count,
    coalesce(m.q_with_many_apps, 0) as q_with_many_apps,
    coalesce(a.apps_with_many_q, 0) as apps_with_many_q,
    coalesce(mm.many_to_many_pairs, 0) as many_to_many_pairs,
    case
        when t.q_total = 0 then 'NO_QUESTIONNAIRES'
        when 100.0 * coalesce(m.q_matched, 0) / nullif(t.q_total, 0)
             >= cfg.min_coverage_pct then 'FIRST_LEG_REACHES_10_PERCENT'
        else 'FIRST_LEG_BELOW_10_PERCENT'
    end as preliminary_result
from totals t
cross join routes r
cross join sbx_pre_orb_fd.man_qas_02_params cfg
left join matched m on m.branch = t.branch and m.route = r.route
left join matched_apps a on a.branch = t.branch and a.route = r.route
left join pairs p on p.branch = t.branch and p.route = r.route
left join many_to_many mm on mm.branch = t.branch and mm.route = r.route
distributed randomly;

-- Результат 1: первый участок. 10% здесь НЕ доказывает 10% связи TQS--TAS.
select branch, route, q_total, q_matched, q_coverage_pct, pair_count
from sbx_pre_orb_fd.man_qas_02_report order by branch, route;

-- Результат 1б: размножение связей, отдельно для удобства скриншотов.
select branch, route, app_matched, q_with_many_apps,
       apps_with_many_q, many_to_many_pairs
from sbx_pre_orb_fd.man_qas_02_report order by branch, route;

-- Результат 2: фактический состав продуктов/источников.
-- Количество ниже — строки промежуточной выборки, не уникальные анкеты.
select branch, q_src_cd, product_type_cd, count(*) as source_rows
from sbx_pre_orb_fd.man_qas_02_q_raw
group by branch, q_src_cd, product_type_cd
order by branch, source_rows desc, q_src_cd, product_type_cd;

-- Результат 3: качество входа. Пустые ключи нельзя соединять друг с другом.
select
    count(*) as source_rows,
    sum(case when nullif(btrim(questionnaire_id), '') is null then 1 else 0 end) as empty_q_id_rows,
    sum(case when nullif(btrim(q_src_cd), '') is null then 1 else 0 end) as empty_q_src_rows,
    sum(case when nullif(btrim(application_num), '') is null then 1 else 0 end) as empty_app_num_rows,
    sum(case when application_num <> btrim(application_num) then 1 else 0 end) as app_num_with_spaces_rows
from sbx_pre_orb_fd.man_qas_02_q_raw;

-- Результат 4: один ключ анкеты с несколькими номерами заявки.
-- Сами ключи не выводим: для обмена скриншотами достаточно агрегатов.
select branch, count(*) as q_with_multiple_application_nums, max(num_count) as max_num_count
from (
    select branch, questionnaire_id, q_src_cd, count(*) as num_count
    from sbx_pre_orb_fd.man_qas_02_q_num
    group by branch, questionnaire_id, q_src_cd
    having count(*) > 1
) d
group by branch
order by branch;

-- Результат 5: повторяющиеся связи BDM после фильтра актуальности.
select app_src_cd, count(*) as duplicate_mapping_groups,
       sum(row_count - 1) as extra_rows
from (
    select application_rk, application_num, app_src_cd, count(*) as row_count
    from sbx_pre_orb_fd.man_qas_02_app_raw
    group by application_rk, application_num, app_src_cd
    having count(*) > 1
) d
group by app_src_cd
order by app_src_cd;

-- Результат 6: один номер -> несколько ключей внутри одного источника.
select app_src_cd, count(*) as ambiguous_num_groups, max(rk_count) as max_rk_count
from (
    select app_src_cd, application_num, count(distinct application_rk) as rk_count
    from sbx_pre_orb_fd.man_qas_02_app
    group by app_src_cd, application_num
    having count(distinct application_rk) > 1
) d
group by app_src_cd
order by app_src_cd;

-- Результат 7: что добавляет УЗ относительно прямой продуктовой связи.
-- Считаем ВСЕ анкеты KN/KK, включая анкеты без application_num.
with flags as (
    select q.branch, q.questionnaire_id, q.q_src_cd,
           max(case when e.app_src_cd = 'MSSA' then 1 else 0 end) as has_uz,
           max(case when e.app_src_cd <> 'MSSA' then 1 else 0 end) as has_product
    from sbx_pre_orb_fd.man_qas_02_q_entity q
    left join sbx_pre_orb_fd.man_qas_02_edges e
      on e.branch = q.branch and e.questionnaire_id = q.questionnaire_id
     and e.q_src_cd = q.q_src_cd
    where q.branch in ('KN', 'KK')
    group by q.branch, q.questionnaire_id, q.q_src_cd
)
select branch, has_uz, has_product, count(*) as questionnaire_count
from flags
group by branch, has_uz, has_product
order by branch, has_uz desc, has_product desc;

-- Результат 8: кого исключили из знаменателя из-за непригодного ключа.
-- Это не разрешение исключать таких строк из будущей итоговой витрины.
select branch, count(*) as source_rows,
       count(distinct questionnaire_id) as distinct_q_id_without_src
from sbx_pre_orb_fd.man_qas_02_q_raw
where nullif(btrim(questionnaire_id), '') is null
   or nullif(btrim(q_src_cd), '') is null
group by branch
order by branch;
