/*
MISREP-4455 TECH_INTERNET_FUNNEL. V5, выбор номера из intention по замечаниям от 06.11.2026.
Анкетные атрибуты и история статусов берутся только из готовой TQS.
questionnaire_x_intention отдаёт ID/номер; дополнительные поля нужны только для выбора строки.
Внутренний ETL TQS в TIF не копируется, новые интервалы версий не рассчитываются.

Макропеременные (подставляются SQL-клиентом/ETL до выполнения):
  &db_sbx             — схема прототипа; по умолчанию: sbx_pre_orb_fd
  &p_db_cdmr          — схема TQS/TAS; по умолчанию: dm_pik_fd_cdmr
  &p_db_rawd          — схема questionnaire_x_intention; по умолчанию: rd_raw_orb
  &p_db_bdm           — схема APPLICATION; по умолчанию: bdm
  &p_min_dttm         — замена NULL в сортировке TQS; по умолчанию: '1900-01-01 00:00:00'
  &p_max_date         — конец текущей версии; по умолчанию: '2999-12-31'
  &P_BEGIN_DATE       — начало пересчитываемой выборки; начальное наполнение: '2025-01-01'
  &p_report_timestamp — единый момент загрузки; пример: '2026-11-05 00:00:00'
  &p_quest_25lvl_product_kn_list   — продукты КН; по умолчанию: 'Потребкредит'
  &p_quest_25lvl_product_kk_list   — продукты КК; по умолчанию: 'Кредитные карты'
  &p_quest_25lvl_product_auto_list — продукты авто; по умолчанию: 'Автокредит'
  &p_kn_verification_status   — по умолчанию: '0', '10.0', 'одобрено',
                               'CHECK_LIST_EMPTY', 'CHECK_LIST_ANTIFRAUD_OR_PRODUCT'
  &p_kk_verification_status   — по умолчанию: 'DONE', 'COURIER'
  &p_auto_verification_status — по умолчанию: 'APPROVE_RKK', 'APPROVED', 'PRE_APPROVED',
                               'APPROVE_CALL2', 'APPROVE_CALL3', 'ORDER_CREATED', 'VERIFICATION',
                               'DRIVER_CARD_ISSUE', 'DRIVER_CARD_ISSUE_UPLOADED', 'DOSSIER_UPLOADED',
                               'DEAL_VER', 'CREDIT_ISSUED', 'PRODUCT_BASKET_SIGNED'
Схемы подставляются без кавычек, строки/даты — в кавычках, списки — через запятую.

База анкет — TQS, включая анкеты без номера и без найденной заявки.
Флаг рассчитывается по всей истории TQS, затем присоединяется к текущему срезу.
questionnaire_dttm и продукт берутся напрямую из текущей строки TQS.
TAS хранит последнее состояние. Для авто: questionnaire_id = application_id.
Для КН/КК: номер из intention -> BDM -> parent_application_rk и parent_src_cd TAS.
При связи флаг true; без заявки — исторический флаг; без анкеты — NULL.
Отсутствующие RK равны -1. level35 берётся из своего поля TAS, без заявки — NULL.
Итог: все анкеты с найденными заявками или без них + только оставшиеся заявки TAS.

Целевой объект: dm_pik_fd_cdmr.TECH_INTERNET_FUNNEL, без истории версий результата.
Регламент: начальное наполнение с 01.01.2025, затем ежедневно после обновления источников
пересчёт с начала прошлого квартала. P_BEGIN_DATE для повторной загрузки задаёт ETL:
GREATEST(DATE '2025-01-01', DATE_TRUNC('quarter', report_timestamp)::date - INTERVAL '3 months').
Прототип пересоздаёт расчётную выборку в sbx; сохранение данных вне окна — задача загрузчика.
Таблицы параметров и дополнительные источники ключей не создаются.
V4 и её таблицы не меняются: все результаты V5 имеют отдельный префикс man_prt_tif_v5_.
В intention проверены повторы одинаковых пар, разных непустых номеров на ID не найдено.
Порядок выбора перенесён из исходного TQS без сокращения приоритетов.
Изменение относительно TQS: PARTITION BY questionnaire_id вместо questionnaire_id, status;
все статусы не требуются, поскольку мосту нужна одна строка на анкету.
Выбирается среди непустых номеров. Это правило V5, а не дословный ETL TQS.
Полный исходный ETL TAS в доступных файлах не найден; его приоритеты не выдумываются.
Готовые TQS/TAS читаются с их контрактом уникальности; нарушения видны в проверках.
GROUP BY остаётся только для содержательного расчёта исторического флага.
*/

-- Шаг 1.1. Исторический флаг верификации по готовой TQS.
-- Откуда: tech_questionnaire_status; продукт и статусы уже рассчитаны её собственным ETL.
-- Зачем: учесть согласованные статусы за всю доступную историю до отбора текущей строки.
drop table if exists &db_sbx.man_prt_tif_v5_verification;
create table &db_sbx.man_prt_tif_v5_verification
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    q.questionnaire_rk,
    q.level25_product_bp_nm,
    cast(max(case
        when q.level25_product_bp_nm in (&p_quest_25lvl_product_kn_list)
         and q.status_cd in (&p_kn_verification_status) then 1
        when q.level25_product_bp_nm in (&p_quest_25lvl_product_kk_list)
         and q.status_cd in (&p_kk_verification_status) then 1
        when q.level25_product_bp_nm in (&p_quest_25lvl_product_auto_list)
         and q.status_cd in (&p_auto_verification_status) then 1
        else 0
    end) as boolean) as quest_verification_flg
from &p_db_cdmr.tech_questionnaire_status q
where q.level25_product_bp_nm in (
    &p_quest_25lvl_product_kn_list,
    &p_quest_25lvl_product_kk_list,
    &p_quest_25lvl_product_auto_list
)
  and q.questionnaire_rk is not null
  and q.questionnaire_rk <> -1
group by q.questionnaire_rk, q.level25_product_bp_nm
) distributed randomly;

-- Шаг 1.2. Анкетные атрибуты из текущего среза TQS.
-- Откуда: готовая tech_questionnaire_status и исторический флаг 1.1.
-- Зачем: сохранить исходные RK, ID, дату и продукт; не вычислять их заново из intention.
drop table if exists &db_sbx.man_prt_tif_v5_questionnaire;
create table &db_sbx.man_prt_tif_v5_questionnaire
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    q.questionnaire_id,
    q.questionnaire_rk,
    q.questionnaire_dttm,
    v.quest_verification_flg,
    q.level25_product_bp_nm
from &p_db_cdmr.tech_questionnaire_status q
inner join &db_sbx.man_prt_tif_v5_verification v
    on v.questionnaire_rk = q.questionnaire_rk
   and v.level25_product_bp_nm = q.level25_product_bp_nm
where q.effective_to_dttm = cast(&p_max_date as timestamp)
  and (q.questionnaire_dttm >= cast(&P_BEGIN_DATE as timestamp)
       or q.questionnaire_dttm is null)
) distributed randomly;

-- Шаг 1.3. [ИЗМЕНЕНО V5] Один непустой номер на questionnaire_id.
-- Откуда: удалённый prt_tqs_questionnaire; порядок ROW_NUMBER сохранён полностью.
-- Сокращено: не рассчитываем даты/статусы/продукт/версии, не выводим личные поля.
-- Нужную популяцию определяет готовая TQS через EXISTS, без размножения по её строкам.
-- [ИЗМЕНЕНО относительно TQS] Раздел окна — ID, без status; фильтр непустого номера до окна.
-- Если номера когда-нибудь станут различаться, V5 выберет строку по этим приоритетам;
-- это требует отдельного контроля: check_internet_funnel_v5.sql, проверка 16.
drop table if exists &db_sbx.man_prt_tif_v5_questionnaire_numbers;
create table &db_sbx.man_prt_tif_v5_questionnaire_numbers
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
with ranked as (
    select
        r.questionnaire_id,
        r.application_num,
        row_number() over (
            partition by r.questionnaire_id
        order by
            coalesce(cast(r.createtime_dttm as timestamp), cast(&p_min_dttm as timestamp)) desc,
            r.sessionintention_id,
            coalesce(cast(r.processed_dttm as timestamp), cast(&p_min_dttm as timestamp)) desc,
            coalesce(cast(r.business_dt as timestamp), cast(&p_min_dttm as timestamp)) desc,
            r.utmcn desc,
            r.utmcct desc,
            r.utmcmd desc,
            coalesce(r.globalclient_id, '#') desc,
            coalesce(r.person_id, '#') desc,
            coalesce(r.last_nm, r.first_nm, r.middle_nm, '#') desc,
            coalesce(r.tax_payer_num, '#') desc,
            coalesce(r.email, '#') desc,
            coalesce(r.client_type, '#') desc,
            coalesce(r.company_nm, '#') desc,
            cast(case when r.phone_num not like ('%%%') then 1 else 0 end as integer) desc,
            r.credit_amt desc,
            r.zero_visits_flg desc,
            r.product_type_code,
            coalesce(cast(r.questionnaire_dt as timestamp), cast(&p_min_dttm as timestamp)) desc,
            r.program_type,
            coalesce(cast(r.scoring_dt as timestamp), cast(&p_min_dttm as timestamp)) desc,
            coalesce(cast(r.prescoring_dt as timestamp), cast(&p_min_dttm as timestamp)) desc,
            r.application_num desc,
            coalesce(r.scoring_status_nm, '#') desc,
            coalesce(r.prescoring_status_nm, '#') desc,
            coalesce(r.spec_program, '#') desc,
            coalesce(r.src_cd_src, '#') desc,
            r.salary_card_flg desc,
            r.phone_num
        ) as rn
    from &p_db_rawd.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention r
    where r.application_num is not null
      and exists (
          select 1
          from &db_sbx.man_prt_tif_v5_questionnaire q
          where q.questionnaire_id = r.questionnaire_id
            and q.level25_product_bp_nm in (
                &p_quest_25lvl_product_kn_list, &p_quest_25lvl_product_kk_list
            )
      )
)
select questionnaire_id, application_num
from ranked
where rn = 1
) distributed randomly;

-- Шаг 1.4. [ИЗМЕНЕНО V5] Переход от анкеты КН/КК через номер к ключу BDM.
-- Откуда: анкеты TQS 1.2 -> пары intention 1.3 -> BDM.APPLICATION.
-- Зачем: получить текущий ключ и источник родителя. GROUP BY убран: номер на ID уже выбран в 1.3.
-- Повторы текущего ключа BDM не скрываем; их контролирует проверка 15.
drop table if exists &db_sbx.man_prt_tif_v5_kn_kk_bdm;
create table &db_sbx.man_prt_tif_v5_kn_kk_bdm
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    q.questionnaire_rk,
    q.level25_product_bp_nm,
    app.application_rk as bdm_application_rk,
    app.src_cd as bdm_src_cd
from &db_sbx.man_prt_tif_v5_questionnaire q
inner join &db_sbx.man_prt_tif_v5_questionnaire_numbers n
    on n.questionnaire_id = q.questionnaire_id
inner join &p_db_bdm.application app
    on app.application_num = n.application_num
   and app.effective_to_date = cast(&p_max_date as date)
   and app.application_rk is not null
   and app.application_rk <> -1
where q.level25_product_bp_nm in (
    &p_quest_25lvl_product_kn_list, &p_quest_25lvl_product_kk_list
)
) distributed randomly;

-- Шаг 1.5. Готовый снимок TAS для трёх продуктов.
-- Откуда: tech_application_status; сохраняются её собственные даты и флаги.
-- Зачем: подготовить заявочную сторону без удаления дублей; NULL-продукт допускается при связи с целевой анкетой.
-- NULL-продукт + EXISTS: резерв для COALESCE(TAS.level25,TQS.level25), не удаление повторов.
-- Проверка пользователя: таких строк 0; условие не влияет на проверенный срез.
-- Полного исходника TAS нет: ROW_NUMBER по processed_dttm здесь не вводим.
drop table if exists &db_sbx.man_prt_tif_v5_tas;
create table &db_sbx.man_prt_tif_v5_tas
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    coalesce(t.parent_application_rk, -1) as parent_application_rk,
    t.parent_application_dt,
    t.parent_src_cd,
    cast(t.parent_open_flg as boolean) as parent_open_flg,
    cast(t.parent_prescoring_flg as boolean) as parent_prescoring_flg,
    cast(t.parent_at_work_flg as boolean) as parent_at_work_flg,
    cast(t.parent_approved_flg as boolean) as parent_approved_flg,
    coalesce(t.application_rk, -1) as application_rk,
    t.application_id,
    t.application_dt,
    t.deal_issue_date,
    cast(t.create_flg as boolean) as create_flg,
    cast(t.at_work_flg as boolean) as at_work_flg,
    cast(t.final_approved_flg as boolean) as final_approved_flg,
    cast(t.agr_signed_flg as boolean) as agr_signed_flg,
    t.level25_product_bp_nm,
    t.level35_product_bp_nm
from &p_db_cdmr.tech_application_status t
where (
    t.level25_product_bp_nm in (
        &p_quest_25lvl_product_kn_list,
        &p_quest_25lvl_product_kk_list,
        &p_quest_25lvl_product_auto_list
    )
    or (t.level25_product_bp_nm is null and (
        exists (
            select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
            where b.bdm_application_rk = t.parent_application_rk
              and b.bdm_src_cd = t.parent_src_cd
        )
        or exists (
            select 1 from &db_sbx.man_prt_tif_v5_questionnaire q
            where q.level25_product_bp_nm in (&p_quest_25lvl_product_auto_list)
              and q.questionnaire_id = t.application_id
        )
    ))
)
  and (coalesce(t.application_dt, t.parent_application_dt) >= cast(&P_BEGIN_DATE as date)
       or coalesce(t.application_dt, t.parent_application_dt) is null)
  -- Хотя бы один реальный ключ: исключить строку без заявки, родитель без дочки допустим.
  -- Проверка пользователя: исключённых строк 0; это не фильтр дублей.
  and (coalesce(t.parent_application_rk, -1) <> -1
       or coalesce(t.application_rk, -1) <> -1)
) distributed randomly;

-- Шаг 2.1. [ИЗМЕНЕНО V5] Найденные пары с атрибутами TAS, без GROUP BY.
-- Откуда: одна текущая анкета и каждая реальная строка TAS.
-- КН/КК: обычный JOIN по родителю и источнику; повторные номера уже устранены в 1.3.
-- Авто: прежнее прямое соответствие ID. Разные дочерние заявки сохраняются.
-- Атрибуты несём сразу: в 2.2 не потребуется повторный JOIN к TAS по неуникальным ключам.
-- Повторы самих исходных TQS/TAS не скрываются: для них нужны исходные ETL и проверки.
drop table if exists &db_sbx.man_prt_tif_v5_matches;
create table &db_sbx.man_prt_tif_v5_matches
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    q.questionnaire_rk,
    q.level25_product_bp_nm,
    t.parent_application_rk,
    t.parent_application_dt,
    t.parent_open_flg,
    t.parent_prescoring_flg,
    t.parent_at_work_flg,
    t.parent_approved_flg,
    t.application_rk,
    t.application_dt,
    t.deal_issue_date,
    t.create_flg,
    t.at_work_flg,
    t.final_approved_flg,
    t.agr_signed_flg,
    t.level25_product_bp_nm as tas_level25_product_bp_nm,
    t.level35_product_bp_nm
from &db_sbx.man_prt_tif_v5_kn_kk_bdm q
inner join &db_sbx.man_prt_tif_v5_tas t
    on q.bdm_application_rk = t.parent_application_rk
   and q.bdm_src_cd = t.parent_src_cd
where t.level25_product_bp_nm in (
    &p_quest_25lvl_product_kn_list, &p_quest_25lvl_product_kk_list
) or t.level25_product_bp_nm is null
union all
select
    q.questionnaire_rk,
    q.level25_product_bp_nm,
    t.parent_application_rk,
    t.parent_application_dt,
    t.parent_open_flg,
    t.parent_prescoring_flg,
    t.parent_at_work_flg,
    t.parent_approved_flg,
    t.application_rk,
    t.application_dt,
    t.deal_issue_date,
    t.create_flg,
    t.at_work_flg,
    t.final_approved_flg,
    t.agr_signed_flg,
    t.level25_product_bp_nm as tas_level25_product_bp_nm,
    t.level35_product_bp_nm
from &db_sbx.man_prt_tif_v5_questionnaire q
inner join &db_sbx.man_prt_tif_v5_tas t
    on q.questionnaire_id = t.application_id
where q.level25_product_bp_nm in (&p_quest_25lvl_product_auto_list)
  and (t.level25_product_bp_nm in (&p_quest_25lvl_product_auto_list)
       or t.level25_product_bp_nm is null)
) distributed randomly;

-- Шаг 2.2. [ИЗМЕНЕНО V5] Все анкеты с найденными заявками или без них.
-- Откуда: готовые атрибуты TQS 1.2 и найденные строки с атрибутами TAS 2.1.
-- [ИЗМЕНЕНО] Убран повторный JOIN к TAS: все её атрибуты уже есть в matches.
-- При нарушении уникальности TAS конфликтующие строки остаются видны по одному разу.
-- Зачем: LEFT JOIN сохраняет анкетную сторону; найденная заявка устанавливает флаг true.
drop table if exists &db_sbx.man_prt_tif_v5_questionnaire_funnel;
create table &db_sbx.man_prt_tif_v5_questionnaire_funnel
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    cast(q.questionnaire_rk as bigint) as questionnaire_rk,
    cast(q.questionnaire_dttm as timestamp) as questionnaire_dttm,
    cast(case
        when t.parent_application_rk is not null or t.application_rk is not null then true
        else q.quest_verification_flg
    end as boolean) as quest_verification_flg,
    cast(coalesce(t.parent_application_rk, -1) as bigint) as parent_application_rk,
    cast(t.parent_application_dt as date) as parent_application_dt,
    cast(t.parent_open_flg as boolean) as parent_open_flg,
    cast(t.parent_prescoring_flg as boolean) as parent_prescoring_flg,
    cast(t.parent_at_work_flg as boolean) as parent_at_work_flg,
    cast(t.parent_approved_flg as boolean) as parent_approved_flg,
    cast(coalesce(t.application_rk, -1) as bigint) as application_rk,
    cast(t.application_dt as date) as application_dt,
    cast(t.deal_issue_date as date) as deal_issue_date,
    cast(t.create_flg as boolean) as create_flg,
    cast(t.at_work_flg as boolean) as at_work_flg,
    cast(t.final_approved_flg as boolean) as final_approved_flg,
    cast(t.agr_signed_flg as boolean) as agr_signed_flg,
    cast(coalesce(t.tas_level25_product_bp_nm, q.level25_product_bp_nm) as text) as level25_product_bp_nm,
    cast(t.level35_product_bp_nm as text) as level35_product_bp_nm,
    cast(&p_report_timestamp as timestamp(0)) as processed_dttm
from &db_sbx.man_prt_tif_v5_questionnaire q
left join &db_sbx.man_prt_tif_v5_matches t
    on t.questionnaire_rk = q.questionnaire_rk
   and t.level25_product_bp_nm = q.level25_product_bp_nm
) distributed randomly;

-- Шаг 2.3. Только оставшиеся заявки TAS.
-- Откуда: снимок TAS 1.5; наличие пары проверяется во всей анкетной таблице 2.2.
-- Зачем: не добавлять повторно уже связанные заявки; проверять оба ключа TAS.
drop table if exists &db_sbx.man_prt_tif_v5_remaining_tas;
create table &db_sbx.man_prt_tif_v5_remaining_tas
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    cast(-1 as bigint) as questionnaire_rk,
    cast(null as timestamp) as questionnaire_dttm,
    cast(null as boolean) as quest_verification_flg,
    cast(coalesce(t.parent_application_rk, -1) as bigint) as parent_application_rk,
    cast(t.parent_application_dt as date) as parent_application_dt,
    cast(t.parent_open_flg as boolean) as parent_open_flg,
    cast(t.parent_prescoring_flg as boolean) as parent_prescoring_flg,
    cast(t.parent_at_work_flg as boolean) as parent_at_work_flg,
    cast(t.parent_approved_flg as boolean) as parent_approved_flg,
    cast(coalesce(t.application_rk, -1) as bigint) as application_rk,
    cast(t.application_dt as date) as application_dt,
    cast(t.deal_issue_date as date) as deal_issue_date,
    cast(t.create_flg as boolean) as create_flg,
    cast(t.at_work_flg as boolean) as at_work_flg,
    cast(t.final_approved_flg as boolean) as final_approved_flg,
    cast(t.agr_signed_flg as boolean) as agr_signed_flg,
    cast(t.level25_product_bp_nm as text) as level25_product_bp_nm,
    cast(t.level35_product_bp_nm as text) as level35_product_bp_nm,
    cast(&p_report_timestamp as timestamp(0)) as processed_dttm
from &db_sbx.man_prt_tif_v5_tas t
where not exists (
    select 1
    from &db_sbx.man_prt_tif_v5_questionnaire_funnel f
    where f.parent_application_rk = t.parent_application_rk
      and f.application_rk = t.application_rk
)
) distributed randomly;

-- Шаг 2.4. Итог: анкетная часть и остаток TAS.
-- Откуда: две непересекающиеся части 2.2 и 2.3; согласованные 19 атрибутов ФТ.
-- Зачем: сохранить связанные пары и обе несвязанные стороны через UNION ALL.
drop table if exists &db_sbx.man_prt_tif_v5_tech_internet_funnel;
create table &db_sbx.man_prt_tif_v5_tech_internet_funnel
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    q.questionnaire_rk,
    q.questionnaire_dttm,
    q.quest_verification_flg,
    q.parent_application_rk,
    q.parent_application_dt,
    q.parent_open_flg,
    q.parent_prescoring_flg,
    q.parent_at_work_flg,
    q.parent_approved_flg,
    q.application_rk,
    q.application_dt,
    q.deal_issue_date,
    q.create_flg,
    q.at_work_flg,
    q.final_approved_flg,
    q.agr_signed_flg,
    q.level25_product_bp_nm,
    q.level35_product_bp_nm,
    q.processed_dttm
from &db_sbx.man_prt_tif_v5_questionnaire_funnel q
union all
select
    t.questionnaire_rk,
    t.questionnaire_dttm,
    t.quest_verification_flg,
    t.parent_application_rk,
    t.parent_application_dt,
    t.parent_open_flg,
    t.parent_prescoring_flg,
    t.parent_at_work_flg,
    t.parent_approved_flg,
    t.application_rk,
    t.application_dt,
    t.deal_issue_date,
    t.create_flg,
    t.at_work_flg,
    t.final_approved_flg,
    t.agr_signed_flg,
    t.level25_product_bp_nm,
    t.level35_product_bp_nm,
    t.processed_dttm
from &db_sbx.man_prt_tif_v5_remaining_tas t
) distributed randomly;
