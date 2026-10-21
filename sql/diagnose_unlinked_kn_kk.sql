/*
КН/КК: ПОЧЕМУ ЗАЯВКИ TAS ОСТАЛИСЬ БЕЗ АНКЕТЫ. Greenplum.
Начинаем с пар TAS, а не с анкет. Цель — разложить 36 882 454 пары по причинам.
Прототип не пересобирается. Создаются только диагностические prt_ifr_*.
Все запросы выполнять ПОСЛЕДОВАТЕЛЬНО, с остановкой при ошибке.

Макропеременные:
  &db_sbx = sbx_pre_orb_fd                  — схема результатов проверок
  &p_db_bdm = bdm                          — схема BDM
  &p_db_rawd = rd_raw_orb                   — схема RAW (только раздел 4)
  &P_BEGIN_DATE = '2025-01-01'              — как в проверяемом запуске
  &p_max_date = '2999-12-31'                — актуальная версия BDM
  &P_UZ_SRC = 'MSSA'
  &P_KN_SRC = 'MSCL'
  &P_KK_SRC = 'CCPP_CRCA', 'CCPP_BATR'
  &p_quest_25lvl_product_kn_list = 'Потребкредит'
  &p_quest_25lvl_product_kk_list = 'Кредитные карты'

Полные имена входов без кавычек — из ОДНОГО запуска прототипа:
  &p_kn_tas_table     = sbx_pre_orb_fd.man_prt_tif_kn_kk_tas
  &p_kn_fin_table     = sbx_pre_orb_fd.man_prt_tif_kn_kk_fin
  &p_kn_numbers_table = sbx_pre_orb_fd.man_prt_tif_kn_kk_verification
  &p_kn_bdm_table     = sbx_pre_orb_fd.man_prt_tif_kn_kk_bdm
  &p_kn_matches_table = sbx_pre_orb_fd.man_prt_tif_kn_kk_matches
  &p_tqs_all_table    = sbx_pre_orb_fd.man_prt_tif_tqs_questionnaire_all
При других именах подставить фактические. В репозитории префикс prt_if2_,
например sbx_pre_orb_fd.prt_if2_kn_kk_tas. Самостоятельной таблицы параметров нет.

Сначала выполнить раздел 1: проверить 37 045 406 / 162 952 / 36 882 454
и состав остатка. Разделы 2–3 объяснят обрыв цепочки TAS -> BDM -> анкета.
Раздел 4 дополнительный: ищет отсутствующие номера в RAW до очистки.
Чтение BDM/RAW и группировки больших таблиц требуют ресурсов; банковский план
здесь не проверен. Несколько COUNT DISTINCT в одном запросе не используются.
Диагностика сравнивает точные номера и все маршруты исходного прототипа.
Нормализация номеров и дополнительные фильтры TAS не применяются.
*/

-- ==================== 1. ИМЕННО НЕСВЯЗАННЫЕ ПАРЫ TAS ====================

-- Шаг 1.1. Те же уже отобранные заявки, что дали 37 млн; никаких новых фильтров даты/продукта.
drop table if exists &db_sbx.prt_ifr_tas;
create table &db_sbx.prt_ifr_tas
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
select distinct parent_application_rk, application_rk,
       parent_src_cd, src_cd, parent_application_id, application_id,
       parent_application_dt, application_dt, level25_product_bp_nm
from &p_kn_tas_table
where parent_application_rk is not null or application_rk is not null
) distributed by (parent_application_rk, application_rk);

-- Шаг 1.2. Одна пара итога и признак хотя бы одной анкеты; повторные строки не увеличивают счетчик.
drop table if exists &db_sbx.prt_ifr_fin_keys;
create table &db_sbx.prt_ifr_fin_keys
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
select parent_application_rk, application_rk, 1 as present_flg,
       max(case when questionnaire_rk is not null then 1 else 0 end) as linked_flg
from &p_kn_fin_table
where parent_application_rk is not null or application_rk is not null
group by parent_application_rk, application_rk
) distributed by (parent_application_rk, application_rk);

-- Шаг 1.3. Исходные пары TAS и их реальное состояние в итоговой ветке КН/КК.
drop table if exists &db_sbx.prt_ifr_base;
create table &db_sbx.prt_ifr_base
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
select t.parent_application_rk, t.application_rk,
          max(coalesce(f.present_flg, 0)) as present_in_final_flg,
          max(coalesce(f.linked_flg, 0)) as linked_flg
   from &db_sbx.prt_ifr_tas t
   left join &db_sbx.prt_ifr_fin_keys f on coalesce(t.parent_application_rk, 0) = coalesce(f.parent_application_rk, 0)
and (t.parent_application_rk is null) = (f.parent_application_rk is null)
and coalesce(t.application_rk, 0) = coalesce(f.application_rk, 0)
and (t.application_rk is null) = (f.application_rk is null)
   group by t.parent_application_rk, t.application_rk
) distributed by (parent_application_rk, application_rk);

-- Отчет A. Ожидаемые числа: 37 045 406 / 162 952 / 36 882 454. missing_from_final должно быть 0.
select count(*) as tas_pair_count,
       coalesce(sum(linked_flg), 0) as linked_pair_count,
       coalesce(sum(1 - linked_flg), 0) as unlinked_pair_count,
       coalesce(sum(1 - present_in_final_flg), 0) as missing_from_final_count
from &db_sbx.prt_ifr_base;

-- Шаг 1.4. Только остаток без анкеты; пара сохраняет все различные атрибутные варианты TAS.
drop table if exists &db_sbx.prt_ifr_unlinked;
create table &db_sbx.prt_ifr_unlinked
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
select t.parent_application_rk, t.application_rk, t.parent_src_cd, t.src_cd,
          t.parent_application_id, t.application_id, t.parent_application_dt,
          t.application_dt, t.level25_product_bp_nm
   from &db_sbx.prt_ifr_tas t
   inner join &db_sbx.prt_ifr_base b on coalesce(t.parent_application_rk, 0) = coalesce(b.parent_application_rk, 0)
and (t.parent_application_rk is null) = (b.parent_application_rk is null)
and coalesce(t.application_rk, 0) = coalesce(b.application_rk, 0)
and (t.application_rk is null) = (b.application_rk is null)
   where b.linked_flg = 0
) distributed by (parent_application_rk, application_rk);

-- Шаг 1.5. Уникальная пара внутри продукта/источников; исходный продукт берется из TAS.
drop table if exists &db_sbx.prt_ifr_composition;
create table &db_sbx.prt_ifr_composition
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
select parent_application_rk, application_rk, level25_product_bp_nm, src_cd, parent_src_cd,
       min(coalesce(application_dt, parent_application_dt)) as cohort_dt
from &db_sbx.prt_ifr_unlinked
group by parent_application_rk, application_rk, level25_product_bp_nm, src_cd, parent_src_cd
) distributed by (parent_application_rk, application_rk);

-- Отчет B. Состав 36,9 млн: продукт, источник, УЗ без дочки. При конфликте меток одна пара видна в нескольких группах.
select level25_product_bp_nm, src_cd, parent_src_cd,
       case when application_rk is null then 'parent_only'
            when parent_application_rk is null then 'application_only'
            else 'parent_and_application' end as application_kind,
       count(*) as unlinked_pair_count
from &db_sbx.prt_ifr_composition
group by level25_product_bp_nm, src_cd, parent_src_cd,
         case when application_rk is null then 'parent_only'
              when parent_application_rk is null then 'application_only'
              else 'parent_and_application' end
order by unlinked_pair_count desc;

-- Отчет C. Периоды несвязанных пар: старые, неизвестные и свежие даты.
select date_trunc('month', cohort_dt) as cohort_month, count(*) as pair_group_count
from &db_sbx.prt_ifr_composition
group by date_trunc('month', cohort_dt)
order by cohort_month;

-- ==================== 2. ОБРАТНАЯ ЦЕПОЧКА TAS -> BDM -> НОМЕР АНКЕТЫ ====================

-- Шаг 2.1. Допустимые исходным JOIN ключи прямой заявки и УЗ; продукт анкеты не выводится из имени продукта TAS.
drop table if exists &db_sbx.prt_ifr_roots;
create table &db_sbx.prt_ifr_roots
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
select distinct parent_application_rk, application_rk, expected_product, bdm_rk, bdm_src, route
from (
select t.parent_application_rk, t.application_rk,
       cast(&p_quest_25lvl_product_kn_list as text) as expected_product, t.application_rk as bdm_rk, t.src_cd as bdm_src,
       case when t.src_cd = &P_UZ_SRC then 'UZ_SELF' else 'DIRECT' end as route
from &db_sbx.prt_ifr_unlinked t
where t.application_rk is not null and (t.src_cd = &P_KN_SRC or t.src_cd = &P_UZ_SRC)
union all
select t.parent_application_rk, t.application_rk,
       cast(&p_quest_25lvl_product_kn_list as text) as expected_product, t.parent_application_rk as bdm_rk,
       cast(&P_UZ_SRC as text) as bdm_src, cast('UZ_PARENT' as text) as route
from &db_sbx.prt_ifr_unlinked t
where t.parent_application_rk is not null and t.parent_src_cd = &P_UZ_SRC
  and (t.src_cd = &P_KN_SRC or t.src_cd is null)
union all
select t.parent_application_rk, t.application_rk,
       cast(&p_quest_25lvl_product_kk_list as text) as expected_product, t.application_rk as bdm_rk, t.src_cd as bdm_src,
       case when t.src_cd = &P_UZ_SRC then 'UZ_SELF' else 'DIRECT' end as route
from &db_sbx.prt_ifr_unlinked t
where t.application_rk is not null and (t.src_cd in (&P_KK_SRC) or t.src_cd = &P_UZ_SRC)
union all
select t.parent_application_rk, t.application_rk,
       cast(&p_quest_25lvl_product_kk_list as text) as expected_product, t.parent_application_rk as bdm_rk,
       cast(&P_UZ_SRC as text) as bdm_src, cast('UZ_PARENT' as text) as route
from &db_sbx.prt_ifr_unlinked t
where t.parent_application_rk is not null and t.parent_src_cd = &P_UZ_SRC
  and (t.src_cd in (&P_KK_SRC) or t.src_cd is null)
) r
) distributed by (parent_application_rk, application_rk);

-- Шаг 2.2. Один ключ BDM независимо от числа дочерних заявок; историю BDM читаем один раз.
drop table if exists &db_sbx.prt_ifr_root_keys;
create table &db_sbx.prt_ifr_root_keys
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
select bdm_rk, bdm_src from &db_sbx.prt_ifr_roots group by bdm_rk, bdm_src
) distributed by (bdm_rk);

-- Шаг 2.3. Найти BDM по RK+источнику, затем отметить актуальность и дату; пока не исключать плохие строки.
drop table if exists &db_sbx.prt_ifr_bdm;
create table &db_sbx.prt_ifr_bdm
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
select distinct a.application_rk as bdm_rk, a.src_cd as bdm_src, a.application_num,
       case when a.effective_to_date = cast(&p_max_date as date) then 1 else 0 end as current_flg,
       case when a.effective_to_date = cast(&p_max_date as date)
             and a.application_begin_date >= cast(&P_BEGIN_DATE as date) then 1 else 0 end as eligible_flg
from &p_db_bdm.application a
inner join &db_sbx.prt_ifr_root_keys k on k.bdm_rk = a.application_rk and k.bdm_src = a.src_cd
) distributed by (bdm_rk);

-- Шаг 2.4. Номера до и после получения RK; отдельные признаки периода и пригодного RK.
drop table if exists &db_sbx.prt_ifr_numbers;
create table &db_sbx.prt_ifr_numbers
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
with n as (
  select application_num, level25_product_bp_nm, 1 as post_flg, 0 as pre_flg,
         case when questionnaire_dttm >= cast(&P_BEGIN_DATE as timestamp)
                    or questionnaire_dttm is null then 1 else 0 end as post_period_flg,
         case when questionnaire_rk is not null
               and (questionnaire_dttm >= cast(&P_BEGIN_DATE as timestamp)
                    or questionnaire_dttm is null) then 1 else 0 end as post_usable_flg
  from &p_kn_numbers_table where application_num is not null
  union all
  select application_num, level25_product_bp_nm, 0, 1, 0, 0
  from &p_tqs_all_table where application_num is not null
)
select application_num, level25_product_bp_nm,
       max(post_flg) as post_flg, max(pre_flg) as pre_flg,
       max(post_period_flg) as post_period_flg, max(post_usable_flg) as post_usable_flg
from n group by application_num, level25_product_bp_nm
) distributed by (application_num);

-- Шаг 2.5. Номер существует хотя бы у одного продукта; нужен для отличия отсутствия номера от несовпадения продукта.
drop table if exists &db_sbx.prt_ifr_numbers_any;
create table &db_sbx.prt_ifr_numbers_any
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
select application_num, max(post_flg) as post_flg, max(pre_flg) as pre_flg
from &db_sbx.prt_ifr_numbers group by application_num
) distributed by (application_num);

-- Шаг 2.6. Какие ключи действительно попали в сохраненный мост прототипа.
drop table if exists &db_sbx.prt_ifr_saved_bridge;
create table &db_sbx.prt_ifr_saved_bridge
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
select bdm_application_rk as bdm_rk, bdm_src_cd as bdm_src, level25_product_bp_nm, 1 as present_flg
from &p_kn_bdm_table
where bdm_application_rk is not null and questionnaire_rk is not null
group by bdm_application_rk, bdm_src_cd, level25_product_bp_nm
) distributed by (bdm_rk);

-- Шаг 2.7. Пары с анкетой на шаге matches: проверить, не потеряла ли связь финальная сборка.
drop table if exists &db_sbx.prt_ifr_saved_matches;
create table &db_sbx.prt_ifr_saved_matches
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
select tas_parent_application_rk as parent_application_rk,
       tas_application_rk as application_rk, 1 as matched_flg
from &p_kn_matches_table where q_questionnaire_rk is not null
group by tas_parent_application_rk, tas_application_rk
) distributed by (parent_application_rk, application_rk);

-- Шаг 2.8. Проверить каждый ключ BDM+продукт один раз, не повторяя историю BDM для каждой дочерней заявки.
drop table if exists &db_sbx.prt_ifr_key_evidence;
create table &db_sbx.prt_ifr_key_evidence
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
with k as (
    select bdm_rk, bdm_src, expected_product from &db_sbx.prt_ifr_roots
    group by bdm_rk, bdm_src, expected_product
)
select k.bdm_rk, k.bdm_src, k.expected_product,
       max(case when a.bdm_rk is not null then 1 else 0 end) as any_bdm_flg,
       max(coalesce(a.current_flg, 0)) as current_bdm_flg,
       max(coalesce(a.eligible_flg, 0)) as eligible_bdm_flg,
       max(case when a.eligible_flg = 1 and a.application_num is not null then 1 else 0 end) as bdm_number_flg,
       max(case when a.eligible_flg = 1 then coalesce(n.post_flg, 0) else 0 end) as post_any_flg,
       max(case when a.eligible_flg = 1 then coalesce(n.pre_flg, 0) else 0 end) as pre_any_flg,
       max(case when a.eligible_flg = 1 then coalesce(p.pre_flg, 0) else 0 end) as pre_expected_flg,
       max(case when a.eligible_flg = 1 then coalesce(p.post_flg, 0) else 0 end) as post_expected_flg,
       max(case when a.eligible_flg = 1 then coalesce(p.post_period_flg, 0) else 0 end) as post_period_flg,
       max(case when a.eligible_flg = 1 then coalesce(p.post_usable_flg, 0) else 0 end) as post_usable_flg,
       max(case when a.eligible_flg = 1 and p.post_usable_flg = 1 then coalesce(s.present_flg, 0) else 0 end) as saved_bridge_flg
from k
left join &db_sbx.prt_ifr_bdm a on a.bdm_rk = k.bdm_rk and a.bdm_src = k.bdm_src
left join &db_sbx.prt_ifr_numbers_any n on n.application_num = a.application_num
left join &db_sbx.prt_ifr_numbers p on p.application_num = a.application_num and p.level25_product_bp_nm = k.expected_product
left join &db_sbx.prt_ifr_saved_bridge s on s.bdm_rk = k.bdm_rk and s.bdm_src = k.bdm_src
                                        and s.level25_product_bp_nm = k.expected_product
group by k.bdm_rk, k.bdm_src, k.expected_product
) distributed by (bdm_rk);

-- Шаг 2.9. На каждую НЕСВЯЗАННУЮ пару собрать признаки маршрутов из готовых счетчиков. Успех одного достаточен.
drop table if exists &db_sbx.prt_ifr_evidence;
create table &db_sbx.prt_ifr_evidence
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
select b.parent_application_rk, b.application_rk, b.present_in_final_flg,
          max(coalesce(m.matched_flg, 0)) as saved_match_flg,
          max(case when r.bdm_rk is not null then 1 else 0 end) as route_flg,
          max(coalesce(e.any_bdm_flg, 0)) as any_bdm_flg,
          max(coalesce(e.current_bdm_flg, 0)) as current_bdm_flg,
          max(coalesce(e.eligible_bdm_flg, 0)) as eligible_bdm_flg,
          max(coalesce(e.bdm_number_flg, 0)) as bdm_number_flg,
          max(coalesce(e.post_any_flg, 0)) as post_any_flg,
          max(coalesce(e.pre_any_flg, 0)) as pre_any_flg,
          max(coalesce(e.pre_expected_flg, 0)) as pre_expected_flg,
          max(coalesce(e.post_expected_flg, 0)) as post_expected_flg,
          max(coalesce(e.post_period_flg, 0)) as post_period_flg,
          max(coalesce(e.post_usable_flg, 0)) as post_usable_flg,
          max(coalesce(e.saved_bridge_flg, 0)) as saved_bridge_flg
   from &db_sbx.prt_ifr_base b
   left join &db_sbx.prt_ifr_roots r on coalesce(b.parent_application_rk, 0) = coalesce(r.parent_application_rk, 0)
and (b.parent_application_rk is null) = (r.parent_application_rk is null)
and coalesce(b.application_rk, 0) = coalesce(r.application_rk, 0)
and (b.application_rk is null) = (r.application_rk is null)
   left join &db_sbx.prt_ifr_key_evidence e on e.bdm_rk = r.bdm_rk and e.bdm_src = r.bdm_src
                                             and e.expected_product = r.expected_product
   left join &db_sbx.prt_ifr_saved_matches m on coalesce(b.parent_application_rk, 0) = coalesce(m.parent_application_rk, 0)
and (b.parent_application_rk is null) = (m.parent_application_rk is null)
and coalesce(b.application_rk, 0) = coalesce(m.application_rk, 0)
and (b.application_rk is null) = (m.application_rk is null)
   where b.linked_flg = 0
   group by b.parent_application_rk, b.application_rk, b.present_in_final_flg
) distributed by (parent_application_rk, application_rk);

-- ==================== 3. ПРИЧИНЫ НА УРОВНЕ ПАРЫ TAS ====================

-- Шаг 3.1. Одна пара — одна причина по первому неподдержанному этапу. Сумма должна дать 36 882 454.
drop table if exists &db_sbx.prt_ifr_reasons;
create table &db_sbx.prt_ifr_reasons
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
select parent_application_rk, application_rk,
       case when present_in_final_flg = 0 then '00_tas_pair_missing_from_final'
            when saved_match_flg = 1 then '01_saved_match_missing_from_final'
            when route_flg = 0 then '02_no_supported_join_route'
            when any_bdm_flg = 0 then '03_no_bdm_for_rk_and_source'
            when current_bdm_flg = 0 then '04_bdm_has_no_current_version'
            when eligible_bdm_flg = 0 then '05_bdm_date_old_or_null'
            when bdm_number_flg = 0 then '06_bdm_application_num_null'
            when post_any_flg = 0 and pre_expected_flg = 1 then '07_number_present_before_rk_only'
            when post_any_flg = 0 and pre_any_flg = 1 then '08_number_before_rk_other_product'
            when post_any_flg = 0 then '09_number_absent_from_prepared_questionnaires'
            when post_expected_flg = 0 then '10_questionnaire_product_mismatch'
            when post_period_flg = 0 then '11_questionnaire_outside_period'
            when post_usable_flg = 0 then '12_questionnaire_rk_null'
            when saved_bridge_flg = 0 then '13_candidate_missing_from_saved_bridge'
            else '14_candidate_exists_check_join_mode_or_run' end as reason
from &db_sbx.prt_ifr_evidence
) distributed by (parent_application_rk, application_rk);

-- Отчет D. Главный результат: сколько именно НЕСВЯЗАННЫХ заявочных пар относится к каждой причине.
select reason, count(*) as unlinked_pair_count
from &db_sbx.prt_ifr_reasons group by reason order by unlinked_pair_count desc;

-- Отчет E. До 50 примеров с исходными ID TAS для ручной проверки.
select r.reason, t.parent_application_rk, t.application_rk,
          t.parent_application_id, t.application_id, t.src_cd, t.parent_src_cd,
          t.level25_product_bp_nm, t.application_dt, t.parent_application_dt
   from &db_sbx.prt_ifr_reasons r
   inner join &db_sbx.prt_ifr_unlinked t on coalesce(r.parent_application_rk, 0) = coalesce(t.parent_application_rk, 0)
and (r.parent_application_rk is null) = (t.parent_application_rk is null)
and coalesce(r.application_rk, 0) = coalesce(t.application_rk, 0)
and (r.application_rk is null) = (t.application_rk is null)
   order by r.reason
   limit 50;

-- ==================== 4. ДОПОЛНИТЕЛЬНО: НОМЕРА В RAW ДО ОЧИСТКИ ====================
-- Запускать после 1–3. RAW может быть большим; даты RAW не приводятся к timestamp.

-- Шаг 4.1. Только допустимые номера BDM, которых нет после подготовки анкет с RK.
drop table if exists &db_sbx.prt_ifr_missing_numbers;
create table &db_sbx.prt_ifr_missing_numbers
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
select a.application_num
from &db_sbx.prt_ifr_bdm a
left join &db_sbx.prt_ifr_numbers_any n on n.application_num = a.application_num
where a.eligible_flg = 1 and a.application_num is not null and coalesce(n.post_flg, 0) = 0
group by a.application_num
) distributed by (application_num);

-- Шаг 4.2. Есть ли номер в RAW вообще; отсутствие не интерпретируется как доказанный другой канал.
drop table if exists &db_sbx.prt_ifr_raw_numbers;
create table &db_sbx.prt_ifr_raw_numbers
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
select n.application_num,
       max(case when r.application_num is not null then 1 else 0 end) as raw_found_flg,
       min(r.questionnaire_id) as example_questionnaire_id,
       min(coalesce(r.questionnaire_dt, r.business_dt, r.createtime_dttm)) as min_raw_date_text
from &db_sbx.prt_ifr_missing_numbers n
left join &p_db_rawd.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention r
  on r.application_num = n.application_num
group by n.application_num
) distributed by (application_num);

-- Шаг 4.3. Вернуться от номеров к парам: не умножать число заявок на число номеров/строк RAW.
drop table if exists &db_sbx.prt_ifr_raw_pairs;
create table &db_sbx.prt_ifr_raw_pairs
with (APPENDONLY = true, ORIENTATION = column, COMPRESSTYPE = zstd, COMPRESSLEVEL = 5)
as (
select r.parent_application_rk, r.application_rk, max(n.raw_found_flg) as raw_found_flg
from &db_sbx.prt_ifr_roots r
inner join &db_sbx.prt_ifr_bdm a on a.bdm_rk = r.bdm_rk and a.bdm_src = r.bdm_src and a.eligible_flg = 1
inner join &db_sbx.prt_ifr_raw_numbers n on n.application_num = a.application_num
group by r.parent_application_rk, r.application_rk
) distributed by (parent_application_rk, application_rk);

-- Отчет F. Разделить отсутствие номера в подготовленных анкетах: найден ли он хотя бы в сыром источнике.
select r.reason, p.raw_found_flg, count(*) as unlinked_pair_count
   from &db_sbx.prt_ifr_reasons r
   left join &db_sbx.prt_ifr_raw_pairs p on coalesce(r.parent_application_rk, 0) = coalesce(p.parent_application_rk, 0)
and (r.parent_application_rk is null) = (p.parent_application_rk is null)
and coalesce(r.application_rk, 0) = coalesce(p.application_rk, 0)
and (r.application_rk is null) = (p.application_rk is null)
   where r.reason in ('07_number_present_before_rk_only', '08_number_before_rk_other_product',
                      '09_number_absent_from_prepared_questionnaires')
   group by r.reason, p.raw_found_flg
   order by r.reason, p.raw_found_flg;

-- Отчет G. До 50 номеров BDM для проверки владельцами источника; даты RAW здесь текстовые.
select application_num, raw_found_flg, example_questionnaire_id, min_raw_date_text
from &db_sbx.prt_ifr_raw_numbers order by raw_found_flg, application_num limit 50;

/*
Интерпретация — docs/unlinked_kn_kk_diagnostics.txt.
Файл показывает подтвержденное место обрыва данных, но не угадывает бизнес-причину:
нет номера в RAW не доказывает другой канал или отсутствие анкеты в других системах.
Одинаковые ключи/номера и источники должны сравниваться в одном снимке/запуске.
Оба маршрута проверяются как кандидаты. При DIRECT/UZ вместо ALL в прототипе
часть причин 14 объясняется выключенным маршрутом; это не автоматическое доказательство ошибки.
Равенства nullable RK учитывают признак NULL, поэтому настоящий RK=0 не сливается с NULL.
*/
