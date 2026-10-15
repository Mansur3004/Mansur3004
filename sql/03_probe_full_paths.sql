/*
ЭТАП 2Б. Полные связи TQS -> TAS, без построения финальной витрины.
Запускать ПОСЛЕ 01_inventory.sql и 02_probe_uz.sql.

ДВА ИМЕНИ ТРЕБУЮТ ПРОВЕРКИ по этапу 1:
    sbx_pre_orb_fd.tech_questionnaire_status
    sbx_pre_orb_fd.tech_application_status
Они используются только при загрузке *_q_raw и *_tas_raw ниже.
Не подменять их сырым источником. Если TAS еще не построена, полный путь
проверить пока нельзя; этап 2А остается самостоятельным полезным результатом.

Версионность TQS: предварительно effective_to_dttm в дне 2999-12-31.
Версионность TAS: НЕ ПОДТВЕРЖДЕНА; здесь читается весь переданный объект.
До подтверждения snapshot-контракта или добавления реального фильтра
актуальности покрытия ниже являются исследовательскими, не приемочными.

Все соединения выполняются по сущностям, не по строкам истории статусов.
Внутренние *_entity_id — номера различных ключей в ЭТОМ запуске.
ROW_NUMBER не выбирает и не выбрасывает версии или спорные соответствия.
Префикс новых таблиц: man_qas_03_*. Исходные объекты не меняются.
*/

drop table if exists sbx_pre_orb_fd.man_qas_03_params;
create table sbx_pre_orb_fd.man_qas_03_params as
select begin_date, max_date, min_coverage_pct,
       false as tas_snapshot_confirmed
from sbx_pre_orb_fd.man_qas_02_params
distributed randomly;

drop table if exists sbx_pre_orb_fd.man_qas_03_q_raw;
create table sbx_pre_orb_fd.man_qas_03_q_raw as
select
    q.questionnaire_rk, q.questionnaire_id, q.src_cd as q_src_cd,
    q.questionnaire_dttm, q.effective_from_dttm, q.effective_to_dttm,
    q.product_type_cd, q.level25_product_bp_nm,
    case
        when q.src_cd like '1388%' then 'AUTO'
        when q.src_cd like '1376%' then 'KN'
        when q.src_cd like '1383%' then 'KK'
    end as branch
from sbx_pre_orb_fd.tech_questionnaire_status q
cross join sbx_pre_orb_fd.man_qas_03_params p
where q.effective_to_dttm >= cast(p.max_date as timestamp)
  and q.effective_to_dttm < timestamp '3000-01-01 00:00:00'
  and (q.questionnaire_dttm >= cast(p.begin_date as timestamp)
       or q.questionnaire_dttm is null)
  and (q.src_cd like '1388%' or q.src_cd like '1376%' or q.src_cd like '1383%')
distributed randomly;

drop table if exists sbx_pre_orb_fd.man_qas_03_tas_raw;
create table sbx_pre_orb_fd.man_qas_03_tas_raw as
select
    t.parent_application_rk, t.parent_src_cd,
    t.application_rk, t.application_id, t.src_cd as app_src_cd,
    t.application_dt, t.processed_dttm,
    case
        when t.src_cd = 'ALPP' then 'AUTO'
        when t.src_cd = 'MSCL' then 'KN'
        when t.src_cd in ('CCPP_CRCA', 'CCPP_BATR') then 'KK'
        when t.src_cd = 'MSSA' then 'UZ'
    end as branch
from sbx_pre_orb_fd.tech_application_status t
cross join sbx_pre_orb_fd.man_qas_03_params p
where t.src_cd in ('ALPP', 'MSCL', 'CCPP_CRCA', 'CCPP_BATR', 'MSSA')
  and (t.application_dt >= p.begin_date or t.application_dt is null)
-- ЗДЕСЬ добавить подтвержденный фильтр актуальности, если TAS версионная.
-- processed_dttm намеренно не используется для удаления строк.
distributed randomly;

drop table if exists sbx_pre_orb_fd.man_qas_03_q_entity;
create table sbx_pre_orb_fd.man_qas_03_q_entity as
select row_number() over (order by q_src_cd, questionnaire_rk) as q_entity_id,
       questionnaire_rk, q_src_cd, branch
from (
    select distinct questionnaire_rk, q_src_cd, branch
    from sbx_pre_orb_fd.man_qas_03_q_raw
    where questionnaire_rk is not null
) d
distributed randomly;

drop table if exists sbx_pre_orb_fd.man_qas_03_tas_entity;
create table sbx_pre_orb_fd.man_qas_03_tas_entity as
select row_number() over (
           order by app_src_cd, application_rk,
                    parent_src_cd nulls first, parent_application_rk nulls first
       ) as app_entity_id,
       application_rk, app_src_cd, parent_application_rk, parent_src_cd, branch
from (
    select distinct application_rk, app_src_cd,
           parent_application_rk, parent_src_cd, branch
    from sbx_pre_orb_fd.man_qas_03_tas_raw
    where application_rk is not null
) d
distributed randomly;

-- Мост нужен именно потому, что application_num отсутствует в DDL TQS.
-- Неоднозначные соответствия сохраняются для измерения, не схлопываются.
drop table if exists sbx_pre_orb_fd.man_qas_03_q_bdm;
create table sbx_pre_orb_fd.man_qas_03_q_bdm as
select distinct q.q_entity_id, q.branch, a.application_rk, a.app_src_cd
from sbx_pre_orb_fd.man_qas_03_q_entity q
join sbx_pre_orb_fd.man_qas_03_q_raw r
  on r.questionnaire_rk = q.questionnaire_rk and r.q_src_cd = q.q_src_cd
join sbx_pre_orb_fd.man_qas_02_q_num n
  on n.questionnaire_id = r.questionnaire_id and n.q_src_cd = r.q_src_cd
join sbx_pre_orb_fd.man_qas_02_app a
  on a.application_num = n.application_num
where q.branch in ('KN', 'KK')
  and (a.app_src_cd = 'MSSA' or exists (
      select 1
      from sbx_pre_orb_fd.man_qas_02_source_rules sr
      where sr.branch = q.branch and sr.expected_app_src = a.app_src_cd
  ))
distributed randomly;

-- Маппинги строковых ID не включаются в зерно сущности; если ID на одном
-- ключе несколько, AUTO_ID проверит все и контроль ниже покажет конфликт.
drop table if exists sbx_pre_orb_fd.man_qas_03_auto_q_ids;
create table sbx_pre_orb_fd.man_qas_03_auto_q_ids as
select distinct q.q_entity_id, r.questionnaire_id
from sbx_pre_orb_fd.man_qas_03_q_entity q
join sbx_pre_orb_fd.man_qas_03_q_raw r
  on r.questionnaire_rk = q.questionnaire_rk and r.q_src_cd = q.q_src_cd
where q.branch = 'AUTO'
  and nullif(btrim(r.questionnaire_id), '') is not null
distributed randomly;

drop table if exists sbx_pre_orb_fd.man_qas_03_auto_app_ids;
create table sbx_pre_orb_fd.man_qas_03_auto_app_ids as
select distinct t.app_entity_id, r.application_id
from sbx_pre_orb_fd.man_qas_03_tas_entity t
join sbx_pre_orb_fd.man_qas_03_tas_raw r
  on r.application_rk = t.application_rk and r.app_src_cd = t.app_src_cd
 and r.parent_application_rk is not distinct from t.parent_application_rk
 and r.parent_src_cd is not distinct from t.parent_src_cd
where t.branch = 'AUTO'
  and nullif(btrim(r.application_id), '') is not null
distributed randomly;

analyze sbx_pre_orb_fd.man_qas_03_q_bdm;
analyze sbx_pre_orb_fd.man_qas_03_q_entity;
analyze sbx_pre_orb_fd.man_qas_03_tas_entity;

drop table if exists sbx_pre_orb_fd.man_qas_03_edges;
create table sbx_pre_orb_fd.man_qas_03_edges as
select distinct cast('AUTO' as text) as branch, cast('AUTO_ID' as text) as route,
       q.q_entity_id, t.app_entity_id
from sbx_pre_orb_fd.man_qas_03_auto_q_ids q
join sbx_pre_orb_fd.man_qas_03_auto_app_ids t
  on q.questionnaire_id = t.application_id
union all
select distinct b.branch, 'DIRECT_PRODUCT', b.q_entity_id, t.app_entity_id
from sbx_pre_orb_fd.man_qas_03_q_bdm b
join sbx_pre_orb_fd.man_qas_03_tas_entity t
  on t.application_rk = b.application_rk and t.app_src_cd = b.app_src_cd
where b.app_src_cd <> 'MSSA'
union all
select distinct b.branch, 'UZ_SELF', b.q_entity_id, t.app_entity_id
from sbx_pre_orb_fd.man_qas_03_q_bdm b
join sbx_pre_orb_fd.man_qas_03_tas_entity t
  on t.application_rk = b.application_rk and t.app_src_cd = 'MSSA'
where b.app_src_cd = 'MSSA'
union all
select distinct b.branch, 'UZ_PARENT', b.q_entity_id, t.app_entity_id
from sbx_pre_orb_fd.man_qas_03_q_bdm b
join sbx_pre_orb_fd.man_qas_03_tas_entity t
  on t.parent_application_rk = b.application_rk and t.parent_src_cd = 'MSSA'
 and t.branch = b.branch
where b.app_src_cd = 'MSSA'
distributed randomly;

drop table if exists sbx_pre_orb_fd.man_qas_03_q_degree;
create table sbx_pre_orb_fd.man_qas_03_q_degree as
select branch, route, q_entity_id, count(*) as application_count
from sbx_pre_orb_fd.man_qas_03_edges
group by branch, route, q_entity_id
distributed randomly;

drop table if exists sbx_pre_orb_fd.man_qas_03_app_degree;
create table sbx_pre_orb_fd.man_qas_03_app_degree as
select branch, route, app_entity_id, count(*) as questionnaire_count
from sbx_pre_orb_fd.man_qas_03_edges
group by branch, route, app_entity_id
distributed randomly;

drop table if exists sbx_pre_orb_fd.man_qas_03_report;
create table sbx_pre_orb_fd.man_qas_03_report as
with route_scope as (
    select cast('AUTO' as text) as branch, cast('AUTO_ID' as text) as route,
           cast('AUTO' as text) as target_branch
    union all select 'KN', 'DIRECT_PRODUCT', 'KN'
    union all select 'KN', 'UZ_SELF', 'UZ'
    union all select 'KN', 'UZ_PARENT', 'KN'
    union all select 'KK', 'DIRECT_PRODUCT', 'KK'
    union all select 'KK', 'UZ_SELF', 'UZ'
    union all select 'KK', 'UZ_PARENT', 'KK'
), q_totals as (
    select branch, count(*) as q_total
    from sbx_pre_orb_fd.man_qas_03_q_entity group by branch
), app_totals as (
    select branch, count(*) as app_total
    from sbx_pre_orb_fd.man_qas_03_tas_entity group by branch
), q_matches as (
    select branch, route, count(*) as q_matched,
           sum(case when application_count > 1 then 1 else 0 end) as q_with_many_apps
    from sbx_pre_orb_fd.man_qas_03_q_degree group by branch, route
), app_matches as (
    select branch, route, count(*) as app_matched,
           sum(case when questionnaire_count > 1 then 1 else 0 end) as apps_with_many_q
    from sbx_pre_orb_fd.man_qas_03_app_degree group by branch, route
), pairs as (
    select branch, route, count(*) as pair_count
    from sbx_pre_orb_fd.man_qas_03_edges group by branch, route
), many_to_many as (
    select e.branch, e.route, count(*) as many_to_many_pairs
    from sbx_pre_orb_fd.man_qas_03_edges e
    join sbx_pre_orb_fd.man_qas_03_q_degree q
      on q.branch = e.branch and q.route = e.route and q.q_entity_id = e.q_entity_id
    join sbx_pre_orb_fd.man_qas_03_app_degree a
      on a.branch = e.branch and a.route = e.route and a.app_entity_id = e.app_entity_id
    where q.application_count > 1 and a.questionnaire_count > 1
    group by e.branch, e.route
)
select s.branch, s.route, s.target_branch,
       coalesce(q.q_total, 0) as q_total,
       coalesce(m.q_matched, 0) as q_matched,
       coalesce(q.q_total, 0) - coalesce(m.q_matched, 0) as q_unmatched,
       round(100.0 * coalesce(m.q_matched, 0) / nullif(q.q_total, 0), 2) as q_coverage_pct,
       coalesce(t.app_total, 0) as app_total,
       coalesce(a.app_matched, 0) as app_matched,
       coalesce(t.app_total, 0) - coalesce(a.app_matched, 0) as app_unmatched,
       round(100.0 * coalesce(a.app_matched, 0) / nullif(t.app_total, 0), 2) as app_coverage_pct,
       round(100.0 * (coalesce(m.q_matched, 0) + coalesce(a.app_matched, 0)) /
             nullif(coalesce(q.q_total, 0) + coalesce(t.app_total, 0), 0), 2) as entity_coverage_pct,
       coalesce(p.pair_count, 0) as pair_count,
       coalesce(m.q_with_many_apps, 0) as q_with_many_apps,
       coalesce(a.apps_with_many_q, 0) as apps_with_many_q,
       coalesce(mm.many_to_many_pairs, 0) as many_to_many_pairs,
       cfg.tas_snapshot_confirmed,
       case when cfg.tas_snapshot_confirmed then 'SNAPSHOT_CONFIRMED_BY_USER'
            else 'UNCONFIRMED_TAS_SNAPSHOT' end as version_assumption,
       case when coalesce(q.q_total, 0) = 0 then 'NO_QUESTIONNAIRES'
            when 100.0 * coalesce(m.q_matched, 0) / nullif(q.q_total, 0)
                 >= cfg.min_coverage_pct then 'Q_COVERAGE_REACHES_10_PERCENT'
            else 'Q_COVERAGE_BELOW_10_PERCENT' end as coverage_observation
from route_scope s
cross join sbx_pre_orb_fd.man_qas_03_params cfg
left join q_totals q on q.branch = s.branch
left join app_totals t on t.branch = s.target_branch
left join q_matches m on m.branch = s.branch and m.route = s.route
left join app_matches a on a.branch = s.branch and a.route = s.route
left join pairs p on p.branch = s.branch and p.route = s.route
left join many_to_many mm on mm.branch = s.branch and mm.route = s.route
distributed randomly;

-- Результат 1: сравнение полных путей, без заявления готовности витрины.
-- UZ_SELF имеет ДРУГОЙ набор целевых заявок (MSSA): нельзя сравнивать
-- его app_coverage_pct с продуктовыми путями как одну и ту же когорту.
select branch, route, q_total, q_matched, q_coverage_pct,
       pair_count, many_to_many_pairs, tas_snapshot_confirmed
from sbx_pre_orb_fd.man_qas_03_report order by branch, route;

-- Результат 1б: знаменатель заявок отличается для UZ_SELF.
select branch, route, target_branch, app_total, app_matched,
       app_coverage_pct, entity_coverage_pct
from sbx_pre_orb_fd.man_qas_03_report order by branch, route;

-- Результат 1в: степени связи. Несколько дочерних заявок на УЗ могут быть
-- корректны; N:M нельзя принимать без объяснения бизнес-смысла.
select branch, route, q_with_many_apps, apps_with_many_q,
       many_to_many_pairs, coverage_observation
from sbx_pre_orb_fd.man_qas_03_report order by branch, route;

-- Результат 2: повторы текущего ключа TQS. Их нужно исследовать ДО
-- присоединения всех статусных атрибутов к будущей итоговой витрине.
select q_src_cd, count(*) as repeated_key_groups, sum(n - 1) as extra_rows
from (
    select q_src_cd, questionnaire_rk, count(*) as n
    from sbx_pre_orb_fd.man_qas_03_q_raw
    group by q_src_cd, questionnaire_rk having count(*) > 1
) d group by q_src_cd order by q_src_cd;

-- Результат 3: повторы ключа TAS, включая различные обработанные версии.
select app_src_cd, count(*) as repeated_key_groups, sum(n - 1) as extra_rows
from (
    select app_src_cd, application_rk, parent_application_rk,
           parent_src_cd, count(*) as n
    from sbx_pre_orb_fd.man_qas_03_tas_raw
    group by app_src_cd, application_rk, parent_application_rk, parent_src_cd
    having count(*) > 1
) d group by app_src_cd order by app_src_cd;

-- Результат 4: полнота входных ключей и дат; отсутствующие даты сохранены
-- в исследуемой базе, но требуют решения о включении в итоговую когорту.
select cast('TQS' as text) as input_name, count(*) as source_rows,
       sum(case when questionnaire_rk is null then 1 else 0 end) as null_rk_rows,
       sum(case when nullif(btrim(questionnaire_id), '') is null then 1 else 0 end) as empty_text_id_rows,
       sum(case when questionnaire_dttm is null then 1 else 0 end) as null_date_rows
from sbx_pre_orb_fd.man_qas_03_q_raw
union all
select 'TAS', count(*),
       sum(case when application_rk is null then 1 else 0 end),
       sum(case when nullif(btrim(application_id), '') is null then 1 else 0 end),
       sum(case when application_dt is null then 1 else 0 end)
from sbx_pre_orb_fd.man_qas_03_tas_raw;

-- Результат 5: проверка классификации источника по продукту TQS.
select branch, q_src_cd, product_type_cd, level25_product_bp_nm, count(*) as source_rows
from sbx_pre_orb_fd.man_qas_03_q_raw
group by branch, q_src_cd, product_type_cd, level25_product_bp_nm
order by branch, source_rows desc;

-- Результат 6: пересечение прямой и родительской продуктовой связи.
-- Каждая пара считается один раз вне зависимости от числа путей.
with pair_paths as (
    select branch, q_entity_id, app_entity_id,
           max(case when route = 'DIRECT_PRODUCT' then 1 else 0 end) as has_direct,
           max(case when route = 'UZ_PARENT' then 1 else 0 end) as has_uz_parent
    from sbx_pre_orb_fd.man_qas_03_edges
    where route in ('DIRECT_PRODUCT', 'UZ_PARENT')
    group by branch, q_entity_id, app_entity_id
)
select branch, has_direct, has_uz_parent, count(*) as pair_count
from pair_paths group by branch, has_direct, has_uz_parent
order by branch, has_direct desc, has_uz_parent desc;

-- Результат 7: контроль конфликтов текстового ID на выбранном ключе.
select cast('TQS' as text) as input_name, count(*) as keys_with_multiple_text_ids
from (
    select q_src_cd, questionnaire_rk
    from sbx_pre_orb_fd.man_qas_03_q_raw
    group by q_src_cd, questionnaire_rk
    having count(distinct questionnaire_id) > 1
) q
union all
select 'TAS', count(*)
from (
    select app_src_cd, application_rk, parent_src_cd, parent_application_rk
    from sbx_pre_orb_fd.man_qas_03_tas_raw
    group by app_src_cd, application_rk, parent_src_cd, parent_application_rk
    having count(distinct application_id) > 1
) t;

-- Результат 8: сколько анкет TQS вообще нашли номер в исходной выборке.
-- Позволяет отличить проблему моста TQS->номер от проблемы номера->BDM.
with bridge_q as (
    select distinct q.q_entity_id
    from sbx_pre_orb_fd.man_qas_03_q_entity q
    join sbx_pre_orb_fd.man_qas_03_q_raw r
      on r.questionnaire_rk = q.questionnaire_rk and r.q_src_cd = q.q_src_cd
    join sbx_pre_orb_fd.man_qas_02_q_num n
      on n.questionnaire_id = r.questionnaire_id and n.q_src_cd = r.q_src_cd
    where q.branch in ('KN', 'KK')
)
select q.branch, count(*) as tqs_q_total,
       count(b.q_entity_id) as q_with_number,
       round(100.0 * count(b.q_entity_id) / nullif(count(*), 0), 2) as number_coverage_pct
from sbx_pre_orb_fd.man_qas_03_q_entity q
left join bridge_q b on b.q_entity_id = q.q_entity_id
where q.branch in ('KN', 'KK')
group by q.branch order by q.branch;
