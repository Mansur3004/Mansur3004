/*
ДИАГНОСТИКА СХОДИМОСТИ TECH_INTERNET_FUNNEL. Greenplum.
Основной прототип и его результаты не пересоздаются. Пишутся только prt_ifd_*.
Запускать последовательно, останавливаясь при ошибке. Параметры периода,
источников и имена таблиц должны соответствовать ОДНОМУ запуску прототипа.

Макропеременные (подстановка SQL-клиентом; таблицы параметров нет):
  &db_sbx - схема проверок; по умолчанию: sbx_pre_orb_fd
  &p_db_cdmr - схема TAS/связи RK; по умолчанию: dm_pik_fd_cdmr
  &p_db_bdm - схема BDM; по умолчанию: bdm
  &p_funnel_table - полное имя фактического итога без кавычек;
                    по умолчанию: sbx_pre_orb_fd.prt_if2_tech_internet_funnel
                    Если ваш итог называется man_prot_tif_tech_internet_funnel,
                    указать sbx_pre_orb_fd.man_prot_tif_tech_internet_funnel.
  &P_BEGIN_DATE - начало когорты, как при построении; по умолчанию: '2025-01-01'
  &p_max_date - конец актуальной версии; по умолчанию: '2999-12-31'
  &p_quest_25lvl_product_kn_list - по умолчанию: 'Потребкредит'
  &p_quest_25lvl_product_kk_list - по умолчанию: 'Кредитные карты'
  &p_quest_25lvl_product_auto_list - по умолчанию: 'Автокредит'
  &P_UZ_SRC - по умолчанию: 'MSSA'
  &P_KN_SRC - по умолчанию: 'MSCL'
  &P_KK_SRC - по умолчанию: 'CCPP_CRCA', 'CCPP_BATR'
  &P_AUTO_SRC - по умолчанию: 'ALPP'

Разделам 2–4 нужны промежуточные таблицы ТОГО ЖЕ запуска:
  &p_kn_numbers_table - по умолчанию: sbx_pre_orb_fd.prt_if2_kn_kk_verification
  &p_kn_bdm_table - по умолчанию: sbx_pre_orb_fd.prt_if2_kn_kk_bdm
  &p_kn_matches_table - по умолчанию: sbx_pre_orb_fd.prt_if2_kn_kk_matches
  &p_auto_q_table - по умолчанию: sbx_pre_orb_fd.prt_if2_auto_verification
  &p_tqs_all_table - по умолчанию: sbx_pre_orb_fd.prt_if2_tqs_questionnaire_all
Имена таблиц задаются без кавычек. При переименовании указать фактические имена.

Раздел 1 можно выполнить отдельно: он читает только итог и готовую TAS.
Разделы 2–4 выполняются после 1. Раздел 4 читает историю BDM и может быть тяжелым.
Ключи сначала группируются: нет нескольких COUNT DISTINCT в одном запросе.
GROUP BY/JOIN тоже требуют памяти; расход на банковских объемах не измерен.

ВАЖНО: ограничение TAS тремя level25-продуктами — диагностический сценарий.
УЗ с другим названием/NULL показываются отдельно и не исчезают из исходной базы.
Новую базу приемки надо согласовать; проверки основной прототип не меняют.
В итоговом продукте COALESCE(TAS.level25, TQS.level25), поэтому он не позволяет
восстановить исходный продукт анкеты. Продукты анкет проверяются по промежуточным
таблицам в разделе 2; продукты заявок — по готовой TAS. Связанность означает
наличие хотя бы одной связи в итого́вой витрине, независимо от продукта второй стороны.
Изменение TAS после запуска может дать расхождение; это проверяется в 1.8.
*/

-- ==================== 1. БАЗА TAS И ТРИ ПРОДУКТА ====================

-- Шаг 1.1. Узкая копия итога для последовательных проверок.
-- Источник: &p_funnel_table.
drop table if exists &db_sbx.prt_ifd_final;
create table &db_sbx.prt_ifd_final
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select questionnaire_rk, questionnaire_dttm,
       parent_application_rk, application_rk,
       parent_application_dt, application_dt, level25_product_bp_nm
from &p_funnel_table
) distributed randomly;

-- Шаг 1.2. Одна анкета и признак хотя бы одной связи; исходная база TQS.
-- Источник: 1.1.
drop table if exists &db_sbx.prt_ifd_final_q;
create table &db_sbx.prt_ifd_final_q
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select questionnaire_rk,
       max(case when parent_application_rk is not null or application_rk is not null
                then 1 else 0 end) as linked_flg
from &db_sbx.prt_ifd_final
where questionnaire_rk is not null
group by questionnaire_rk
) distributed by (questionnaire_rk);

-- Шаг 1.3. Одна пара RK и признак хотя бы одной анкеты; исходная база TAS.
-- Источник: 1.1.
drop table if exists &db_sbx.prt_ifd_final_a;
create table &db_sbx.prt_ifd_final_a
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select parent_application_rk, application_rk,
       max(case when questionnaire_rk is not null then 1 else 0 end) as linked_flg
from &db_sbx.prt_ifd_final
where parent_application_rk is not null or application_rk is not null
group by parent_application_rk, application_rk
) distributed by (parent_application_rk, application_rk);

-- Отчет 1.3. Оба исходных процента. Сверить с 34,51% / 8,61% при тех же данных.
select q.questionnaire_count, q.linked_questionnaire_count,
       round(100.0 * q.linked_questionnaire_count / nullif(q.questionnaire_count, 0), 2) as questionnaire_link_pct,
       a.application_count, a.linked_application_count,
       round(100.0 * a.linked_application_count / nullif(a.application_count, 0), 2) as application_link_pct
from (select count(*) as questionnaire_count, coalesce(sum(linked_flg), 0) as linked_questionnaire_count
      from &db_sbx.prt_ifd_final_q) q
cross join (select count(*) as application_count, coalesce(sum(linked_flg), 0) as linked_application_count
            from &db_sbx.prt_ifd_final_a) a;

-- Шаг 1.4. Состав TAS до фильтра продуктом; исходный отбор источников отмечен флагом.
-- Источник: dm_pik_fd_cdmr.tech_application_status.
drop table if exists &db_sbx.prt_ifd_tas;
create table &db_sbx.prt_ifd_tas
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select nullif(t.parent_application_rk, -1) as parent_application_rk,
       nullif(t.application_rk, -1) as application_rk,
       t.application_id, t.parent_src_cd, t.src_cd,
       t.parent_application_dt, t.application_dt, t.level25_product_bp_nm,
       case when (t.src_cd in (&P_KN_SRC, &P_KK_SRC, &P_UZ_SRC, &P_AUTO_SRC)
          or (t.src_cd is null and t.parent_src_cd = &P_UZ_SRC)) then 1 else 0 end as prototype_source_flg,
       case when t.level25_product_bp_nm in (&p_quest_25lvl_product_kn_list,
              &p_quest_25lvl_product_kk_list, &p_quest_25lvl_product_auto_list) then 1 else 0 end as target_product_flg,
       case when coalesce(t.application_dt, t.parent_application_dt) >= cast(&P_BEGIN_DATE as date)
                 or coalesce(t.application_dt, t.parent_application_dt) is null
            then 1 else 0 end as period_flg
from &p_db_cdmr.tech_application_status t
where (t.src_cd in (&P_KN_SRC, &P_KK_SRC, &P_UZ_SRC, &P_AUTO_SRC)
          or (t.src_cd is null and t.parent_src_cd = &P_UZ_SRC)) or t.level25_product_bp_nm in (&p_quest_25lvl_product_kn_list,
              &p_quest_25lvl_product_kk_list, &p_quest_25lvl_product_auto_list)
) distributed randomly;

-- Отчет 1.4. Продукты/источники/даты TAS. Считаются СТРОКИ, не уникальные заявки.
select level25_product_bp_nm, src_cd, parent_src_cd,
       prototype_source_flg, target_product_flg, period_flg,
       count(*) as source_rows,
       sum(case when parent_application_rk is null and application_rk is null then 1 else 0 end) as rows_without_both_rk,
       sum(case when application_dt is null and parent_application_dt is null then 1 else 0 end) as rows_without_date
from &db_sbx.prt_ifd_tas
group by level25_product_bp_nm, src_cd, parent_src_cd,
         prototype_source_flg, target_product_flg, period_flg
order by source_rows desc;

-- Шаг 1.5. Уникальные пары по исходному продукту TAS и факт связи в итоге.
-- Равенства с признаком NULL допускают hash join и не приравнивают настоящий RK=0 к NULL.
-- Источник: 1.4 и пары итога 1.3.
drop table if exists &db_sbx.prt_ifd_tas_product;
create table &db_sbx.prt_ifd_tas_product
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select t.parent_application_rk, t.application_rk, t.level25_product_bp_nm,
       max(t.prototype_source_flg) as prototype_source_flg,
       max(t.target_product_flg) as target_product_flg,
       min(coalesce(t.application_dt, t.parent_application_dt)) as cohort_dt,
       max(case when t.application_dt is null and t.parent_application_dt is null then 1 else 0 end) as missing_date_flg,
       max(coalesce(a.linked_flg, 0)) as linked_flg
from &db_sbx.prt_ifd_tas t
left join &db_sbx.prt_ifd_final_a a
  on coalesce(a.parent_application_rk, 0) = coalesce(t.parent_application_rk, 0)
 and (a.parent_application_rk is null) = (t.parent_application_rk is null)
 and coalesce(a.application_rk, 0) = coalesce(t.application_rk, 0)
 and (a.application_rk is null) = (t.application_rk is null)
where t.period_flg = 1
  and (t.parent_application_rk is not null or t.application_rk is not null)
group by t.parent_application_rk, t.application_rk, t.level25_product_bp_nm
) distributed by (parent_application_rk, application_rk);

-- Отчет 1.5. Покрытие каждого продукта TAS. Прочие названия и NULL видны отдельно.
select level25_product_bp_nm, prototype_source_flg, target_product_flg,
       count(*) as application_count, sum(linked_flg) as linked_application_count,
       round(100.0 * sum(linked_flg) / nullif(count(*), 0), 2) as application_link_pct
from &db_sbx.prt_ifd_tas_product
group by level25_product_bp_nm, prototype_source_flg, target_product_flg
order by prototype_source_flg desc, application_count desc;

-- Шаг 1.6. Одна пара для общего знаменателя; несколько названий не удваивают пару.
-- Источник: 1.5, только источники исходного прототипа.
drop table if exists &db_sbx.prt_ifd_tas_keys;
create table &db_sbx.prt_ifd_tas_keys
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select parent_application_rk, application_rk,
       max(target_product_flg) as target_product_flg,
       max(linked_flg) as linked_flg, count(*) as product_labels_count
from &db_sbx.prt_ifd_tas_product
where prototype_source_flg = 1
group by parent_application_rk, application_rk
) distributed by (parent_application_rk, application_rk);

-- Отчет 1.6. Старая база, только три продукта и остаток. Исходный процент не подменяется.
select '01_final_original' as scope, count(*) as application_count,
       coalesce(sum(linked_flg), 0) as linked_application_count,
       round(100.0 * sum(linked_flg) / nullif(count(*), 0), 2) as application_link_pct
from &db_sbx.prt_ifd_final_a
union all
select '02_tas_prototype_sources', count(*), coalesce(sum(linked_flg), 0),
       round(100.0 * sum(linked_flg) / nullif(count(*), 0), 2)
from &db_sbx.prt_ifd_tas_keys
union all
select '03_tas_three_products', count(*), coalesce(sum(linked_flg), 0),
       round(100.0 * sum(linked_flg) / nullif(count(*), 0), 2)
from &db_sbx.prt_ifd_tas_keys where target_product_flg = 1
union all
select '04_tas_only_other_or_null_product', count(*), coalesce(sum(linked_flg), 0),
       round(100.0 * sum(linked_flg) / nullif(count(*), 0), 2)
from &db_sbx.prt_ifd_tas_keys where target_product_flg = 0
order by scope;

-- Отчет 1.7. Покрытие по месяцам и виду заявки; отдельно УЗ без дочки, NULL и будущие даты.
select t.level25_product_bp_nm, date_trunc('month', t.cohort_dt) as cohort_month,
       case when t.application_rk is null then 'parent_only'
            when t.parent_application_rk is null then 'application_only'
            else 'parent_and_application' end as application_kind,
       count(*) as application_count, sum(t.linked_flg) as linked_application_count,
       sum(t.missing_date_flg) as pairs_with_missing_date,
       sum(case when t.cohort_dt > current_date then 1 else 0 end) as pairs_with_future_date,
       round(100.0 * sum(t.linked_flg) / nullif(count(*), 0), 2) as application_link_pct
from &db_sbx.prt_ifd_tas_product t
where t.prototype_source_flg = 1
group by t.level25_product_bp_nm, date_trunc('month', t.cohort_dt),
         case when t.application_rk is null then 'parent_only'
              when t.parent_application_rk is null then 'application_only'
              else 'parent_and_application' end
order by t.level25_product_bp_nm, cohort_month, application_kind;

-- Отчет 1.8. Потери ключей, разные запуски, неоднозначные продукты и пустые идентификаторы.
select 'tas_pair_absent_from_final' as issue, count(*) as pair_count
from &db_sbx.prt_ifd_tas_keys t
where not exists (
  select 1 from &db_sbx.prt_ifd_final_a a
  where coalesce(a.parent_application_rk, 0) = coalesce(t.parent_application_rk, 0)
    and (a.parent_application_rk is null) = (t.parent_application_rk is null)
    and coalesce(a.application_rk, 0) = coalesce(t.application_rk, 0)
    and (a.application_rk is null) = (t.application_rk is null))
union all
select 'final_pair_absent_from_current_tas_cohort', count(*)
from &db_sbx.prt_ifd_final_a a
where not exists (
  select 1 from &db_sbx.prt_ifd_tas_keys t
  where coalesce(a.parent_application_rk, 0) = coalesce(t.parent_application_rk, 0)
    and (a.parent_application_rk is null) = (t.parent_application_rk is null)
    and coalesce(a.application_rk, 0) = coalesce(t.application_rk, 0)
    and (a.application_rk is null) = (t.application_rk is null))
union all
select 'tas_pair_with_multiple_product_labels', count(*)
from &db_sbx.prt_ifd_tas_keys where product_labels_count > 1
union all
select 'final_row_without_any_rk', count(*)
from &db_sbx.prt_ifd_final
where questionnaire_rk is null and parent_application_rk is null and application_rk is null;

-- ==================== 2. АНКЕТЫ И МЕСТО ОБРЫВА КН/КК ====================

-- Шаг 2.1. Все сохранившиеся номера, включая NULL, в когорте КН/КК.
-- Источник: &p_kn_numbers_table, шаг 1.7 V2.
drop table if exists &db_sbx.prt_ifd_kn_numbers;
create table &db_sbx.prt_ifd_kn_numbers
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select distinct questionnaire_id, questionnaire_rk, questionnaire_dttm,
       level25_product_bp_nm, application_num
from &p_kn_numbers_table
where questionnaire_dttm >= cast(&P_BEGIN_DATE as timestamp) or questionnaire_dttm is null
) distributed by (questionnaire_rk);

-- Шаг 2.2. Исходные продукты анкет до COALESCE с TAS; месяц и факт сохранения.
-- Источник: 2.1, &p_auto_q_table и итог 1.2.
drop table if exists &db_sbx.prt_ifd_q_product;
create table &db_sbx.prt_ifd_q_product
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
with q as (
  select questionnaire_rk, level25_product_bp_nm, questionnaire_dttm
  from &db_sbx.prt_ifd_kn_numbers
  union all
  select questionnaire_rk, level25_product_bp_nm, questionnaire_dttm
  from &p_auto_q_table
  where questionnaire_dttm >= cast(&P_BEGIN_DATE as timestamp) or questionnaire_dttm is null
)
select q.questionnaire_rk, q.level25_product_bp_nm,
       min(q.questionnaire_dttm) as questionnaire_dttm,
       max(coalesce(f.linked_flg, 0)) as linked_flg,
       max(case when f.questionnaire_rk is not null then 1 else 0 end) as present_in_final_flg
from q left join &db_sbx.prt_ifd_final_q f on f.questionnaire_rk = q.questionnaire_rk
where q.questionnaire_rk is not null
group by q.questionnaire_rk, q.level25_product_bp_nm
) distributed by (questionnaire_rk);

-- Отчет 2.2. TQS → TAS по исходному продукту анкеты; суммы продуктов могут повторять RK.
select level25_product_bp_nm, count(*) as questionnaire_count,
       sum(linked_flg) as linked_questionnaire_count,
       sum(case when present_in_final_flg = 0 then 1 else 0 end) as absent_from_final_count,
       round(100.0 * sum(linked_flg) / nullif(count(*), 0), 2) as questionnaire_link_pct
from &db_sbx.prt_ifd_q_product
group by level25_product_bp_nm
order by level25_product_bp_nm;

-- Отчет 2.3. Сдвиг периодов: сравнить месяцы анкет с месяцами TAS из 1.7.
select level25_product_bp_nm, date_trunc('month', questionnaire_dttm) as cohort_month,
       count(*) as questionnaire_count, sum(linked_flg) as linked_questionnaire_count,
       round(100.0 * sum(linked_flg) / nullif(count(*), 0), 2) as questionnaire_link_pct
from &db_sbx.prt_ifd_q_product
group by level25_product_bp_nm, date_trunc('month', questionnaire_dttm)
order by level25_product_bp_nm, cohort_month;

-- Шаг 2.4. Одна анкета и этап потери связи, без умножения на количество номеров.
-- Источник: 2.1, сохраненные мост BDM и найденные пары V2.
drop table if exists &db_sbx.prt_ifd_kn_stage;
create table &db_sbx.prt_ifd_kn_stage
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
with q as (
  select questionnaire_rk, level25_product_bp_nm,
         max(case when application_num is not null then 1 else 0 end) as has_number_flg,
         max(case when nullif(btrim(application_num), '') is not null then 1 else 0 end) as has_nonblank_number_flg
  from &db_sbx.prt_ifd_kn_numbers
  group by questionnaire_rk, level25_product_bp_nm
), b as (
  select questionnaire_rk, level25_product_bp_nm,
         max(case when bdm_application_rk is not null then 1 else 0 end) as bdm_found_flg
  from &p_kn_bdm_table
  group by questionnaire_rk, level25_product_bp_nm
), m as (
  select q_questionnaire_rk, q_level25_product_bp_nm, 1 as matched_flg
  from &p_kn_matches_table
  group by q_questionnaire_rk, q_level25_product_bp_nm
)
select q.questionnaire_rk, q.level25_product_bp_nm, q.has_number_flg, q.has_nonblank_number_flg,
       coalesce(b.bdm_found_flg, 0) as bdm_found_flg, coalesce(m.matched_flg, 0) as matched_flg,
       case when m.matched_flg = 1 then '04_matched_tas'
            when q.has_number_flg = 0 then '01_no_application_num'
            when coalesce(b.bdm_found_flg, 0) = 0 then '02_no_bdm_under_prototype_filters'
            else '03_bdm_found_no_tas_match' end as lost_at
from q
left join b on b.questionnaire_rk = q.questionnaire_rk and b.level25_product_bp_nm = q.level25_product_bp_nm
left join m on m.q_questionnaire_rk = q.questionnaire_rk and m.q_level25_product_bp_nm = q.level25_product_bp_nm
) distributed by (questionnaire_rk);

-- Отчет 2.4. Взаимоисключающие причины на уровне анкеты: сумма равна базе КН/КК.
select level25_product_bp_nm, lost_at, count(*) as questionnaire_count,
       sum(case when has_number_flg = 1 and has_nonblank_number_flg = 0 then 1 else 0 end) as only_blank_numbers_count
from &db_sbx.prt_ifd_kn_stage
group by level25_product_bp_nm, lost_at
order by level25_product_bp_nm, lost_at;

-- Отчет 2.5. Примеры несвязанных анкет для ручной проверки, до 50 строк.
select n.questionnaire_id, n.questionnaire_rk, n.level25_product_bp_nm,
       n.questionnaire_dttm, n.application_num, s.lost_at
from &db_sbx.prt_ifd_kn_numbers n
inner join &db_sbx.prt_ifd_kn_stage s
  on s.questionnaire_rk = n.questionnaire_rk and s.level25_product_bp_nm = n.level25_product_bp_nm
where s.matched_flg = 0
limit 50;

-- Шаг 2.6. Потеря до измеренной базы TQS из-за отсутствия RK при исходном INNER JOIN.
-- Источник: &p_tqs_all_table и актуальная TECH_QUESTIONNAIRE_X_CUSTOMER.
drop table if exists &db_sbx.prt_ifd_pre_rk;
create table &db_sbx.prt_ifd_pre_rk
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
with q as (
  select questionnaire_id, level25_product_bp_nm, min(questionnaire_dttm) as questionnaire_dttm
  from &p_tqs_all_table
  group by questionnaire_id, level25_product_bp_nm
), rk as (
  select questionnaire_id,
         max(case when questionnaire_rk is not null then 1 else 0 end) as has_rk_flg
  from &p_db_cdmr.tech_questionnaire_x_customer
  where effective_to_dttm = cast(&p_max_date as timestamp)
  group by questionnaire_id
)
select q.questionnaire_id, q.level25_product_bp_nm, coalesce(rk.has_rk_flg, 0) as has_rk_flg
from q left join rk on rk.questionnaire_id = q.questionnaire_id
where q.questionnaire_dttm >= cast(&P_BEGIN_DATE as timestamp) or q.questionnaire_dttm is null
) distributed randomly;

-- Отчет 2.6. Отсутствие RK уменьшает исходную базу; это не только несвязанные анкеты итога.
select level25_product_bp_nm, has_rk_flg, count(*) as questionnaire_id_count
from &db_sbx.prt_ifd_pre_rk
group by level25_product_bp_nm, has_rk_flg
order by level25_product_bp_nm, has_rk_flg;

-- ==================== 3. ОБА МАРШРУТА И АВТО ====================

-- Шаг 3.1. Кандидаты обоих маршрутов независимо от link_mode, без фильтра TAS тремя продуктами.
-- Источник: сохраненный мост BDM и TAS 1.4 с исходными периодом/источниками.
drop table if exists &db_sbx.prt_ifd_routes;
create table &db_sbx.prt_ifd_routes
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select distinct q.questionnaire_rk, q.level25_product_bp_nm as questionnaire_product,
       t.parent_application_rk, t.application_rk, t.level25_product_bp_nm as tas_product,
       t.target_product_flg,
       case when q.bdm_src_cd <> &P_UZ_SRC then 'DIRECT'
            when t.src_cd = &P_UZ_SRC then 'UZ_SELF'
            else 'UZ_PARENT' end as route
from &p_kn_bdm_table q
inner join &db_sbx.prt_ifd_tas t
  on t.prototype_source_flg = 1 and t.period_flg = 1
 and ((q.bdm_src_cd <> &P_UZ_SRC and t.application_rk = q.bdm_application_rk and t.src_cd = q.bdm_src_cd)
   or (q.bdm_src_cd = &P_UZ_SRC
       and ((t.parent_application_rk = q.bdm_application_rk and t.parent_src_cd = &P_UZ_SRC
             and ((q.level25_product_bp_nm = cast(&p_quest_25lvl_product_kn_list as text) and t.src_cd = &P_KN_SRC)
               or (q.level25_product_bp_nm = cast(&p_quest_25lvl_product_kk_list as text) and t.src_cd in (&P_KK_SRC))
               or t.src_cd is null))
         or (t.application_rk = q.bdm_application_rk and t.src_cd = &P_UZ_SRC))))
) distributed by (questionnaire_rk);

-- Отчет 3.1. Продукт анкеты против TAS. Строгий фильтр удалит кандидатов с target_product_flg = 0.
select questionnaire_product, tas_product, route, target_product_flg, count(*) as candidate_pair_count
from &db_sbx.prt_ifd_routes
group by questionnaire_product, tas_product, route, target_product_flg
order by questionnaire_product, candidate_pair_count desc;

-- Шаг 3.2. Одна анкета: прямой путь, УЗ или оба; их охваты нельзя просто складывать.
-- Источник: 3.1.
drop table if exists &db_sbx.prt_ifd_route_q;
create table &db_sbx.prt_ifd_route_q
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select questionnaire_rk, questionnaire_product,
       max(case when route = 'DIRECT' then 1 else 0 end) as direct_flg,
       max(case when route in ('UZ_PARENT', 'UZ_SELF') then 1 else 0 end) as uz_flg,
       max(target_product_flg) as any_target_product_flg
from &db_sbx.prt_ifd_routes
group by questionnaire_rk, questionnaire_product
) distributed by (questionnaire_rk);

-- Отчет 3.2. Охват маршрутов, их пересечение и потеря при фильтре TAS тремя продуктами.
select questionnaire_product, direct_flg, uz_flg, any_target_product_flg,
       count(*) as questionnaire_count
from &db_sbx.prt_ifd_route_q
group by questionnaire_product, direct_flg, uz_flg, any_target_product_flg
order by questionnaire_product, direct_flg, uz_flg;

-- Шаг 3.3. Авто: точное совпадение ID, исключение периодом/продуктом и непригодный RK.
-- Источник: подготовленные авто-анкеты и TAS 1.4, включая старые даты.
drop table if exists &db_sbx.prt_ifd_auto_ids;
create table &db_sbx.prt_ifd_auto_ids
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select q.questionnaire_id, q.questionnaire_rk,
       max(case when t.application_id is not null then 1 else 0 end) as exact_id_found_flg,
       max(case when t.period_flg = 1 then 1 else 0 end) as exact_id_in_period_flg,
       max(case when t.period_flg = 1 and t.target_product_flg = 1 then 1 else 0 end) as exact_id_target_product_flg,
       max(case when t.period_flg = 1 and t.level25_product_bp_nm = cast(&p_quest_25lvl_product_auto_list as text)
                then 1 else 0 end) as exact_id_auto_product_flg,
       max(case when t.period_flg = 1 and (t.application_rk is not null or t.parent_application_rk is not null)
                then 1 else 0 end) as usable_pair_in_period_flg
from &p_auto_q_table q
left join &db_sbx.prt_ifd_tas t on t.application_id = q.questionnaire_id and t.src_cd = &P_AUTO_SRC
group by q.questionnaire_id, q.questionnaire_rk
) distributed by (questionnaire_rk);

-- Отчет 3.3. Авто: нет ID вообще, есть только вне периода, другой/NULL продукт, нет пригодного RK.
select exact_id_found_flg, exact_id_in_period_flg, exact_id_target_product_flg, exact_id_auto_product_flg,
       usable_pair_in_period_flg, count(*) as questionnaire_count
from &db_sbx.prt_ifd_auto_ids
group by exact_id_found_flg, exact_id_in_period_flg, exact_id_target_product_flg, exact_id_auto_product_flg, usable_pair_in_period_flg
order by exact_id_found_flg, exact_id_in_period_flg;

-- Отчет 3.4. Пустые номера/внешние пробелы мешают точному равенству. Номера автоматически не исправляются.
select level25_product_bp_nm, count(*) as questionnaire_number_rows,
       sum(case when application_num is null then 1 else 0 end) as null_number_rows,
       sum(case when application_num is not null and btrim(application_num) = '' then 1 else 0 end) as blank_number_rows,
       sum(case when application_num <> btrim(application_num) then 1 else 0 end) as outer_space_number_rows
from &db_sbx.prt_ifd_kn_numbers
group by level25_product_bp_nm;

-- ==================== 4. ПОЧЕМУ BDM НЕ ПРОПУСТИЛ НОМЕР ====================
-- Дополнительный раздел читает BDM без ограничения текущей версией.

-- Шаг 4.1. Последовательно проверить для номера те же условия, что в JOIN прототипа.
-- Источник: 2.1 и история bdm.application.
drop table if exists &db_sbx.prt_ifd_bdm_reasons;
create table &db_sbx.prt_ifd_bdm_reasons
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
with q as (
  select application_num, level25_product_bp_nm
  from &db_sbx.prt_ifd_kn_numbers
  where application_num is not null
  group by application_num, level25_product_bp_nm
)
select q.application_num, q.level25_product_bp_nm,
       max(case when a.application_num is not null then 1 else 0 end) as any_bdm_flg,
       max(case when a.effective_to_date = cast(&p_max_date as date) then 1 else 0 end) as current_bdm_flg,
       max(case when a.effective_to_date = cast(&p_max_date as date) and (a.src_cd = &P_UZ_SRC
               or (q.level25_product_bp_nm = cast(&p_quest_25lvl_product_kn_list as text) and a.src_cd = &P_KN_SRC)
               or (q.level25_product_bp_nm = cast(&p_quest_25lvl_product_kk_list as text) and a.src_cd in (&P_KK_SRC))) then 1 else 0 end) as current_source_flg,
       max(case when a.effective_to_date = cast(&p_max_date as date) and (a.src_cd = &P_UZ_SRC
               or (q.level25_product_bp_nm = cast(&p_quest_25lvl_product_kn_list as text) and a.src_cd = &P_KN_SRC)
               or (q.level25_product_bp_nm = cast(&p_quest_25lvl_product_kk_list as text) and a.src_cd in (&P_KK_SRC))) and a.application_rk is not null and a.application_rk <> -1 then 1 else 0 end) as current_source_key_flg,
       max(case when a.effective_to_date = cast(&p_max_date as date) and (a.src_cd = &P_UZ_SRC
               or (q.level25_product_bp_nm = cast(&p_quest_25lvl_product_kn_list as text) and a.src_cd = &P_KN_SRC)
               or (q.level25_product_bp_nm = cast(&p_quest_25lvl_product_kk_list as text) and a.src_cd in (&P_KK_SRC))) and a.application_rk is not null and a.application_rk <> -1 and a.application_begin_date >= cast(&P_BEGIN_DATE as date)
                then 1 else 0 end) as all_filters_flg
from q left join &p_db_bdm.application a on a.application_num = q.application_num
group by q.application_num, q.level25_product_bp_nm
) distributed randomly;

-- Отчет 4.1. Причины на уровне номера+продукта, НЕ анкеты. Удачи одного из ее номеров достаточно.
select level25_product_bp_nm,
       case when any_bdm_flg = 0 then '01_number_absent_from_bdm'
            when current_bdm_flg = 0 then '02_no_current_version'
            when current_source_flg = 0 then '03_source_not_allowed'
            when current_source_key_flg = 0 then '04_invalid_rk'
            when all_filters_flg = 0 then '05_begin_date_old_or_null'
            else '06_passes_all_bdm_filters' end as reason,
       count(*) as number_product_count
from &db_sbx.prt_ifd_bdm_reasons
group by level25_product_bp_nm,
         case when any_bdm_flg = 0 then '01_number_absent_from_bdm'
              when current_bdm_flg = 0 then '02_no_current_version'
              when current_source_flg = 0 then '03_source_not_allowed'
              when current_source_key_flg = 0 then '04_invalid_rk'
              when all_filters_flg = 0 then '05_begin_date_old_or_null'
              else '06_passes_all_bdm_filters' end
order by level25_product_bp_nm, reason;

/*
ЧТО НЕЛЬЗЯ ДОКАЗАТЬ ЭТИМИ ДАННЫМИ:
1. Заявка TAS без анкеты не обязательно относится к другому каналу.
   В показанном составе TAS нет канала. Нужен подтвержденный источник канала
   заявки и правило связи с application_rk/parent_application_rk.
   Поле channel в RAW описывает имеющиеся анкеты и само по себе не классифицирует
   все несвязанные заявки TAS. Канал по отсутствию связи не восстанавливать.
2. Здесь не повторяется очистка RAW. Потери до tqs_questionnaire_all потребуют
   отдельного анализа RAW; действующие фильтры не меняются.
3. УЗ с продуктом вне трех имен может законно входить в воронку. Сценарий 03
   не заменяет 01 до согласования правил включения таких УЗ.
4. Несколько продуктов одной пары/одного RK делают суммы продуктовых отчетов
   неаддитивными. Общие знаменатели считаются отдельно по ключам.
5. Отчеты маршрутов — кандидаты при обоих способах. Их правильность и параметры
   реального запуска проверять по примерам; автоматически новые связи не записываются.
*/
