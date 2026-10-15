/*
ЭТАП 1. ОБЩИЙ ФЛАГ ВЕРИФИКАЦИИ АНКЕТЫ. НЕ ЗАВИСИТ ОТ TAS И BDM.
Сначала выполнить ../status_by_product.sql.

Предположения для проверки:
  1. tech_questionnaire_status хранит историю статусов с интервалами [from, to).
  2. Ключ анкеты: (questionnaire_rk, src_cd).
  3. Рабочая семантика: хотя бы раз достигнут выбранный статус до report_dttm.
     Это НЕ равнозначно успешному завершению проверки.
  4. Жёлтые строки status_by_product — только кандидаты для правила.

Уточнения меняют справочник/политику, а не логику будущих веток.
По умолчанию status_rule_confirmed = false: итоговый verification_flg = NULL,
а отдельно вычисляется кандидат verification_candidate_flg для исследования.
При неподтверждённой полноте истории отсутствие статуса НЕ превращается в false.

Выход: prt_qs_verification_flags, одна строка на (questionnaire_rk, src_cd).
Флаг рассчитан НА report_dttm для будущего ТЕКУЩЕГО среза витрины.
Для исторической витрины потребуются отдельные расчёты на момент каждой версии.
*/

-- 1.1. Отчётный момент. При повторении одного отчёта указать тот же timestamp.
drop table if exists sbx_pre_orb_fd.prt_qs_verification_params;
create table sbx_pre_orb_fd.prt_qs_verification_params
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select cast(current_timestamp as timestamp) as report_dttm
distributed randomly;

-- 1.2. Политика по продуктам. Пока все три правила НЕ подтверждены.
-- verification_mode: EVER_REACHED или CURRENT_STATUS.
-- Успешную верификацию можно рассчитывать только по отдельному согласованному
-- набору успешных статусов: VERIFICATION не означает автоматически «пройдена».
-- status_rule_confirmed = true ставить только после проверки ПОЛНОГО набора
-- положительных статусов и согласования семантики именно для этого продукта.
-- history_complete_confirmed = true разрешает false при отсутствии статуса
-- в ПОЛНОЙ истории анкеты; усечённая история такого основания не даёт.
drop table if exists sbx_pre_orb_fd.prt_qs_verification_policy;
create table sbx_pre_orb_fd.prt_qs_verification_policy
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    cast(p.product_branch as text) as product_branch,
    cast(p.level25_product_bp_nm as text) as level25_product_bp_nm,
    cast(p.src_pattern as text) as src_pattern,
    cast('EVER_REACHED' as text) as verification_mode,
    false as status_rule_confirmed,
    false as history_complete_confirmed
from (
    values
        ('KN',   'Потребкредит',    '1376%'),
        ('KK',   'Кредитные карты', '1383%'),
        ('AUTO', 'Автокредит',      '1388%')
) p(product_branch, level25_product_bp_nm, src_pattern)
distributed randomly;

-- 1.3. История статусов. ВАЖНО: не отсекаем прошлые статусы условием
-- effective_to_dttm = '2999-12-31', иначе потеряем ранее пройденные этапы.
-- Нет ограничения по дате создания версии: нужная анкета могла проходить
-- проверку до начала периода отчёта. Когорту ограничим позже, в ветках.
-- Имена TQS/полей взяты из показанного DDL; при отличии изменить этот адаптер.
-- Неизвестный продукт выбранного источника сохраняется для диагностики.
drop table if exists sbx_pre_orb_fd.prt_qs_verification_history;
create table sbx_pre_orb_fd.prt_qs_verification_history
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    q.questionnaire_rk,
    q.questionnaire_id,
    q.src_cd,
    q.level25_product_bp_nm,
    q.status_cd,
    q.effective_from_dttm,
    q.effective_to_dttm,
    p.product_branch,
    p.verification_mode,
    p.status_rule_confirmed,
    p.history_complete_confirmed,
    case when s.status_cd is not null then 1 else 0 end as candidate_status_hit,
    case
        when q.effective_from_dttm <= r.report_dttm
         and q.effective_to_dttm > r.report_dttm
        then 1 else 0
    end as active_at_report_flg
from sbx_pre_orb_fd.tech_questionnaire_status q
cross join sbx_pre_orb_fd.prt_qs_verification_params r
left join sbx_pre_orb_fd.prt_qs_verification_policy p
    on q.src_cd like p.src_pattern
   and q.level25_product_bp_nm = p.level25_product_bp_nm
left join sbx_pre_orb_fd.prt_qs_status_by_product s
    on s.product_branch = p.product_branch
   and s.level25_product_bp_nm = p.level25_product_bp_nm
   and s.status_cd = q.status_cd
where (q.src_cd like '1376%' or q.src_cd like '1383%' or q.src_cd like '1388%')
  and (q.effective_from_dttm <= r.report_dttm or q.effective_from_dttm is null)
distributed randomly;

-- 1.4. Сводим историю к ключу анкеты. MAX — по признаку наличия статуса,
-- а не выбор одной произвольной строки статуса или последней загрузки.
-- Не группируем по статусу, чтобы флаг не размножил будущие связи.
drop table if exists sbx_pre_orb_fd.prt_qs_verification_facts;
create table sbx_pre_orb_fd.prt_qs_verification_facts
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    q.questionnaire_rk,
    q.src_cd,
    case
        when count(distinct q.product_branch) = 1
         and sum(case when q.product_branch is null then 1 else 0 end) = 0
        then max(q.product_branch)
        else 'UNMAPPED_OR_CONFLICT'
    end as product_branch,
    max(q.verification_mode) as verification_mode,
    min(case when q.status_rule_confirmed then 1 else 0 end) as rule_confirmed_flg,
    min(case when q.history_complete_confirmed then 1 else 0 end) as history_complete_flg,
    count(distinct q.questionnaire_id) as questionnaire_id_count,
    count(*) as history_row_count,
    sum(q.active_at_report_flg) as active_row_count,
    sum(case when nullif(btrim(q.status_cd), '') is null then 1 else 0 end) as empty_status_count,
    sum(case when q.active_at_report_flg = 1
              and nullif(btrim(q.status_cd), '') is null then 1 else 0 end) as active_empty_status_count,
    sum(case when q.effective_from_dttm is null
               or q.effective_to_dttm is null
               or q.effective_to_dttm <= q.effective_from_dttm
             then 1 else 0 end) as invalid_interval_count,
    max(q.candidate_status_hit) as ever_candidate_flg,
    max(case when q.active_at_report_flg = 1 then q.candidate_status_hit else 0 end) as current_candidate_flg
from sbx_pre_orb_fd.prt_qs_verification_history q
where q.questionnaire_rk is not null and q.questionnaire_rk <> -1
group by q.questionnaire_rk, q.src_cd
distributed randomly;

-- 1.5. Причина решения. NULL отличается от подтверждённого false.
drop table if exists sbx_pre_orb_fd.prt_qs_verification_decisions;
create table sbx_pre_orb_fd.prt_qs_verification_decisions
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    f.questionnaire_rk, f.src_cd, f.product_branch, f.verification_mode,
    case
        when f.verification_mode = 'EVER_REACHED' then f.ever_candidate_flg
        when f.verification_mode = 'CURRENT_STATUS' then f.current_candidate_flg
        else null
    end as verification_candidate_flg,
    f.history_row_count, f.active_row_count,
    case
        when f.product_branch = 'UNMAPPED_OR_CONFLICT' then 'PRODUCT_OR_SOURCE_NOT_MAPPED'
        when f.questionnaire_id_count > 1 then 'MULTIPLE_TEXT_IDS_ON_ONE_KEY'
        when f.invalid_interval_count > 0 then 'INVALID_STATUS_INTERVAL'
        when f.verification_mode not in ('EVER_REACHED', 'CURRENT_STATUS')
             or f.verification_mode is null then 'UNSUPPORTED_SEMANTICS'
        when f.verification_mode = 'CURRENT_STATUS' and f.active_row_count <> 1
             then 'CURRENT_STATUS_NOT_UNIQUE_OR_MISSING'
        when f.rule_confirmed_flg <> 1 then 'STATUS_RULE_NOT_CONFIRMED'
        when f.verification_mode = 'EVER_REACHED' and f.ever_candidate_flg = 1
             then 'MATCHING_STATUS_IN_HISTORY'
        when f.verification_mode = 'CURRENT_STATUS' and f.current_candidate_flg = 1
             then 'MATCHING_CURRENT_STATUS'
        when f.verification_mode = 'EVER_REACHED' and f.empty_status_count > 0
             then 'MISSING_STATUS_IN_HISTORY'
        when f.verification_mode = 'CURRENT_STATUS' and f.active_empty_status_count > 0
             then 'MISSING_CURRENT_STATUS'
        when f.verification_mode = 'EVER_REACHED' and f.history_complete_flg <> 1
             then 'HISTORY_COMPLETENESS_NOT_CONFIRMED'
        when f.verification_mode = 'EVER_REACHED' then 'NO_MATCH_IN_COMPLETE_HISTORY'
        when f.verification_mode = 'CURRENT_STATUS' then 'CURRENT_STATUS_NOT_MATCHING'
        else 'UNRESOLVED'
    end as verification_reason
from sbx_pre_orb_fd.prt_qs_verification_facts f
distributed randomly;

-- 1.6. Общий результат для будущих КН/КК и авто.
-- JOIN только по (questionnaire_rk, src_cd), без application_num/application_id.
drop table if exists sbx_pre_orb_fd.prt_qs_verification_flags;
create table sbx_pre_orb_fd.prt_qs_verification_flags
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    d.questionnaire_rk, d.src_cd, d.product_branch,
    cast(case
        when d.verification_reason in ('MATCHING_STATUS_IN_HISTORY', 'MATCHING_CURRENT_STATUS') then true
        when d.verification_reason in ('NO_MATCH_IN_COMPLETE_HISTORY', 'CURRENT_STATUS_NOT_MATCHING') then false
        else null
    end as boolean) as verification_flg,
    d.verification_candidate_flg,
    d.verification_reason,
    d.verification_mode,
    d.history_row_count,
    d.active_row_count,
    r.report_dttm
from sbx_pre_orb_fd.prt_qs_verification_decisions d
cross join sbx_pre_orb_fd.prt_qs_verification_params r
distributed randomly;

-- 1.7. Контроли. На первом запуске verification_flg ожидаемо NULL,
-- потому что правила ещё не подтверждены. Кандидат выводится отдельно.
select product_branch, verification_candidate_flg, verification_flg,
       verification_reason, count(*) as questionnaire_count
from sbx_pre_orb_fd.prt_qs_verification_flags
group by product_branch, verification_candidate_flg, verification_flg, verification_reason
order by product_branch, verification_reason, verification_candidate_flg;

-- Ожидается 0 строк: присоединение флага не должно размножать анкеты.
select questionnaire_rk, src_cd, count(*) as row_count
from sbx_pre_orb_fd.prt_qs_verification_flags
group by questionnaire_rk, src_cd having count(*) > 1;

-- Неклассифицированные продукты выбранных источников — дополнить политику
-- после проверки, а не отбрасывать такие анкеты из будущего результата.
select src_cd, level25_product_bp_nm, count(*) as history_row_count
from sbx_pre_orb_fd.prt_qs_verification_history
where product_branch is null
group by src_cd, level25_product_bp_nm
order by src_cd, level25_product_bp_nm;

-- Непригодные ключи не объединены в одну искусственную «анкету».
select src_cd, count(*) as invalid_key_history_rows
from sbx_pre_orb_fd.prt_qs_verification_history
where questionnaire_rk is null or questionnaire_rk = -1
group by src_cd order by src_cd;
