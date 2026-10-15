/*
ЕДИНЫЙ СКРИПТ. Greenplum. Выполнять последовательно с остановкой на ошибке.
Порядок: 1 — верификация анкеты; 2 — КН/КК; 3 — авто; 4 — итог и контроли.
Итог: sbx_pre_orb_fd.prt_tech_questionnaire_application_status.

ПОДТВЕРЖДЁННОЕ ПРАВИЛО: любой выделенный зелёным/жёлтым статус означает,
что верификация была пройдена. Флаг — наличие такого статуса КОГДА-ЛИБО
в доступной истории до report_dttm. Цвет не участвует в расчёте.
Все 20 статусов, видимых выделенными на присланных скриншотах, в шаге 1.1.
Если в остальных частях status_by_product есть ещё выделения, дописать их там.

ИСТОЧНИКИ ДЛЯ ПРОВЕРКИ ИМЁН:
  sbx_pre_orb_fd.tech_questionnaire_status — история/текущий срез TQS;
  sbx_pre_orb_fd.man_prt_tqs_questionnaire — выборка из источника TQS,
      в которой есть application_num (в показанном DDL TQS его нет);
  bdm.application — номер заявки -> application_rk;
  sbx_pre_orb_fd.tech_application_status — TAS.

ПРЕДПОЛОЖЕНИЯ, ОСТАВЛЕННЫЕ ДЛЯ ПРОВЕРКИ:
  TQS текущая: effective_to_dttm в дне 2999-12-31, начало версии не в будущем.
  TAS: актуальный пересобираемый снимок — поля окончания версии в DDL нет.
  Если TAS версионная, ДО группировки добавить реальный фильтр в 2.3 и 3.1.
  processed_dttm не заменяет поле актуальности и не выбирает последнюю строку.
  По датам NULL сохраняются; их количество видно в контролях.
  Разные значения атрибута на одном текущем ключе дают NULL атрибута и счётчик
  конфликта. Произвольная строка не выбирается; исходные строки в *_raw.

КН/КК: по умолчанию ALL — объединение кандидатов прямого пути и путей УЗ,
с удалением повторов одной пары и сохранением списка путей/кардинальности.
Это исследовательский режим для выбора жизнеспособного способа. После
проверки отчёта 2.7 можно выбрать DIRECT или UZ в шаге 0.1 без переписывания.
Строка УЗ без дочки — самостоятельная сущность TAS, а не дочерняя заявка.

Технические q_entity_id/tas_entity_id действуют в рамках одной пересборки;
для внешних связей использовать бизнес-RK вместе с источником.
DROP удаляет только результаты этого скрипта с префиксами prt_qas_ и итог.
Источники не изменяются. На боевых объёмах сначала посмотреть планы загрузок.
*/

-- 0.1. Параметры: период из прототипа и режим исследования КН/КК.
drop table if exists sbx_pre_orb_fd.prt_qas_params;
create table sbx_pre_orb_fd.prt_qas_params
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    date '2025-01-01' as begin_date,
    date '2999-12-31' as max_date,
    cast(current_timestamp as timestamp) as report_dttm,
    cast(10.0 as numeric) as min_coverage_pct,
    cast('ALL' as text) as kn_kk_link_mode,
    true as bdm_limit_by_begin_date
distributed randomly;

-- ==================== 1. ВЕРИФИКАЦИЯ АНКЕТЫ ====================
-- Источники/продукты проверяются вместе: одинаковый код статуса в другом
-- продукте не должен автоматически подтверждать верификацию.

-- 1.1. Подтверждённые статусы пройденной верификации из обеих заливок.
drop table if exists sbx_pre_orb_fd.prt_qas_verification_status;
create table sbx_pre_orb_fd.prt_qas_verification_status
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    cast(v.product_branch as text) as product_branch,
    cast(v.level25_product_bp_nm as text) as level25_product_bp_nm,
    cast(v.src_pattern as text) as src_pattern,
    cast(v.status_cd as text) as status_cd
from (values
        ('KN', 'Потребкредит', '1376%', '0'),
        ('KN', 'Потребкредит', '1376%', '10.0'),
        ('KN', 'Потребкредит', '1376%', 'одобрено'),
        ('KN', 'Потребкредит', '1376%', 'CHECK_LIST_EMPTY'),
        ('KN', 'Потребкредит', '1376%', 'CHECK_LIST_ANTIFRAUD_OR_PRODUCT'),
        ('KK', 'Кредитные карты', '1383%', 'DONE'),
        ('KK', 'Кредитные карты', '1383%', 'COURIER'),
        ('AUTO', 'Автокредит', '1388%', 'APPROVE_RKK'),
        ('AUTO', 'Автокредит', '1388%', 'APPROVED'),
        ('AUTO', 'Автокредит', '1388%', 'PRE_APPROVED'),
        ('AUTO', 'Автокредит', '1388%', 'APPROVE_CALL2'),
        ('AUTO', 'Автокредит', '1388%', 'APPROVE_CALL3'),
        ('AUTO', 'Автокредит', '1388%', 'ORDER_CREATED'),
        ('AUTO', 'Автокредит', '1388%', 'VERIFICATION'),
        ('AUTO', 'Автокредит', '1388%', 'DRIVER_CARD_ISSUE'),
        ('AUTO', 'Автокредит', '1388%', 'DRIVER_CARD_ISSUE_UPLOADED'),
        ('AUTO', 'Автокредит', '1388%', 'DOSSIER_UPLOADED'),
        ('AUTO', 'Автокредит', '1388%', 'DEAL_VER'),
        ('AUTO', 'Автокредит', '1388%', 'CREDIT_ISSUED'),
        ('AUTO', 'Автокредит', '1388%', 'PRODUCT_BASKET_SIGNED')
) v(product_branch, level25_product_bp_nm, src_pattern, status_cd)
distributed randomly;

-- 1.2. История анкеты. Здесь НЕТ фильтра effective_to_dttm = 2999-12-31.
drop table if exists sbx_pre_orb_fd.prt_qas_verification_history;
create table sbx_pre_orb_fd.prt_qas_verification_history
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    q.questionnaire_rk, q.src_cd, q.status_cd, q.level25_product_bp_nm,
    q.effective_from_dttm, q.effective_to_dttm,
    case when v.status_cd is not null then 1 else 0 end as verified_status_hit
from sbx_pre_orb_fd.tech_questionnaire_status q
cross join sbx_pre_orb_fd.prt_qas_params p
left join sbx_pre_orb_fd.prt_qas_verification_status v
  on q.src_cd like v.src_pattern
 and q.level25_product_bp_nm = v.level25_product_bp_nm
 and q.status_cd = v.status_cd
where (q.src_cd like '1376%' or q.src_cd like '1383%' or q.src_cd like '1388%')
  and (q.effective_from_dttm <= p.report_dttm or q.effective_from_dttm is null)
distributed randomly;

-- 1.3. Один флаг на ключ анкеты: любой такой статус в доступной истории.
drop table if exists sbx_pre_orb_fd.prt_qas_verification_flags;
create table sbx_pre_orb_fd.prt_qas_verification_flags
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    h.questionnaire_rk, h.src_cd,
    cast(max(h.verified_status_hit) = 1 as boolean) as verification_flg,
    count(*) as history_row_count,
    sum(case when h.status_cd is null or btrim(h.status_cd) = '' then 1 else 0 end) as empty_status_rows
from sbx_pre_orb_fd.prt_qas_verification_history h
where h.questionnaire_rk is not null and h.questionnaire_rk <> -1
group by h.questionnaire_rk, h.src_cd
distributed randomly;

-- 1.4. Текущая когорта анкет. Строки с NULL ключа/даты не теряем.
drop table if exists sbx_pre_orb_fd.prt_qas_questionnaire_current_raw;
create table sbx_pre_orb_fd.prt_qas_questionnaire_current_raw
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    row_number() over (order by q.src_cd, q.questionnaire_rk nulls first, q.questionnaire_id) as q_row_id,
    nullif(q.questionnaire_rk, -1) as questionnaire_rk,
    q.questionnaire_id, q.questionnaire_dttm, q.status_cd, q.status_name, q.product_type_cd, q.program_type, q.level25_product_bp_nm,
    q.src_cd as q_src_cd,
    case when q.src_cd like '1376%' then 'KN'
         when q.src_cd like '1383%' then 'KK'
         when q.src_cd like '1388%' then 'AUTO' end as product_branch,
    case when (q.src_cd like '1376%' and q.level25_product_bp_nm = 'Потребкредит')
           or (q.src_cd like '1383%' and q.level25_product_bp_nm = 'Кредитные карты')
           or (q.src_cd like '1388%' and q.level25_product_bp_nm = 'Автокредит')
         then 1 else 0 end as product_match_flg
from sbx_pre_orb_fd.tech_questionnaire_status q
cross join sbx_pre_orb_fd.prt_qas_params p
where (q.src_cd like '1376%' or q.src_cd like '1383%' or q.src_cd like '1388%')
  and q.effective_to_dttm >= cast(p.max_date as timestamp)
  and q.effective_to_dttm < timestamp '3000-01-01 00:00:00'
  and (q.effective_from_dttm <= p.report_dttm or q.effective_from_dttm is null)
  and (q.questionnaire_dttm >= cast(p.begin_date as timestamp) or q.questionnaire_dttm is null)
distributed randomly;

-- 1.5. Ключи и атрибуты анкет + общий флаг. NULL ключи сохраняются раздельно.
drop table if exists sbx_pre_orb_fd.prt_qas_questionnaire;
create table sbx_pre_orb_fd.prt_qas_questionnaire
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    row_number() over (order by g.q_src_cd, g.questionnaire_rk nulls first,
                       g.invalid_row_group nulls first) as q_entity_id,
    g.questionnaire_rk, g.q_src_cd, g.questionnaire_id, g.questionnaire_dttm, g.status_cd, g.status_name, g.product_type_cd, g.program_type, g.level25_product_bp_nm,
    g.product_branch, g.product_match_flg, g.current_row_count, g.id_count, g.status_count,
    case when g.questionnaire_rk is null then cast(null as boolean)
         else coalesce(v.verification_flg, false) end as verification_flg
from (
    select
        r.questionnaire_rk, r.q_src_cd,
        case when r.questionnaire_rk is null then r.q_row_id else null end as invalid_row_group,
        case when count(distinct r.questionnaire_id) = 1 then min(r.questionnaire_id) else null end as questionnaire_id,
        case when count(distinct r.questionnaire_dttm) = 1 then min(r.questionnaire_dttm) else null end as questionnaire_dttm,
        case when count(distinct r.status_cd) = 1 then min(r.status_cd) else null end as status_cd,
        case when count(distinct r.status_name) = 1 then min(r.status_name) else null end as status_name,
        case when count(distinct r.product_type_cd) = 1 then min(r.product_type_cd) else null end as product_type_cd,
        case when count(distinct r.program_type) = 1 then min(r.program_type) else null end as program_type,
        case when count(distinct r.level25_product_bp_nm) = 1 then min(r.level25_product_bp_nm) else null end as level25_product_bp_nm,
        max(r.product_branch) as product_branch,
        min(r.product_match_flg) as product_match_flg,
        count(*) as current_row_count,
        count(distinct r.questionnaire_id) as id_count,
        count(distinct r.status_cd) as status_count
    from sbx_pre_orb_fd.prt_qas_questionnaire_current_raw r
    group by r.questionnaire_rk, r.q_src_cd,
             case when r.questionnaire_rk is null then r.q_row_id else null end
) g
left join sbx_pre_orb_fd.prt_qas_verification_flags v
  on v.questionnaire_rk = g.questionnaire_rk and v.src_cd = g.q_src_cd
distributed randomly;

-- Контроль 1: бизнес-флаг уже true/false; NULL — у непригодного RK.
-- false означает «не найдено в доступной истории», не доказательство её полноты.
select product_branch, verification_flg, count(*) as questionnaire_count
from sbx_pre_orb_fd.prt_qas_questionnaire
group by product_branch, verification_flg order by product_branch, verification_flg;

-- ==================== 2. ВЕТКА КН/КК ====================
-- application_num получаем из ИСТОЧНИКА анкет, а не из отсутствующей колонки TQS.
-- Пустые номера/ключи не соединяем. Строки без номера остаются в базе анкет.

-- 2.1. Мост из источника: questionnaire_id + src_cd -> application_num.
drop table if exists sbx_pre_orb_fd.prt_qas_kn_kk_questionnaire_num;
create table sbx_pre_orb_fd.prt_qas_kn_kk_questionnaire_num
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select distinct
    s.questionnaire_id, s.src_cd as q_src_cd, s.application_num
from sbx_pre_orb_fd.man_prt_tqs_questionnaire s
where (s.src_cd like '1376%' or s.src_cd like '1383%')
  and nullif(btrim(s.questionnaire_id), '') is not null
  and nullif(btrim(s.application_num), '') is not null
distributed randomly;

-- 2.2. Текущие BDM-заявки продуктовых систем и УЗ.
drop table if exists sbx_pre_orb_fd.prt_qas_kn_kk_bdm_application;
create table sbx_pre_orb_fd.prt_qas_kn_kk_bdm_application
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select distinct
    a.application_rk, a.application_num, a.src_cd
from bdm.application a
cross join sbx_pre_orb_fd.prt_qas_params p
where a.effective_to_date = p.max_date
  and (not p.bdm_limit_by_begin_date or a.application_begin_date >= p.begin_date)
  and a.src_cd in ('MSSA', 'MSCL', 'CCPP_CRCA', 'CCPP_BATR')
  and a.application_rk is not null and a.application_rk <> -1
  and nullif(btrim(a.application_num), '') is not null
distributed randomly;

-- 2.3. Загрузка TAS: предполагаемый актуальный снимок; -1 -> NULL перед связями.
drop table if exists sbx_pre_orb_fd.prt_qas_kn_kk_tas_raw;
create table sbx_pre_orb_fd.prt_qas_kn_kk_tas_raw
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    row_number() over (order by t.src_cd nulls first, t.application_rk nulls first,
                       t.parent_application_rk nulls first) as tas_row_id,
    nullif(t.parent_application_rk, -1) as parent_application_rk,
    t.parent_src_cd,
    nullif(t.application_rk, -1) as application_rk,
    t.src_cd,
    t.parent_application_id, t.parent_application_dt, t.parent_approved_dttm, t.application_id, t.application_dt, t.application_type_cd, t.deal_issue_date, t.level25_product_bp_nm, t.level35_product_bp_nm, cast(t.parent_open_flg as boolean) as parent_open_flg, cast(t.parent_prescoring_flg as boolean) as parent_prescoring_flg, cast(t.parent_at_work_flg as boolean) as parent_at_work_flg, cast(t.parent_approved_flg as boolean) as parent_approved_flg, cast(t.create_flg as boolean) as create_flg, cast(t.at_work_flg as boolean) as at_work_flg, cast(t.final_approved_flg as boolean) as final_approved_flg, cast(t.agr_signed_flg as boolean) as agr_signed_flg,
    t.processed_dttm,
    case when t.src_cd = 'ALPP' then 'AUTO'
         when t.src_cd = 'MSCL' then 'KN'
         when t.src_cd in ('CCPP_CRCA', 'CCPP_BATR') then 'KK'
         else 'UZ' end as product_branch
from sbx_pre_orb_fd.tech_application_status t
cross join sbx_pre_orb_fd.prt_qas_params p
where (t.src_cd in ('MSCL', 'CCPP_CRCA', 'CCPP_BATR', 'MSSA')
       or (t.src_cd is null and t.parent_src_cd = 'MSSA'
           and nullif(t.parent_application_rk, -1) is not null))
  and (coalesce(t.application_dt, t.parent_application_dt) >= p.begin_date
       or coalesce(t.application_dt, t.parent_application_dt) is null)
-- При версионной TAS добавить подтверждённый фильтр актуальности ЗДЕСЬ.
distributed randomly;

-- 2.4. Сущности TAS: ключ родителя + ребёнка; конфликты атрибутов не выбираем произвольно.
drop table if exists sbx_pre_orb_fd.prt_qas_kn_kk_tas;
create table sbx_pre_orb_fd.prt_qas_kn_kk_tas
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    row_number() over (order by g.src_cd nulls first, g.application_rk nulls first,
                       g.parent_src_cd nulls first, g.parent_application_rk nulls first,
                       g.invalid_row_group nulls first) as app_entity_id,
    g.parent_application_rk, g.parent_src_cd, g.application_rk, g.src_cd, g.parent_application_id, g.parent_application_dt, g.parent_approved_dttm, g.application_id, g.application_dt, g.application_type_cd, g.deal_issue_date, g.level25_product_bp_nm, g.level35_product_bp_nm, g.parent_open_flg, g.parent_prescoring_flg, g.parent_at_work_flg, g.parent_approved_flg, g.create_flg, g.at_work_flg, g.final_approved_flg, g.agr_signed_flg,
    g.product_branch, g.tas_row_count, g.payload_variant_count, g.application_id_count,
    g.max_processed_dttm,
    case when g.application_rk is not null then 'APPLICATION'
         when g.parent_application_rk is not null and g.parent_src_cd = 'MSSA'
              and g.src_cd is null then 'UZ_ONLY'
         else 'INVALID_KEYS' end as tas_entity_type
from (
    select r.parent_application_rk, r.parent_src_cd, r.application_rk, r.src_cd,
        case when r.application_rk is null and r.parent_application_rk is null then r.tas_row_id else null end as invalid_row_group,
        case when count(distinct r.parent_application_id) = 1 then min(r.parent_application_id) else null end as parent_application_id,
        case when count(distinct r.parent_application_dt) = 1 then min(r.parent_application_dt) else null end as parent_application_dt,
        case when count(distinct r.parent_approved_dttm) = 1 then min(r.parent_approved_dttm) else null end as parent_approved_dttm,
        case when count(distinct r.application_id) = 1 then min(r.application_id) else null end as application_id,
        case when count(distinct r.application_dt) = 1 then min(r.application_dt) else null end as application_dt,
        case when count(distinct r.application_type_cd) = 1 then min(r.application_type_cd) else null end as application_type_cd,
        case when count(distinct r.deal_issue_date) = 1 then min(r.deal_issue_date) else null end as deal_issue_date,
        case when count(distinct r.level25_product_bp_nm) = 1 then min(r.level25_product_bp_nm) else null end as level25_product_bp_nm,
        case when count(distinct r.level35_product_bp_nm) = 1 then min(r.level35_product_bp_nm) else null end as level35_product_bp_nm,
        case when count(distinct r.parent_open_flg) = 1 then bool_or(r.parent_open_flg) else null end as parent_open_flg,
        case when count(distinct r.parent_prescoring_flg) = 1 then bool_or(r.parent_prescoring_flg) else null end as parent_prescoring_flg,
        case when count(distinct r.parent_at_work_flg) = 1 then bool_or(r.parent_at_work_flg) else null end as parent_at_work_flg,
        case when count(distinct r.parent_approved_flg) = 1 then bool_or(r.parent_approved_flg) else null end as parent_approved_flg,
        case when count(distinct r.create_flg) = 1 then bool_or(r.create_flg) else null end as create_flg,
        case when count(distinct r.at_work_flg) = 1 then bool_or(r.at_work_flg) else null end as at_work_flg,
        case when count(distinct r.final_approved_flg) = 1 then bool_or(r.final_approved_flg) else null end as final_approved_flg,
        case when count(distinct r.agr_signed_flg) = 1 then bool_or(r.agr_signed_flg) else null end as agr_signed_flg,
        max(r.product_branch) as product_branch,
        count(*) as tas_row_count,
        count(distinct row(r.parent_application_id, r.parent_application_dt, r.parent_approved_dttm, r.application_id, r.application_dt, r.application_type_cd, r.deal_issue_date, r.level25_product_bp_nm, r.level35_product_bp_nm, r.parent_open_flg, r.parent_prescoring_flg, r.parent_at_work_flg, r.parent_approved_flg, r.create_flg, r.at_work_flg, r.final_approved_flg, r.agr_signed_flg)) as payload_variant_count,
        count(distinct r.application_id) as application_id_count,
        max(r.processed_dttm) as max_processed_dttm
    from sbx_pre_orb_fd.prt_qas_kn_kk_tas_raw r
    group by r.parent_application_rk, r.parent_src_cd, r.application_rk, r.src_cd, case when r.application_rk is null and r.parent_application_rk is null then r.tas_row_id else null end
) g
distributed randomly;

-- 2.5. Ключ анкеты -> номер заявки -> BDM RK, с проверкой источника продукта.
drop table if exists sbx_pre_orb_fd.prt_qas_kn_kk_questionnaire_bdm;
create table sbx_pre_orb_fd.prt_qas_kn_kk_questionnaire_bdm
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select distinct
    q.q_entity_id, q.product_branch, a.application_rk, a.src_cd
from sbx_pre_orb_fd.prt_qas_questionnaire q
join sbx_pre_orb_fd.prt_qas_kn_kk_questionnaire_num n
  on n.questionnaire_id = q.questionnaire_id and n.q_src_cd = q.q_src_cd
join sbx_pre_orb_fd.prt_qas_kn_kk_bdm_application a
  on a.application_num = n.application_num
where q.product_branch in ('KN', 'KK')
  and q.product_match_flg = 1 and q.id_count = 1
  and (a.src_cd = 'MSSA'
       or (q.product_branch = 'KN' and a.src_cd = 'MSCL')
       or (q.product_branch = 'KK' and a.src_cd in ('CCPP_CRCA', 'CCPP_BATR')))
distributed randomly;

-- 2.6. Кандидаты: прямой путь, родитель УЗ, УЗ без ребёнка, собственный ключ УЗ.
drop table if exists sbx_pre_orb_fd.prt_qas_kn_kk_link_candidates;
create table sbx_pre_orb_fd.prt_qas_kn_kk_link_candidates
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select distinct
    b.product_branch, b.q_entity_id, t.app_entity_id, cast('DIRECT_PRODUCT' as text) as link_route
from sbx_pre_orb_fd.prt_qas_kn_kk_questionnaire_bdm b
join sbx_pre_orb_fd.prt_qas_kn_kk_tas t
  on t.application_rk = b.application_rk and t.src_cd = b.src_cd
where b.src_cd <> 'MSSA'
union all
select distinct b.product_branch, b.q_entity_id, t.app_entity_id, 'UZ_PARENT'
from sbx_pre_orb_fd.prt_qas_kn_kk_questionnaire_bdm b
join sbx_pre_orb_fd.prt_qas_kn_kk_tas t
  on t.parent_application_rk = b.application_rk and t.parent_src_cd = 'MSSA'
 and t.product_branch = b.product_branch and t.application_rk is not null
where b.src_cd = 'MSSA'
union all
select distinct b.product_branch, b.q_entity_id, t.app_entity_id, 'UZ_ONLY'
from sbx_pre_orb_fd.prt_qas_kn_kk_questionnaire_bdm b
join sbx_pre_orb_fd.prt_qas_kn_kk_tas t
  on t.parent_application_rk = b.application_rk and t.parent_src_cd = 'MSSA'
 and t.tas_entity_type = 'UZ_ONLY'
where b.src_cd = 'MSSA'
union all
select distinct b.product_branch, b.q_entity_id, t.app_entity_id, 'UZ_SELF'
from sbx_pre_orb_fd.prt_qas_kn_kk_questionnaire_bdm b
join sbx_pre_orb_fd.prt_qas_kn_kk_tas t
  on t.application_rk = b.application_rk and t.src_cd = 'MSSA'
where b.src_cd = 'MSSA'
distributed randomly;

-- 2.7. Сравнение путей: уникальные сущности, покрытие и N:M. UZ_ONLY — отдельная цель.
drop table if exists sbx_pre_orb_fd.prt_qas_kn_kk_link_quality;
create table sbx_pre_orb_fd.prt_qas_kn_kk_link_quality
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
with branches as (
    select cast('KN' as text) as product_branch union all select 'KK'
), routes as (
    select cast('DIRECT_PRODUCT' as text) as link_route
    union all select 'UZ_PARENT' union all select 'UZ_ONLY' union all select 'UZ_SELF'
), q_totals as (
    select product_branch, count(*) as q_total
    from sbx_pre_orb_fd.prt_qas_questionnaire group by product_branch
), q_degrees as (
    select product_branch, link_route, q_entity_id, count(*) as app_count
    from sbx_pre_orb_fd.prt_qas_kn_kk_link_candidates group by product_branch, link_route, q_entity_id
), app_degrees as (
    select product_branch, link_route, app_entity_id, count(*) as q_count
    from sbx_pre_orb_fd.prt_qas_kn_kk_link_candidates group by product_branch, link_route, app_entity_id
), q_matches as (
    select product_branch, link_route, count(*) as q_matched,
           sum(case when app_count > 1 then 1 else 0 end) as q_with_many_apps
    from q_degrees group by product_branch, link_route
), app_matches as (
    select product_branch, link_route, count(*) as app_matched,
           sum(case when q_count > 1 then 1 else 0 end) as apps_with_many_q
    from app_degrees group by product_branch, link_route
), pair_stats as (
    select e.product_branch, e.link_route, count(*) as pair_count,
           sum(case when q.app_count > 1 and a.q_count > 1 then 1 else 0 end) as many_to_many_pairs
    from sbx_pre_orb_fd.prt_qas_kn_kk_link_candidates e
    join q_degrees q on q.product_branch = e.product_branch and q.link_route = e.link_route
                   and q.q_entity_id = e.q_entity_id
    join app_degrees a on a.product_branch = e.product_branch and a.link_route = e.link_route
                     and a.app_entity_id = e.app_entity_id
    group by e.product_branch, e.link_route
), target_totals as (
    select b.product_branch, r.link_route, count(t.app_entity_id) as app_total
    from branches b cross join routes r
    left join sbx_pre_orb_fd.prt_qas_kn_kk_tas t
      on (r.link_route in ('DIRECT_PRODUCT', 'UZ_PARENT') and t.product_branch = b.product_branch)
      or (r.link_route = 'UZ_ONLY' and t.tas_entity_type = 'UZ_ONLY')
      or (r.link_route = 'UZ_SELF' and t.src_cd = 'MSSA')
    group by b.product_branch, r.link_route
)
select b.product_branch, r.link_route,
       coalesce(q.q_total, 0) as q_total, coalesce(m.q_matched, 0) as q_matched,
       round(100.0 * coalesce(m.q_matched, 0) / nullif(q.q_total, 0), 2) as q_coverage_pct,
       t.app_total, coalesce(a.app_matched, 0) as app_matched,
       round(100.0 * coalesce(a.app_matched, 0) / nullif(t.app_total, 0), 2) as app_coverage_pct,
       coalesce(p.pair_count, 0) as pair_count,
       coalesce(m.q_with_many_apps, 0) as q_with_many_apps,
       coalesce(a.apps_with_many_q, 0) as apps_with_many_q,
       coalesce(p.many_to_many_pairs, 0) as many_to_many_pairs
from branches b cross join routes r
left join q_totals q on q.product_branch = b.product_branch
left join q_matches m on m.product_branch = b.product_branch and m.link_route = r.link_route
left join app_matches a on a.product_branch = b.product_branch and a.link_route = r.link_route
left join pair_stats p on p.product_branch = b.product_branch and p.link_route = r.link_route
join target_totals t on t.product_branch = b.product_branch and t.link_route = r.link_route
distributed randomly;

-- 2.8. Выбор режима и одна строка на пару; сохраняем все обнаружившие её пути.
drop table if exists sbx_pre_orb_fd.prt_qas_kn_kk_links;
create table sbx_pre_orb_fd.prt_qas_kn_kk_links
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select d.q_entity_id, d.app_entity_id, d.link_routes,
       count(*) over (partition by d.q_entity_id) as q_link_count,
       count(*) over (partition by d.app_entity_id) as app_link_count
from (
    select c.q_entity_id, c.app_entity_id,
           string_agg(c.link_route, ',' order by c.link_route) as link_routes
    from sbx_pre_orb_fd.prt_qas_kn_kk_link_candidates c
    cross join sbx_pre_orb_fd.prt_qas_params p
    where p.kn_kk_link_mode = 'ALL'
       or (p.kn_kk_link_mode = 'DIRECT' and c.link_route = 'DIRECT_PRODUCT')
       or (p.kn_kk_link_mode = 'UZ' and c.link_route in ('UZ_PARENT', 'UZ_ONLY', 'UZ_SELF'))
    group by c.q_entity_id, c.app_entity_id
) d
distributed randomly;

-- 2.9. Ветка целиком: связанные пары + анкеты без пары + все строки TAS без пары.
drop table if exists sbx_pre_orb_fd.prt_qas_kn_kk_fin;
create table sbx_pre_orb_fd.prt_qas_kn_kk_fin
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    coalesce(q.product_branch, t.product_branch) as product_branch,
    cast(case when q.q_entity_id is null then 'APPLICATION_ONLY'
              when t.app_entity_id is null then 'QUESTIONNAIRE_ONLY'
              else 'MATCHED' end as text) as record_type,
    l.link_routes,
    cast(case when l.q_entity_id is null then 'NO_LINK'
              when l.q_link_count > 1 and l.app_link_count > 1 then 'N:M'
              when l.q_link_count > 1 then '1:N'
              when l.app_link_count > 1 then 'N:1'
              else '1:1' end as text) as link_cardinality,
    l.q_link_count, l.app_link_count,
    q.q_entity_id as q_entity_id,
    q.questionnaire_rk as q_questionnaire_rk,
    q.questionnaire_id as q_questionnaire_id,
    q.q_src_cd as q_src_cd,
    q.questionnaire_dttm as q_questionnaire_dttm,
    q.status_cd as q_status_cd,
    q.status_name as q_status_name,
    q.product_type_cd as q_product_type_cd,
    q.program_type as q_program_type,
    q.level25_product_bp_nm as q_level25_product_bp_nm,
    q.product_match_flg as q_product_match_flg,
    q.current_row_count as q_current_row_count,
    q.id_count as q_id_count,
    q.status_count as q_status_count,
    q.verification_flg as verification_flg,
    case when t.app_entity_id is not null then 'KN_KK:' || cast(t.app_entity_id as text) else null end as tas_entity_id,
    t.parent_application_rk as tas_parent_application_rk,
    t.parent_src_cd as tas_parent_src_cd,
    t.application_rk as tas_application_rk,
    t.src_cd as tas_src_cd,
    t.parent_application_id as tas_parent_application_id,
    t.parent_application_dt as tas_parent_application_dt,
    t.parent_approved_dttm as tas_parent_approved_dttm,
    t.application_id as tas_application_id,
    t.application_dt as tas_application_dt,
    t.application_type_cd as tas_application_type_cd,
    t.deal_issue_date as tas_deal_issue_date,
    t.level25_product_bp_nm as tas_level25_product_bp_nm,
    t.level35_product_bp_nm as tas_level35_product_bp_nm,
    t.parent_open_flg as tas_parent_open_flg,
    t.parent_prescoring_flg as tas_parent_prescoring_flg,
    t.parent_at_work_flg as tas_parent_at_work_flg,
    t.parent_approved_flg as tas_parent_approved_flg,
    t.create_flg as tas_create_flg,
    t.at_work_flg as tas_at_work_flg,
    t.final_approved_flg as tas_final_approved_flg,
    t.agr_signed_flg as tas_agr_signed_flg,
    t.tas_entity_type as tas_entity_type,
    t.tas_row_count as tas_row_count,
    t.payload_variant_count as tas_payload_variant_count,
    t.max_processed_dttm as tas_max_processed_dttm
from (select q0.* from sbx_pre_orb_fd.prt_qas_questionnaire q0 where q0.product_branch in ('KN', 'KK')) q
left join sbx_pre_orb_fd.prt_qas_kn_kk_links l on l.q_entity_id = q.q_entity_id
full outer join sbx_pre_orb_fd.prt_qas_kn_kk_tas t on t.app_entity_id = l.app_entity_id
distributed randomly;

-- Отчёт КН/КК: прямой и родительский пути сравниваются на одной базе анкет.
-- У UZ_ONLY/UZ_SELF другой набор целевых сущностей TAS; app_coverage не смешиваем.
select product_branch, link_route, q_total, q_matched, q_coverage_pct,
       pair_count, many_to_many_pairs
from sbx_pre_orb_fd.prt_qas_kn_kk_link_quality order by product_branch, link_route;

-- ==================== 3. ВЕТКА АВТОКРЕДИТОВ ====================

-- 3.1. Загрузка TAS: предполагаемый актуальный снимок; -1 -> NULL перед связями.
drop table if exists sbx_pre_orb_fd.prt_qas_auto_tas_raw;
create table sbx_pre_orb_fd.prt_qas_auto_tas_raw
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    row_number() over (order by t.src_cd nulls first, t.application_rk nulls first,
                       t.parent_application_rk nulls first) as tas_row_id,
    nullif(t.parent_application_rk, -1) as parent_application_rk,
    t.parent_src_cd,
    nullif(t.application_rk, -1) as application_rk,
    t.src_cd,
    t.parent_application_id, t.parent_application_dt, t.parent_approved_dttm, t.application_id, t.application_dt, t.application_type_cd, t.deal_issue_date, t.level25_product_bp_nm, t.level35_product_bp_nm, cast(t.parent_open_flg as boolean) as parent_open_flg, cast(t.parent_prescoring_flg as boolean) as parent_prescoring_flg, cast(t.parent_at_work_flg as boolean) as parent_at_work_flg, cast(t.parent_approved_flg as boolean) as parent_approved_flg, cast(t.create_flg as boolean) as create_flg, cast(t.at_work_flg as boolean) as at_work_flg, cast(t.final_approved_flg as boolean) as final_approved_flg, cast(t.agr_signed_flg as boolean) as agr_signed_flg,
    t.processed_dttm,
    case when t.src_cd = 'ALPP' then 'AUTO'
         when t.src_cd = 'MSCL' then 'KN'
         when t.src_cd in ('CCPP_CRCA', 'CCPP_BATR') then 'KK'
         else 'UZ' end as product_branch
from sbx_pre_orb_fd.tech_application_status t
cross join sbx_pre_orb_fd.prt_qas_params p
where t.src_cd = 'ALPP'
  and (coalesce(t.application_dt, t.parent_application_dt) >= p.begin_date
       or coalesce(t.application_dt, t.parent_application_dt) is null)
-- При версионной TAS добавить подтверждённый фильтр актуальности ЗДЕСЬ.
distributed randomly;

-- 3.2. Сущности TAS: ключ родителя + ребёнка; конфликты атрибутов не выбираем произвольно.
drop table if exists sbx_pre_orb_fd.prt_qas_auto_tas;
create table sbx_pre_orb_fd.prt_qas_auto_tas
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    row_number() over (order by g.src_cd nulls first, g.application_rk nulls first,
                       g.parent_src_cd nulls first, g.parent_application_rk nulls first,
                       g.invalid_row_group nulls first) as app_entity_id,
    g.parent_application_rk, g.parent_src_cd, g.application_rk, g.src_cd, g.parent_application_id, g.parent_application_dt, g.parent_approved_dttm, g.application_id, g.application_dt, g.application_type_cd, g.deal_issue_date, g.level25_product_bp_nm, g.level35_product_bp_nm, g.parent_open_flg, g.parent_prescoring_flg, g.parent_at_work_flg, g.parent_approved_flg, g.create_flg, g.at_work_flg, g.final_approved_flg, g.agr_signed_flg,
    g.product_branch, g.tas_row_count, g.payload_variant_count, g.application_id_count,
    g.max_processed_dttm,
    case when g.application_rk is not null then 'APPLICATION'
         when g.parent_application_rk is not null and g.parent_src_cd = 'MSSA'
              and g.src_cd is null then 'UZ_ONLY'
         else 'INVALID_KEYS' end as tas_entity_type
from (
    select r.parent_application_rk, r.parent_src_cd, r.application_rk, r.src_cd,
        case when r.application_rk is null and r.parent_application_rk is null then r.tas_row_id else null end as invalid_row_group,
        case when count(distinct r.parent_application_id) = 1 then min(r.parent_application_id) else null end as parent_application_id,
        case when count(distinct r.parent_application_dt) = 1 then min(r.parent_application_dt) else null end as parent_application_dt,
        case when count(distinct r.parent_approved_dttm) = 1 then min(r.parent_approved_dttm) else null end as parent_approved_dttm,
        case when count(distinct r.application_id) = 1 then min(r.application_id) else null end as application_id,
        case when count(distinct r.application_dt) = 1 then min(r.application_dt) else null end as application_dt,
        case when count(distinct r.application_type_cd) = 1 then min(r.application_type_cd) else null end as application_type_cd,
        case when count(distinct r.deal_issue_date) = 1 then min(r.deal_issue_date) else null end as deal_issue_date,
        case when count(distinct r.level25_product_bp_nm) = 1 then min(r.level25_product_bp_nm) else null end as level25_product_bp_nm,
        case when count(distinct r.level35_product_bp_nm) = 1 then min(r.level35_product_bp_nm) else null end as level35_product_bp_nm,
        case when count(distinct r.parent_open_flg) = 1 then bool_or(r.parent_open_flg) else null end as parent_open_flg,
        case when count(distinct r.parent_prescoring_flg) = 1 then bool_or(r.parent_prescoring_flg) else null end as parent_prescoring_flg,
        case when count(distinct r.parent_at_work_flg) = 1 then bool_or(r.parent_at_work_flg) else null end as parent_at_work_flg,
        case when count(distinct r.parent_approved_flg) = 1 then bool_or(r.parent_approved_flg) else null end as parent_approved_flg,
        case when count(distinct r.create_flg) = 1 then bool_or(r.create_flg) else null end as create_flg,
        case when count(distinct r.at_work_flg) = 1 then bool_or(r.at_work_flg) else null end as at_work_flg,
        case when count(distinct r.final_approved_flg) = 1 then bool_or(r.final_approved_flg) else null end as final_approved_flg,
        case when count(distinct r.agr_signed_flg) = 1 then bool_or(r.agr_signed_flg) else null end as agr_signed_flg,
        max(r.product_branch) as product_branch,
        count(*) as tas_row_count,
        count(distinct row(r.parent_application_id, r.parent_application_dt, r.parent_approved_dttm, r.application_id, r.application_dt, r.application_type_cd, r.deal_issue_date, r.level25_product_bp_nm, r.level35_product_bp_nm, r.parent_open_flg, r.parent_prescoring_flg, r.parent_at_work_flg, r.parent_approved_flg, r.create_flg, r.at_work_flg, r.final_approved_flg, r.agr_signed_flg)) as payload_variant_count,
        count(distinct r.application_id) as application_id_count,
        max(r.processed_dttm) as max_processed_dttm
    from sbx_pre_orb_fd.prt_qas_auto_tas_raw r
    group by r.parent_application_rk, r.parent_src_cd, r.application_rk, r.src_cd, case when r.application_rk is null and r.parent_application_rk is null then r.tas_row_id else null end
) g
distributed randomly;

-- 3.3. Связь авто по questionnaire_id = application_id с источником и продуктом.
drop table if exists sbx_pre_orb_fd.prt_qas_auto_links;
create table sbx_pre_orb_fd.prt_qas_auto_links
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select d.q_entity_id, d.app_entity_id,
       cast('AUTO_ID' as text) as link_routes,
       count(*) over (partition by d.q_entity_id) as q_link_count,
       count(*) over (partition by d.app_entity_id) as app_link_count
from (
    select distinct q.q_entity_id, t.app_entity_id
    from sbx_pre_orb_fd.prt_qas_questionnaire q
    join sbx_pre_orb_fd.prt_qas_auto_tas t on t.application_id = q.questionnaire_id
    where q.product_branch = 'AUTO' and q.product_match_flg = 1 and q.id_count = 1
      and t.src_cd = 'ALPP' and t.application_id_count = 1
      and nullif(btrim(q.questionnaire_id), '') is not null
      and nullif(btrim(t.application_id), '') is not null
) d
distributed randomly;

-- 3.4. Ветка целиком: связанные пары + анкеты без пары + все строки TAS без пары.
drop table if exists sbx_pre_orb_fd.prt_qas_auto_fin;
create table sbx_pre_orb_fd.prt_qas_auto_fin
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    coalesce(q.product_branch, t.product_branch) as product_branch,
    cast(case when q.q_entity_id is null then 'APPLICATION_ONLY'
              when t.app_entity_id is null then 'QUESTIONNAIRE_ONLY'
              else 'MATCHED' end as text) as record_type,
    l.link_routes,
    cast(case when l.q_entity_id is null then 'NO_LINK'
              when l.q_link_count > 1 and l.app_link_count > 1 then 'N:M'
              when l.q_link_count > 1 then '1:N'
              when l.app_link_count > 1 then 'N:1'
              else '1:1' end as text) as link_cardinality,
    l.q_link_count, l.app_link_count,
    q.q_entity_id as q_entity_id,
    q.questionnaire_rk as q_questionnaire_rk,
    q.questionnaire_id as q_questionnaire_id,
    q.q_src_cd as q_src_cd,
    q.questionnaire_dttm as q_questionnaire_dttm,
    q.status_cd as q_status_cd,
    q.status_name as q_status_name,
    q.product_type_cd as q_product_type_cd,
    q.program_type as q_program_type,
    q.level25_product_bp_nm as q_level25_product_bp_nm,
    q.product_match_flg as q_product_match_flg,
    q.current_row_count as q_current_row_count,
    q.id_count as q_id_count,
    q.status_count as q_status_count,
    q.verification_flg as verification_flg,
    case when t.app_entity_id is not null then 'AUTO:' || cast(t.app_entity_id as text) else null end as tas_entity_id,
    t.parent_application_rk as tas_parent_application_rk,
    t.parent_src_cd as tas_parent_src_cd,
    t.application_rk as tas_application_rk,
    t.src_cd as tas_src_cd,
    t.parent_application_id as tas_parent_application_id,
    t.parent_application_dt as tas_parent_application_dt,
    t.parent_approved_dttm as tas_parent_approved_dttm,
    t.application_id as tas_application_id,
    t.application_dt as tas_application_dt,
    t.application_type_cd as tas_application_type_cd,
    t.deal_issue_date as tas_deal_issue_date,
    t.level25_product_bp_nm as tas_level25_product_bp_nm,
    t.level35_product_bp_nm as tas_level35_product_bp_nm,
    t.parent_open_flg as tas_parent_open_flg,
    t.parent_prescoring_flg as tas_parent_prescoring_flg,
    t.parent_at_work_flg as tas_parent_at_work_flg,
    t.parent_approved_flg as tas_parent_approved_flg,
    t.create_flg as tas_create_flg,
    t.at_work_flg as tas_at_work_flg,
    t.final_approved_flg as tas_final_approved_flg,
    t.agr_signed_flg as tas_agr_signed_flg,
    t.tas_entity_type as tas_entity_type,
    t.tas_row_count as tas_row_count,
    t.payload_variant_count as tas_payload_variant_count,
    t.max_processed_dttm as tas_max_processed_dttm
from (select q0.* from sbx_pre_orb_fd.prt_qas_questionnaire q0 where q0.product_branch = 'AUTO') q
left join sbx_pre_orb_fd.prt_qas_auto_links l on l.q_entity_id = q.q_entity_id
full outer join sbx_pre_orb_fd.prt_qas_auto_tas t on t.app_entity_id = l.app_entity_id
distributed randomly;

-- ==================== 4. ИТОГОВАЯ ВИТРИНА И КОНТРОЛИ ====================

-- 4.1. Единая витрина. Явный состав колонок, общий флаг и обе стороны без пары.
drop table if exists sbx_pre_orb_fd.prt_tech_questionnaire_application_status;
create table sbx_pre_orb_fd.prt_tech_questionnaire_application_status
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    product_branch,
    record_type,
    link_routes,
    link_cardinality,
    q_link_count,
    app_link_count,
    q_entity_id,
    q_questionnaire_rk,
    q_questionnaire_id,
    q_src_cd,
    q_questionnaire_dttm,
    q_status_cd,
    q_status_name,
    q_product_type_cd,
    q_program_type,
    q_level25_product_bp_nm,
    q_product_match_flg,
    q_current_row_count,
    q_id_count,
    q_status_count,
    verification_flg,
    tas_entity_id,
    tas_parent_application_rk,
    tas_parent_src_cd,
    tas_application_rk,
    tas_src_cd,
    tas_parent_application_id,
    tas_parent_application_dt,
    tas_parent_approved_dttm,
    tas_application_id,
    tas_application_dt,
    tas_application_type_cd,
    tas_deal_issue_date,
    tas_level25_product_bp_nm,
    tas_level35_product_bp_nm,
    tas_parent_open_flg,
    tas_parent_prescoring_flg,
    tas_parent_at_work_flg,
    tas_parent_approved_flg,
    tas_create_flg,
    tas_at_work_flg,
    tas_final_approved_flg,
    tas_agr_signed_flg,
    tas_entity_type,
    tas_row_count,
    tas_payload_variant_count,
    tas_max_processed_dttm,
    p.report_dttm
from sbx_pre_orb_fd.prt_qas_kn_kk_fin k
cross join sbx_pre_orb_fd.prt_qas_params p
union all
select
    product_branch,
    record_type,
    link_routes,
    link_cardinality,
    q_link_count,
    app_link_count,
    q_entity_id,
    q_questionnaire_rk,
    q_questionnaire_id,
    q_src_cd,
    q_questionnaire_dttm,
    q_status_cd,
    q_status_name,
    q_product_type_cd,
    q_program_type,
    q_level25_product_bp_nm,
    q_product_match_flg,
    q_current_row_count,
    q_id_count,
    q_status_count,
    verification_flg,
    tas_entity_id,
    tas_parent_application_rk,
    tas_parent_src_cd,
    tas_application_rk,
    tas_src_cd,
    tas_parent_application_id,
    tas_parent_application_dt,
    tas_parent_approved_dttm,
    tas_application_id,
    tas_application_dt,
    tas_application_type_cd,
    tas_deal_issue_date,
    tas_level25_product_bp_nm,
    tas_level35_product_bp_nm,
    tas_parent_open_flg,
    tas_parent_prescoring_flg,
    tas_parent_at_work_flg,
    tas_parent_approved_flg,
    tas_create_flg,
    tas_at_work_flg,
    tas_final_approved_flg,
    tas_agr_signed_flg,
    tas_entity_type,
    tas_row_count,
    tas_payload_variant_count,
    tas_max_processed_dttm,
    p.report_dttm
from sbx_pre_orb_fd.prt_qas_auto_fin a
cross join sbx_pre_orb_fd.prt_qas_params p
distributed randomly;

-- 4.2. Покрытие уникальных сущностей по веткам и общей базе; строки пары не знаменатель.
drop table if exists sbx_pre_orb_fd.prt_qas_coverage;
create table sbx_pre_orb_fd.prt_qas_coverage
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
with totals as (
    select product_branch,
           count(distinct q_entity_id) as q_total,
           count(distinct case when record_type = 'MATCHED' then q_entity_id end) as q_matched,
           count(distinct tas_entity_id) as app_total,
           count(distinct case when record_type = 'MATCHED' then tas_entity_id end) as app_matched
    from sbx_pre_orb_fd.prt_tech_questionnaire_application_status group by product_branch
    union all
    select 'ALL', count(distinct q_entity_id),
           count(distinct case when record_type = 'MATCHED' then q_entity_id end),
           count(distinct tas_entity_id),
           count(distinct case when record_type = 'MATCHED' then tas_entity_id end)
    from sbx_pre_orb_fd.prt_tech_questionnaire_application_status
)
select t.product_branch, t.q_total, t.q_matched,
       round(100.0 * t.q_matched / nullif(t.q_total, 0), 2) as q_coverage_pct,
       t.app_total, t.app_matched,
       round(100.0 * t.app_matched / nullif(t.app_total, 0), 2) as app_coverage_pct,
       round(100.0 * (t.q_matched + t.app_matched) / nullif(t.q_total + t.app_total, 0), 2) as entity_coverage_pct,
       p.min_coverage_pct as reference_coverage_pct
from totals t cross join sbx_pre_orb_fd.prt_qas_params p
distributed randomly;

-- 4.3. Контроли сохранности/уникальности. Все error_count должны быть 0.
drop table if exists sbx_pre_orb_fd.prt_qas_checks;
create table sbx_pre_orb_fd.prt_qas_checks
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select cast('MISSING_QUESTIONNAIRES' as text) as check_name, count(*) as error_count
from sbx_pre_orb_fd.prt_qas_questionnaire q
where not exists (select 1 from sbx_pre_orb_fd.prt_tech_questionnaire_application_status f where f.q_entity_id = q.q_entity_id)
union all
select 'MISSING_KN_KK_TAS', count(*) from sbx_pre_orb_fd.prt_qas_kn_kk_tas t
where not exists (select 1 from sbx_pre_orb_fd.prt_tech_questionnaire_application_status f
                  where f.tas_entity_id = 'KN_KK:' || cast(t.app_entity_id as text))
union all
select 'MISSING_AUTO_TAS', count(*) from sbx_pre_orb_fd.prt_qas_auto_tas t
where not exists (select 1 from sbx_pre_orb_fd.prt_tech_questionnaire_application_status f
                  where f.tas_entity_id = 'AUTO:' || cast(t.app_entity_id as text))
union all
select 'DUPLICATE_FINAL_PAIRS', count(*) from (
    select q_entity_id, tas_entity_id
    from sbx_pre_orb_fd.prt_tech_questionnaire_application_status
    group by q_entity_id, tas_entity_id having count(*) > 1
) d
union all
select 'DUPLICATE_VERIFICATION_KEYS', count(*) from (
    select questionnaire_rk, src_cd from sbx_pre_orb_fd.prt_qas_verification_flags
    group by questionnaire_rk, src_cd having count(*) > 1
) d
union all
select 'INCONSISTENT_VERIFICATION_FLAGS', count(*) from (
    select q_entity_id from sbx_pre_orb_fd.prt_tech_questionnaire_application_status
    where q_entity_id is not null
    group by q_entity_id having count(distinct verification_flg) > 1
) d
union all
select 'EMPTY_FINAL_ROWS', count(*) from sbx_pre_orb_fd.prt_tech_questionnaire_application_status
where q_entity_id is null and tas_entity_id is null
union all
select 'INVALID_LINK_MODE', count(*) from sbx_pre_orb_fd.prt_qas_params
where kn_kk_link_mode not in ('ALL', 'DIRECT', 'UZ') or kn_kk_link_mode is null
distributed randomly;

-- Результат 4.4: все контроли сохранности/уникальности должны быть 0.
select check_name, error_count from sbx_pre_orb_fd.prt_qas_checks order by check_name;

-- Результат 4.5: ориентир 10% показываем по анкетам, TAS и общей базе сущностей.
-- Общая строка ALL считает TAS-сущности один раз, даже если УЗ связалась с КН и КК.
select * from sbx_pre_orb_fd.prt_qas_coverage order by product_branch;

-- Результат 4.6: несвязанные стороны и кардинальность. N:M требует исследования.
select product_branch, record_type, link_cardinality, count(*) as row_count
from sbx_pre_orb_fd.prt_tech_questionnaire_application_status
group by product_branch, record_type, link_cardinality
order by product_branch, record_type, link_cardinality;

-- Результат 4.7: качество текущего среза анкет, включая сохранённые NULL ключи.
select product_branch, count(*) as questionnaire_count,
       sum(case when questionnaire_rk is null then 1 else 0 end) as missing_rk_count,
       sum(case when product_match_flg <> 1 then 1 else 0 end) as product_mismatch_count,
       sum(case when id_count > 1 then 1 else 0 end) as conflicting_id_count,
       sum(case when status_count > 1 then 1 else 0 end) as conflicting_status_count,
       sum(case when questionnaire_dttm is null then 1 else 0 end) as missing_date_count
from sbx_pre_orb_fd.prt_qas_questionnaire group by product_branch order by product_branch;

-- Результат 4.8: несколько разных наборов атрибутов на ключе TAS.
-- При таких конфликтах прежде всего проверить snapshot-контракт/актуальность TAS.
select cast('KN_KK' as text) as branch_group, count(*) as conflicting_tas_entities
from sbx_pre_orb_fd.prt_qas_kn_kk_tas where payload_variant_count > 1
union all
select 'AUTO', count(*) from sbx_pre_orb_fd.prt_qas_auto_tas where payload_variant_count > 1;

-- Результат 4.9: число номеров на одну анкету в мосте источника.
select q_src_cd, count(*) as questionnaires_with_multiple_nums
from (
    select questionnaire_id, q_src_cd
    from sbx_pre_orb_fd.prt_qas_kn_kk_questionnaire_num
    group by questionnaire_id, q_src_cd having count(*) > 1
) d group by q_src_cd order by q_src_cd;

-- Результат 4.10: только история, прочитанная этим скриптом; полнота ETL
-- не доказывается отсутствием пустых статусов. При усечённой истории false
-- следует трактовать как «пока не найдено», а не как факт непрохождения.
select src_cd, sum(history_row_count) as history_rows,
       sum(empty_status_rows) as empty_status_rows
from sbx_pre_orb_fd.prt_qas_verification_flags group by src_cd order by src_cd;
