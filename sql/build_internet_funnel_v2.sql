/*
НОВЫЙ ПРОТОТИП V2. Предыдущий SQL не изменён.
КН/КК: копия кредитной части tech_questionnaire_status с application_num ->
верификация -> bdm.application -> tech_application_status.
Авто: готовая tech_questionnaire_status -> верификация -> tech_application_status.
Итог: &db_sbx.prt_if2_tech_internet_funnel, ровно 19 согласованных полей.
Все создаваемые таблицы имеют префикс prt_if2_; результаты старого SQL не удаляются.

Макропеременные (подстановка SQL-клиентом/ETL, как в исходных прототипах):
  &db_sbx                     - схема результатов; по умолчанию: sbx_pre_orb_fd
  &p_db_rawd                  - схема RAW; по умолчанию: rd_raw_orb
  &p_db_cdmr                  - схема TQS/TAS и связи с RK; по умолчанию: dm_pik_fd_cdmr
  &p_db_bdm                   - схема заявок BDM; по умолчанию: bdm
  &p_max_date                 - максимальная дата; по умолчанию: '2999-12-31'
  &p_min_dttm                 - замена NULL в сортировке; по умолчанию: '1900-01-01 00:00:00'
  &p_rds_report_dt_date       - начало выборки RAW, как в TQS; по умолчанию: '2024-10-01'
  &P_BEGIN_DATE               - начало когорты анкет/заявок; по умолчанию: '2025-01-01'
  &p_report_timestamp         - один момент этой загрузки; пример: '2026-10-19 00:00:00'

  &p_test_first_nm_like_text_list - как в TQS; по умолчанию:
                                 '%ТЕСТ%', '%ТКЕСТ%', '%ТКЕКСТ%', '%ТЕМСТ%', '%ЛИПОВЫЙ%',
                                 '%ЗАЯВК%', 'ПЕНСИОНН%', 'МУЛЬТИКАРТ%', 'АРХАНГЕЛЬСК%', 'ЗВОНИТЬ%', 'AAA%'
  &p_test_first_nm_in_text_list - как в TQS; по умолчанию:
                                 'ПЕНСЫ', 'ЛИД', 'НОВОКУЗНЕЦК', 'ТЕСТ', 'ЛЕХА', 'ДЯДЯ', 'ПРОЛД', 'АРОПР', 'ООО'
  &p_test_last_nm_in_text_list - по умолчанию: 'ТЕСТ'
  &p_test_middle_nm_like_text_list - по умолчанию: 'ТЕСТОВНА'
  &p_quest_product_kn_list    - по умолчанию: 'cm.LiabilityType.Loan', 'RF', 'KN'
  &p_quest_product_kk_list    - по умолчанию: 'cm.LiabilityType.CreditCard', 'CreditCard',
                                'cm.LiabilityType.CreditCard cm.LiabilityType.Loan'
  &p_quest_src_cd_kn_list     - один LIKE-шаблон исходной ветки КН; по умолчанию: '1376%'
  &p_quest_src_cd_kk_list     - один LIKE-шаблон исходной ветки КК; по умолчанию: '1383%'
  &p_quest_not_len_id_kk_list - исключённые длины ID КК; по умолчанию: 6

  &p_quest_25lvl_product_kn_list             - по умолчанию: 'Потребкредит'
  &p_quest_25lvl_product_kk_list             - по умолчанию: 'Кредитные карты'
  &p_quest_25lvl_product_auto_list           - по умолчанию: 'Автокредит'
  &p_kn_verification_status  - по умолчанию: '0', '10.0', 'одобрено', 'CHECK_LIST_EMPTY',
                                'CHECK_LIST_ANTIFRAUD_OR_PRODUCT'
  &p_kk_verification_status  - по умолчанию: 'DONE', 'COURIER'
  &p_auto_verification_status - по умолчанию: 'APPROVE_RKK', 'APPROVED', 'PRE_APPROVED',
                                'APPROVE_CALL2', 'APPROVE_CALL3', 'ORDER_CREATED', 'VERIFICATION',
                                'DRIVER_CARD_ISSUE', 'DRIVER_CARD_ISSUE_UPLOADED', 'DOSSIER_UPLOADED',
                                'DEAL_VER', 'CREDIT_ISSUED', 'PRODUCT_BASKET_SIGNED'

  &P_UZ_SRC                   - источник УЗ; по умолчанию: 'MSSA'
  &P_KN_SRC                   - источник КН; по умолчанию: 'MSCL'
  &P_KK_SRC                   - источники КК; по умолчанию: 'CCPP_CRCA', 'CCPP_BATR'
  &P_AUTO_SRC                 - источник авто; по умолчанию: 'ALPP'
  &p_kn_kk_link_mode         - добавленный в этом прототипе режим сравнения; по умолчанию: 'ALL';
                                'DIRECT' = BDM.application_rk -> TAS.application_rk;
                                'UZ' = BDM УЗ -> TAS.parent_application_rk или собственный RK УЗ.

p_kn_kk_link_mode отсутствует в исходных TQS/TAS: он добавлен для сравнения
прямой связки и пути через УЗ. ALL включает оба условия JOIN в шаге 1.10;
SELECT DISTINCT оставляет одну пару, если совпали оба пути.

Имена схем задаются без кавычек; строки/даты — в одинарных кавычках;
списки — SQL-значения через запятую без внешних скобок; числа — без кавычек.

В 1.1 оставлены исходные CAST, WHERE, MIN и ROW_NUMBER в одном запросе.
Отдельных RAW/parsed/checked/ranked-таблиц нет. Исходные фильтры и формула
EXTRACT(SECONDS) здесь не исправляются и не дополняются новыми проверками.
TQS-цепочка копируется только для КН/КК; для авто RAW не используется.
Флаг — MAX(CASE ... THEN 1 ELSE 0 END), как у флагов TAS, по ВСЕЙ истории.
Статусы берутся из макросписков, соответствующих всем выделениям Excel.
Верификация/соединения анкет после назначения продукта не фильтруют q.src_cd.

В 1.6 сохранён исходный INNER JOIN на существующие RK. Поэтому базой КН/КК
являются анкеты, прошедшие исходный ETL TQS, включая наличие RK. Новые RK
не генерируются. Все номера переживших исходную дедупликацию статусов
сохраняются и участвуют в связи. Версии не отбрасываются до расчёта флага.

TAS читается как готовый актуальный снимок, как в предоставленном DDL.
Поля окончания версии TAS не показано; processed_dttm не используется вместо него.
КН/КК и авто сохраняют несвязанные анкеты и заявки внутри своих когорт.
Оба итоговых уровня продукта равны COALESCE(TAS.level25, TQS.level25).
Описание копирования каждого шага: docs/prototype_v2_steps.txt.
*/

-- ==================== 1. КН/КК: КОПИЯ TQS -> ФЛАГ -> ЗАЯВКА ====================

-- Шаг 1.1. Очистка и подгонка RAW, как в начале tech_questionnaire_status.
-- Откуда: исходный prt_tqs_questionnaire, скриншот строк 53–131.
-- Зачем: получить те же исходные атрибуты/приоритеты сразу для КН/КК; application_num уже есть в исходнике.
-- Копирование: скопировать исходный шаг, добавить WHERE 1.1-A и вывести src_cd_src (1.1-B), если его нет в SELECT.
drop table if exists &db_sbx.prt_if2_tqs_questionnaire;
create table &db_sbx.prt_if2_tqs_questionnaire
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
with pre as (
select distinct
    r.questionnaire_id,
    r.application_num,
    r.utmcn,
    r.utmcmd,
    r.utmcsr,
    r.utmctr,
    r.utmcct,
    r.status,
    r.scoring_status_nm,
    r.prescoring_status_nm,
    r.product_type_code,
    r.program_type,
    r.src_cd,
    cast(min(coalesce(r.questionnaire_dt, r.business_dt, r.createtime_dttm))
        over (partition by r.questionnaire_id) as timestamp) as questionnaire_dttm,
    date_trunc('seconds', cast(coalesce(r.questionnaire_dt, r.business_dt,
        r.createtime_dttm, r.prescoring_dt, r.scoring_dt, r.processed_dttm) as timestamp))
        as original_effective_from_dttm_auto_kn,
    date_trunc('seconds', cast(coalesce(r.business_dt, r.processed_dttm,
        r.questionnaire_dt, r.createtime_dttm, r.prescoring_dt, r.scoring_dt) as timestamp))
        as original_effective_from_dttm_kk_dk,
    row_number() over (
        partition by r.questionnaire_id, r.status
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
    ) as rn,
    -- Изменение 1.1-B: поле источника, которое уже используется следующими ветками TQS.
    r.src_cd_src
from &p_db_rawd.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention r
where 1=1
  and coalesce(upper(r.first_nm), '#') not like any (array[&p_test_first_nm_like_text_list])
  and coalesce(upper(r.first_nm), '#') not in (&p_test_first_nm_in_text_list)
  and coalesce(upper(r.last_nm), '#') not in (&p_test_last_nm_in_text_list)
  and coalesce(upper(r.middle_nm), '#') not like &p_test_middle_nm_like_text_list
  and coalesce(r.questionnaire_dt, r.business_dt, r.createtime_dttm)
      similar to '20[0-9][0-9]-[0-2][0-9]-[0-3][0-9][ T][0-2][0-9]:[0-5][0-9]:[0-5][0-9]%'
  and coalesce(r.questionnaire_dt, r.business_dt, r.createtime_dttm) not like '%+%'
  and cast(coalesce(r.questionnaire_dt, r.business_dt, r.createtime_dttm) as timestamp)
      >= cast(&p_rds_report_dt_date as timestamp)
  -- Изменение 1.1-A: только условия двух кредитных веток исходного TQS.
  and ((r.src_cd_src like &p_quest_src_cd_kk_list or r.product_type_code in (&p_quest_product_kk_list))
       or ((r.src_cd_src like &p_quest_src_cd_kn_list or r.product_type_code in (&p_quest_product_kn_list))
           and r.src_cd_src not like &p_quest_src_cd_kk_list))
)
select
    p.questionnaire_id,
    p.application_num,
    p.utmcn,
    p.utmcmd,
    p.utmcsr,
    p.utmctr,
    p.utmcct,
    p.status,
    p.scoring_status_nm,
    p.prescoring_status_nm,
    p.product_type_code,
    p.program_type,
    p.src_cd,
    p.questionnaire_dttm,
    p.original_effective_from_dttm_auto_kn,
    p.original_effective_from_dttm_kk_dk,
    p.rn,
    p.src_cd_src
from pre p
where p.rn = 1
) distributed randomly;

-- Шаг 1.2. Ветка KK: продукт и статусы исходного TQS.
-- Откуда: раздел «Кредитные карты», строки 134–187 tech_questionnaire_status.
-- Зачем: присвоить level25_product_bp_nm тем же способом; далее продукт фильтруется по этому полю.
-- Копирование: можно полностью скопировать из tech_questionnaire_status; заменить только имена таблиц/макроимена.
drop table if exists &db_sbx.prt_if2_tqs_kk_questionnaire;
create table &db_sbx.prt_if2_tqs_kk_questionnaire
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    r.application_num,
    r.questionnaire_id,
    r.utmcn,
    r.utmcmd,
    r.utmcsr,
    r.utmctr,
    r.utmcct,
    r.status,
    r.scoring_status_nm,
    r.prescoring_status_nm,
    r.program_type,
    r.src_cd_src,
    r.questionnaire_dttm,
    r.product_type_code as product_type_cd,
    case
        when r.status in ('CANCELLED') then 'Отмена'
        when r.status in ('CHECKING') then 'На проверке'
        when r.status in ('CLIENT_DECLINE') then 'Отказ по инициативе клиента'
        when r.status in ('COURIER') then 'Курьер'
        when r.status in ('CREATED') then 'Создана'
        when r.status in ('DECLINE') then 'Отказ'
        when r.status in ('DELIVERY') then 'Доставка'
        when r.status in ('DONE') then 'Выдача'
        when r.status in ('DRAFT') then 'Черновик'
        when r.status in ('EXPIRED') then 'Просрочено'
        when r.status in ('FAILED') then 'Ошибка'
        when r.status in ('NEED_BKI') then 'Требуется проверка в БКИ'
        when r.status in ('NO_OFFER') then 'Нет предложения'
        when r.status in ('ONLY_SALE_POINT') then 'Выдача только в ТП'
        when r.status in ('SALE_POINT') then 'Необходим визит в ТП'
        when r.status in ('SCORING') then 'В процессе скоринга'
        when r.status in ('SELECT_CARD') then 'Выбор карты'
        else r.status end as status_name,
    cast(&p_quest_25lvl_product_kk_list as text) as level25_product_bp_nm,
    r.original_effective_from_dttm_kk_dk as effective_from_dttm
from &db_sbx.prt_if2_tqs_questionnaire r
where 1=1
  and (r.src_cd_src like &p_quest_src_cd_kk_list or r.product_type_code in (&p_quest_product_kk_list))
  and length(r.questionnaire_id) not in (&p_quest_not_len_id_kk_list)
) distributed randomly;

-- Шаг 1.3. Ветка KN: продукт и статусы исходного TQS.
-- Откуда: раздел «Кредит наличными», строки 190–299 tech_questionnaire_status.
-- Зачем: присвоить level25_product_bp_nm тем же способом; далее продукт фильтруется по этому полю.
-- Копирование: можно полностью скопировать из tech_questionnaire_status; заменить только имена таблиц/макроимена.
drop table if exists &db_sbx.prt_if2_tqs_kn_questionnaire;
create table &db_sbx.prt_if2_tqs_kn_questionnaire
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    r.application_num,
    r.questionnaire_id,
    r.utmcn,
    r.utmcmd,
    r.utmcsr,
    r.utmctr,
    r.utmcct,
    r.status,
    r.scoring_status_nm,
    r.prescoring_status_nm,
    r.program_type,
    r.src_cd_src,
    r.questionnaire_dttm,
    r.product_type_code as product_type_cd,
    case
        when r.status in ('0') then 'Создана'
        when r.status in ('71') then 'Ошибка на прескоринге'
        when r.status in ('72') then 'Ошибка на скоринге'
        when r.status in ('90', 'CLIENT_DECLINE') then 'Закрыта'
        when r.status in ('CHECK_LIST_EMPTY', 'CHECK_LIST_UNDERWRITING', 'CHECK_LIST_ANTIFRAUD_OR_PRODUCT') then 'Одобрено'
        when r.status in ('HARD_DECLINE') then 'Жесткий отказ'
        when r.status in ('SOFT_DECLINE') then 'Не мораторный отказ'
        when r.status in ('SHORT_FORM') then 'Предварительно одобрено (call0)'
        when r.status in ('DONE') then 'Кредит выдан'
        when r.status in ('SCORING') then 'В процессе скоринга'
        when r.status in ('CONFIGURATION') then 'Подбор продукта'
        when r.status in ('ANTIFRAUD') then 'Антифрод'
        when r.status in ('CHOICE_CONFIRMATION') then 'Выбор способа подтверждения'
        when r.status in ('DATA_CORRECTION') then 'Корректировка данных'
        when r.status in ('DATA_CORRECTION_WAITING') then 'Корректировка данных (ожидание)'
        when r.status in ('FINAL_SCAN') then 'Сканирование документов'
        when r.status in ('FULL_FORM') then 'Полная заявка'
        when r.status in ('PRODUCT_ISSUE') then 'Формирование КОД'
        when r.status in ('UNDERWRITING') then 'Андеррайтинг'
        when r.status in ('TECHNICAL_DECLINE') then 'Отказ по техническим причинам'
        when r.status in ('IDENTIFICATION') then 'Идентификация'
        when r.status in ('CLARIFICATION') then 'Уточнение'
        when r.status in ('UNKNOWN-ERROR') then 'Неизвестная ошибка'
        when r.status is null then 'Не определено'
        else r.status end as status_name,
    cast(&p_quest_25lvl_product_kn_list as text) as level25_product_bp_nm,
    case r.status
        when 'создана' then 1
        when 'идентификация' then 2
        when 'полная заявка' then 3
        when 'корректировка данных (ожидание)' then 4
        when 'корректировка данных' then 5
        when 'подбор продукта' then 6
        when 'в процессе скоринга' then 7
        when 'предварительно одобрено (call0)' then 8
        when 'ошибка на прескоринге' then 9
        when 'неизвестная ошибка' then 10
        when 'ошибка на скоринге' then 11
        when 'жесткий отказ' then 12
        when 'не мораторный отказ' then 13
        when 'отказ по техническим причинам' then 14
        when 'одобрено' then 15
        when 'закрыта' then 16
        when '1' then 17
        when '10.0' then 18
        when '2.0' then 19
        when '3.0' then 20
        when '4.0' then 21
        when '9.0' then 22
        when '0' then 23
        when 'IDENTIFICATION' then 24
        when 'CHOICE_CONFIRMATION' then 25
        when 'FULL_FORM' then 26
        when 'DATA_CORRECTION' then 27
        when 'DATA_CORRECTION_WAITING' then 28
        when 'CONFIGURATION' then 29
        when 'SCORING' then 30
        when 'SHORT_FORM' then 31
        when '71' then 32
        when '72' then 33
        when 'CLARIFICATION' then 34
        when 'UNDERWRITING' then 35
        when 'HARD_DECLINE' then 36
        when 'SOFT_DECLINE' then 37
        when 'TECHNICAL_DECLINE' then 38
        when 'CHECK_LIST_ANTIFRAUD_OR_PRODUCT' then 39
        when 'CHECK_LIST_UNDERWRITING' then 40
        when 'CHECK_LIST_EMPTY' then 41
        when 'DECISION_EXPIRED' then 42
        when 'PRODUCT_ISSUE' then 43
        when 'DONE' then 44
        when 'UNKNOWN-ERROR' then 45
        when '90' then 46
        when 'CLIENT_DECLINE' then 47
        else null end as status_priority,
    r.original_effective_from_dttm_auto_kn as original_effective_from_dttm
from &db_sbx.prt_if2_tqs_questionnaire r
where 1=1
  and (r.src_cd_src like &p_quest_src_cd_kn_list or r.product_type_code in (&p_quest_product_kn_list))
  and r.src_cd_src not like &p_quest_src_cd_kk_list
) distributed randomly;

-- Шаг 1.4. Сдвиг совпадающих времён статусов только КН.
-- Откуда: prt_tqs_kn_auto_dk_questionnaire, строки 659–787 tech_questionnaire_status.
-- Зачем: сохранить исходное построение effective_from_dttm, не добавляя отдельные проверки.
-- Копирование: скопировать исходный шаг; оставить только КН и пронести application_num через оба SELECT.
drop table if exists &db_sbx.prt_if2_tqs_kn_timeline;
create table &db_sbx.prt_if2_tqs_kn_timeline
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
with kn_pre_eff_calc as (
select
    application_num,
    questionnaire_id,
    utmcn,
    utmcmd,
    utmcsr,
    utmctr,
    utmcct,
    status,
    scoring_status_nm,
    prescoring_status_nm,
    program_type,
    src_cd_src,
    questionnaire_dttm,
    product_type_cd,
    status_name,
    level25_product_bp_nm,
    status_priority,
    original_effective_from_dttm,
    coalesce(extract(seconds from (original_effective_from_dttm -
        lag(original_effective_from_dttm) over (partition by questionnaire_id
            order by original_effective_from_dttm, status_priority))), 1) as diff_sec,
    count(*) over (partition by questionnaire_id, original_effective_from_dttm
        order by status_priority) as count_eq_ef,
    count(*) over (partition by questionnaire_id, original_effective_from_dttm) as count_eq_ef_not_ordered
from &db_sbx.prt_if2_tqs_kn_questionnaire
)
select
    application_num,
    questionnaire_id,
    utmcn,
    utmcmd,
    utmcsr,
    utmctr,
    utmcct,
    status,
    scoring_status_nm,
    prescoring_status_nm,
    program_type,
    src_cd_src,
    questionnaire_dttm,
    product_type_cd,
    status_name,
    level25_product_bp_nm,
    case when diff_sec = 0
         then original_effective_from_dttm + (count_eq_ef - 1) * interval '1 second'
         when diff_sec > 0
          and coalesce(lag(count_eq_ef_not_ordered) over (partition by questionnaire_id
                       order by original_effective_from_dttm, status_priority), 0) >= diff_sec
         then original_effective_from_dttm +
              (lag(count_eq_ef_not_ordered) over (partition by questionnaire_id
               order by original_effective_from_dttm, status_priority) - diff_sec) * interval '1 second'
         else original_effective_from_dttm end as effective_from_dttm
from kn_pre_eff_calc
) distributed randomly;

-- Шаг 1.5. Общий поток КН/КК с application_num.
-- Откуда: prt_tqs_questionnaire_all, строки 789–840 tech_questionnaire_status.
-- Зачем: получить исходный состав TQS после переименований UTM/status/src и сохранить номер заявки.
-- Копирование: скопировать UNION КК/КН; убрать остальные продукты, добавить application_num в оба плеча.
drop table if exists &db_sbx.prt_if2_tqs_questionnaire_all;
create table &db_sbx.prt_if2_tqs_questionnaire_all
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    kk.questionnaire_id,
    kk.questionnaire_dttm,
    kk.utmcn as utmcn_info,
    kk.utmcmd as utmcmd_info,
    kk.utmcsr as utmcsr_info,
    kk.utmctr as utmctr_info,
    kk.utmcct as utmcct_info,
    kk.status as status_cd,
    kk.scoring_status_nm,
    kk.prescoring_status_nm,
    kk.product_type_cd,
    kk.status_name,
    kk.program_type,
    kk.src_cd_src as src_cd,
    kk.level25_product_bp_nm,
    kk.effective_from_dttm,
    kk.application_num
from &db_sbx.prt_if2_tqs_kk_questionnaire kk
union all
select
    kn.questionnaire_id,
    kn.questionnaire_dttm,
    kn.utmcn as utmcn_info,
    kn.utmcmd as utmcmd_info,
    kn.utmcsr as utmcsr_info,
    kn.utmctr as utmctr_info,
    kn.utmcct as utmcct_info,
    kn.status as status_cd,
    kn.scoring_status_nm,
    kn.prescoring_status_nm,
    kn.product_type_cd,
    kn.status_name,
    kn.program_type,
    kn.src_cd_src as src_cd,
    kn.level25_product_bp_nm,
    kn.effective_from_dttm,
    kn.application_num
from &db_sbx.prt_if2_tqs_kn_timeline kn
) distributed randomly;

-- Шаг 1.6. Получение RK и интервалов TQS для КН/КК.
-- Откуда: финальная сборка prot_tech_questionnaire_status, строки 843–884 исходного TQS.
-- Зачем: подтянуть настоящий RK из существующей связи с клиентом и сохранить все атрибуты TQS плюс номер.
-- Копирование: скопировать исходный INNER JOIN/LEAD; добавить base.application_num и момент загрузки в SELECT.
drop table if exists &db_sbx.prt_if2_tech_questionnaire_status;
create table &db_sbx.prt_if2_tech_questionnaire_status
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    cast(tqx.questionnaire_rk as bigint) as questionnaire_rk,
    base.questionnaire_id,
    base.questionnaire_dttm,
    base.utmcn_info,
    base.utmcmd_info,
    base.utmcsr_info,
    base.utmctr_info,
    base.utmcct_info,
    base.status_cd,
    base.scoring_status_nm,
    base.prescoring_status_nm,
    base.product_type_cd,
    base.status_name,
    base.program_type,
    base.src_cd,
    base.level25_product_bp_nm,
    base.effective_from_dttm,
    base.application_num,
    cast(lead(base.effective_from_dttm, 1, cast(&p_max_date as timestamp)) over (
        partition by tqx.questionnaire_rk order by base.effective_from_dttm
    ) as timestamp) as effective_to_dttm,
    cast(&p_report_timestamp as timestamp) as processed_dttm
from &db_sbx.prt_if2_tqs_questionnaire_all base
inner join (
    select questionnaire_id, questionnaire_rk
    from &p_db_cdmr.tech_questionnaire_x_customer
    where effective_to_dttm = cast(&p_max_date as timestamp)
    group by 1, 2
) tqx on tqx.questionnaire_id = base.questionnaire_id
) distributed randomly;

-- Шаг 1.7. Флаг верификации КН/КК по всей истории TQS.
-- Откуда: новый шаг; MAX(CASE) взят из стиля флагов tech_application_status, статусы — из выделений Excel.
-- Зачем: найти когда-либо пройденную верификацию и передать флаг вместе с каждым application_num дальше.
-- Копирование: это добавляемый шаг, целиком из TQS его скопировать нельзя.
drop table if exists &db_sbx.prt_if2_kn_kk_verification;
create table &db_sbx.prt_if2_kn_kk_verification
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
with verification as (
select
    questionnaire_rk,
    level25_product_bp_nm,
    max(case
        when level25_product_bp_nm = cast(&p_quest_25lvl_product_kn_list as text)
         and status_cd in (&p_kn_verification_status) then 1
        when level25_product_bp_nm = cast(&p_quest_25lvl_product_kk_list as text)
         and status_cd in (&p_kk_verification_status) then 1
        else 0 end) as quest_verification_flg
from &db_sbx.prt_if2_tech_questionnaire_status
group by 1, 2
)
select
    q.questionnaire_rk,
    q.questionnaire_id,
    q.questionnaire_dttm,
    q.utmcn_info,
    q.utmcmd_info,
    q.utmcsr_info,
    q.utmctr_info,
    q.utmcct_info,
    q.status_cd,
    q.scoring_status_nm,
    q.prescoring_status_nm,
    q.product_type_cd,
    q.status_name,
    q.program_type,
    q.src_cd,
    q.level25_product_bp_nm,
    q.effective_from_dttm,
    q.application_num,
    q.effective_to_dttm,
    q.processed_dttm,
    cast(v.quest_verification_flg as boolean) as quest_verification_flg
from &db_sbx.prt_if2_tech_questionnaire_status q
inner join verification v
    on v.questionnaire_rk = q.questionnaire_rk
   and v.level25_product_bp_nm = q.level25_product_bp_nm
) distributed randomly;

-- Шаг 1.8. Последний шаг анкет -> BDM по application_num.
-- Откуда: новый шаг по ранее описанной связке и примеру соединения с bdm.application.
-- Зачем: использовать все номера истории после вычисления флага; не повторять один номер на каждом статусе.
-- Копирование: можно взять показанный JOIN анкет с BDM; LEFT JOIN сохраняет анкету без найденной заявки.
drop table if exists &db_sbx.prt_if2_kn_kk_bdm;
create table &db_sbx.prt_if2_kn_kk_bdm
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select distinct
    q.questionnaire_id,
    q.questionnaire_rk,
    q.questionnaire_dttm,
    q.quest_verification_flg,
    q.level25_product_bp_nm,
    q.application_num,
    app.application_rk as bdm_application_rk,
    app.src_cd as bdm_src_cd
from &db_sbx.prt_if2_kn_kk_verification q
left join &p_db_bdm.application app
    on q.application_num = app.application_num
   and app.effective_to_date = cast(&p_max_date as date)
   and app.application_begin_date >= cast(&P_BEGIN_DATE as date)
   and app.application_rk is not null and app.application_rk <> -1
   and (app.src_cd = &P_UZ_SRC
        or (q.level25_product_bp_nm = cast(&p_quest_25lvl_product_kn_list as text) and app.src_cd = &P_KN_SRC)
        or (q.level25_product_bp_nm = cast(&p_quest_25lvl_product_kk_list as text) and app.src_cd in (&P_KK_SRC)))
where q.questionnaire_dttm >= cast(&P_BEGIN_DATE as timestamp)
   or q.questionnaire_dttm is null
) distributed randomly;

-- Шаг 1.9. Новый источник: готовая TAS КН/КК и УЗ.
-- Откуда: tech_application_status из предоставленного DDL; её флаги уже рассчитаны исходным прототипом.
-- Зачем: выбрать атрибуты второй стороны, в том числе заявки без анкеты и УЗ без дочерней заявки.
-- Копирование: новая выборка готовой TAS, её исходный ETL целиком копировать не требуется.
drop table if exists &db_sbx.prt_if2_kn_kk_tas;
create table &db_sbx.prt_if2_kn_kk_tas
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select distinct
    nullif(t.parent_application_rk, -1) as parent_application_rk,
    t.parent_application_id,
    t.parent_application_dt,
    t.parent_src_cd,
    t.parent_approved_dttm,
    cast(t.parent_open_flg as boolean) as parent_open_flg,
    cast(t.parent_prescoring_flg as boolean) as parent_prescoring_flg,
    cast(t.parent_at_work_flg as boolean) as parent_at_work_flg,
    cast(t.parent_approved_flg as boolean) as parent_approved_flg,
    nullif(t.application_rk, -1) as application_rk,
    t.application_id,
    t.application_dt,
    t.src_cd,
    t.application_type_cd,
    t.deal_issue_date,
    cast(t.create_flg as boolean) as create_flg,
    cast(t.at_work_flg as boolean) as at_work_flg,
    cast(t.final_approved_flg as boolean) as final_approved_flg,
    cast(t.agr_signed_flg as boolean) as agr_signed_flg,
    t.level25_product_bp_nm,
    t.level35_product_bp_nm,
    t.processed_dttm
from &p_db_cdmr.tech_application_status t
where (t.src_cd in (&P_KN_SRC, &P_KK_SRC, &P_UZ_SRC)
       or (t.src_cd is null and t.parent_src_cd = &P_UZ_SRC))
  and (coalesce(t.application_dt, t.parent_application_dt) >= cast(&P_BEGIN_DATE as date)
       or coalesce(t.application_dt, t.parent_application_dt) is null)
) distributed randomly;

-- Шаг 1.10. Соединение с TAS по ключу, полученному через BDM.
-- Откуда: новый шаг по требованиям: прямой RK продуктовой заявки либо RK универсальной заявки.
-- Зачем: получить связанные пары; один и тот же результат разных номеров/путей оставить один раз.
-- Копирование: новый JOIN; режим DIRECT/UZ/ALL задаёт уже исследуемый способ связи.
drop table if exists &db_sbx.prt_if2_kn_kk_matches;
create table &db_sbx.prt_if2_kn_kk_matches
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select distinct
    q.questionnaire_id as q_questionnaire_id,
    q.questionnaire_rk as q_questionnaire_rk,
    q.questionnaire_dttm as q_questionnaire_dttm,
    q.quest_verification_flg as q_quest_verification_flg,
    q.level25_product_bp_nm as q_level25_product_bp_nm,
    t.parent_application_rk as tas_parent_application_rk,
    t.parent_application_id as tas_parent_application_id,
    t.parent_application_dt as tas_parent_application_dt,
    t.parent_src_cd as tas_parent_src_cd,
    t.parent_approved_dttm as tas_parent_approved_dttm,
    t.parent_open_flg as tas_parent_open_flg,
    t.parent_prescoring_flg as tas_parent_prescoring_flg,
    t.parent_at_work_flg as tas_parent_at_work_flg,
    t.parent_approved_flg as tas_parent_approved_flg,
    t.application_rk as tas_application_rk,
    t.application_id as tas_application_id,
    t.application_dt as tas_application_dt,
    t.src_cd as tas_src_cd,
    t.application_type_cd as tas_application_type_cd,
    t.deal_issue_date as tas_deal_issue_date,
    t.create_flg as tas_create_flg,
    t.at_work_flg as tas_at_work_flg,
    t.final_approved_flg as tas_final_approved_flg,
    t.agr_signed_flg as tas_agr_signed_flg,
    t.level25_product_bp_nm as tas_level25_product_bp_nm,
    t.level35_product_bp_nm as tas_level35_product_bp_nm,
    t.processed_dttm as tas_processed_dttm
from &db_sbx.prt_if2_kn_kk_bdm q
inner join &db_sbx.prt_if2_kn_kk_tas t
    on (cast(&p_kn_kk_link_mode as text) in ('ALL', 'DIRECT')
        and q.bdm_src_cd <> &P_UZ_SRC
        and t.application_rk = q.bdm_application_rk and t.src_cd = q.bdm_src_cd)
    or (cast(&p_kn_kk_link_mode as text) in ('ALL', 'UZ')
        and q.bdm_src_cd = &P_UZ_SRC
        and ((t.parent_application_rk = q.bdm_application_rk and t.parent_src_cd = &P_UZ_SRC
              and ((q.level25_product_bp_nm = cast(&p_quest_25lvl_product_kn_list as text) and t.src_cd = &P_KN_SRC)
                   or (q.level25_product_bp_nm = cast(&p_quest_25lvl_product_kk_list as text) and t.src_cd in (&P_KK_SRC))
                   or t.src_cd is null))
             or (t.application_rk = q.bdm_application_rk and t.src_cd = &P_UZ_SRC)))
) distributed randomly;

-- Шаг 1.11. Итог ветки КН/КК: пары и обе стороны без пары.
-- Откуда: новый шаг из требования сохранить анкеты и заявки, даже если связка не найдена.
-- Зачем: одна анкета без связи выводится один раз, а не по числу её исторических номеров.
-- Копирование: новая сборка: связанные пары + NOT EXISTS для каждой несвязанной стороны.
drop table if exists &db_sbx.prt_if2_kn_kk_fin;
create table &db_sbx.prt_if2_kn_kk_fin
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select distinct
    cast(m.q_questionnaire_rk as bigint) as questionnaire_rk,
    cast(m.q_questionnaire_dttm as timestamp) as questionnaire_dttm,
    cast(m.q_quest_verification_flg as boolean) as quest_verification_flg,
    cast(m.tas_parent_application_rk as bigint) as parent_application_rk,
    cast(m.tas_parent_application_dt as date) as parent_application_dt,
    cast(m.tas_parent_open_flg as boolean) as parent_open_flg,
    cast(m.tas_parent_prescoring_flg as boolean) as parent_prescoring_flg,
    cast(m.tas_parent_at_work_flg as boolean) as parent_at_work_flg,
    cast(m.tas_parent_approved_flg as boolean) as parent_approved_flg,
    cast(m.tas_application_rk as bigint) as application_rk,
    cast(m.tas_application_dt as date) as application_dt,
    cast(m.tas_deal_issue_date as date) as deal_issue_date,
    cast(m.tas_create_flg as boolean) as create_flg,
    cast(m.tas_at_work_flg as boolean) as at_work_flg,
    cast(m.tas_final_approved_flg as boolean) as final_approved_flg,
    cast(m.tas_agr_signed_flg as boolean) as agr_signed_flg,
    cast(coalesce(m.tas_level25_product_bp_nm, m.q_level25_product_bp_nm) as text) as level25_product_bp_nm,
    cast(coalesce(m.tas_level25_product_bp_nm, m.q_level25_product_bp_nm) as text) as level35_product_bp_nm,
    cast(&p_report_timestamp as timestamp(0)) as processed_dttm
from &db_sbx.prt_if2_kn_kk_matches m
union all
select distinct
    cast(q.questionnaire_rk as bigint) as questionnaire_rk,
    cast(q.questionnaire_dttm as timestamp) as questionnaire_dttm,
    cast(q.quest_verification_flg as boolean) as quest_verification_flg,
    cast(null as bigint) as parent_application_rk,
    cast(null as date) as parent_application_dt,
    cast(null as boolean) as parent_open_flg,
    cast(null as boolean) as parent_prescoring_flg,
    cast(null as boolean) as parent_at_work_flg,
    cast(null as boolean) as parent_approved_flg,
    cast(null as bigint) as application_rk,
    cast(null as date) as application_dt,
    cast(null as date) as deal_issue_date,
    cast(null as boolean) as create_flg,
    cast(null as boolean) as at_work_flg,
    cast(null as boolean) as final_approved_flg,
    cast(null as boolean) as agr_signed_flg,
    cast(coalesce(null, q.level25_product_bp_nm) as text) as level25_product_bp_nm,
    cast(coalesce(null, q.level25_product_bp_nm) as text) as level35_product_bp_nm,
    cast(&p_report_timestamp as timestamp(0)) as processed_dttm
from &db_sbx.prt_if2_kn_kk_bdm q
where not exists (
    select 1 from &db_sbx.prt_if2_kn_kk_matches m
    where m.q_questionnaire_rk = q.questionnaire_rk
      and m.q_questionnaire_id = q.questionnaire_id
      and m.q_level25_product_bp_nm = q.level25_product_bp_nm
)
union all
select distinct
    cast(null as bigint) as questionnaire_rk,
    cast(null as timestamp) as questionnaire_dttm,
    cast(null as boolean) as quest_verification_flg,
    cast(t.parent_application_rk as bigint) as parent_application_rk,
    cast(t.parent_application_dt as date) as parent_application_dt,
    cast(t.parent_open_flg as boolean) as parent_open_flg,
    cast(t.parent_prescoring_flg as boolean) as parent_prescoring_flg,
    cast(t.parent_at_work_flg as boolean) as parent_at_work_flg,
    cast(t.parent_approved_flg as boolean) as parent_approved_flg,
    cast(t.application_rk as bigint) as application_rk,
    cast(t.application_dt as date) as application_dt,
    cast(t.deal_issue_date as date) as deal_issue_date,
    cast(t.create_flg as boolean) as create_flg,
    cast(t.at_work_flg as boolean) as at_work_flg,
    cast(t.final_approved_flg as boolean) as final_approved_flg,
    cast(t.agr_signed_flg as boolean) as agr_signed_flg,
    cast(coalesce(t.level25_product_bp_nm, null) as text) as level25_product_bp_nm,
    cast(coalesce(t.level25_product_bp_nm, null) as text) as level35_product_bp_nm,
    cast(&p_report_timestamp as timestamp(0)) as processed_dttm
from &db_sbx.prt_if2_kn_kk_tas t
where not exists (
    select 1 from &db_sbx.prt_if2_kn_kk_matches m
    where m.tas_parent_application_rk is not distinct from t.parent_application_rk
      and m.tas_parent_src_cd is not distinct from t.parent_src_cd
      and m.tas_application_rk is not distinct from t.application_rk
      and m.tas_src_cd is not distinct from t.src_cd
)
) distributed randomly;

-- ==================== 2. АВТО: ГОТОВАЯ TQS -> ФЛАГ -> TAS ====================

-- Шаг 2.1. Готовая TQS авто и флаг верификации по истории.
-- Откуда: tech_questionnaire_status напрямую; MAX(CASE) — стиль флагов tech_application_status.
-- Зачем: не копировать RAW-цепочку авто; учесть любой выделенный статус, а не только текущую версию.
-- Копирование: новая агрегация готовой TQS; имена status_cd/RK/даты/продукта — из её DDL.
drop table if exists &db_sbx.prt_if2_auto_verification;
create table &db_sbx.prt_if2_auto_verification
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    q.questionnaire_id,
    q.questionnaire_rk,
    min(q.questionnaire_dttm) as questionnaire_dttm,
    cast(max(case when q.status_cd in (&p_auto_verification_status) then 1 else 0 end) as boolean)
        as quest_verification_flg,
    q.level25_product_bp_nm
from &p_db_cdmr.tech_questionnaire_status q
where q.level25_product_bp_nm = cast(&p_quest_25lvl_product_auto_list as text)
group by q.questionnaire_id, q.questionnaire_rk, q.level25_product_bp_nm
having min(q.questionnaire_dttm) >= cast(&P_BEGIN_DATE as timestamp)
    or min(q.questionnaire_dttm) is null
) distributed randomly;

-- Шаг 2.2. Готовая TAS автокредитов.
-- Откуда: tech_application_status, источник автокредитов из исходных макропеременных TAS.
-- Зачем: взять заявочные атрибуты и сохранить авто-заявки без анкеты.
-- Копирование: можно скопировать выборку 1.9, заменив условие источника на P_AUTO_SRC.
drop table if exists &db_sbx.prt_if2_auto_tas;
create table &db_sbx.prt_if2_auto_tas
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select distinct
    nullif(t.parent_application_rk, -1) as parent_application_rk,
    t.parent_application_id,
    t.parent_application_dt,
    t.parent_src_cd,
    t.parent_approved_dttm,
    cast(t.parent_open_flg as boolean) as parent_open_flg,
    cast(t.parent_prescoring_flg as boolean) as parent_prescoring_flg,
    cast(t.parent_at_work_flg as boolean) as parent_at_work_flg,
    cast(t.parent_approved_flg as boolean) as parent_approved_flg,
    nullif(t.application_rk, -1) as application_rk,
    t.application_id,
    t.application_dt,
    t.src_cd,
    t.application_type_cd,
    t.deal_issue_date,
    cast(t.create_flg as boolean) as create_flg,
    cast(t.at_work_flg as boolean) as at_work_flg,
    cast(t.final_approved_flg as boolean) as final_approved_flg,
    cast(t.agr_signed_flg as boolean) as agr_signed_flg,
    t.level25_product_bp_nm,
    t.level35_product_bp_nm,
    t.processed_dttm
from &p_db_cdmr.tech_application_status t
where t.src_cd = &P_AUTO_SRC
  and (coalesce(t.application_dt, t.parent_application_dt) >= cast(&P_BEGIN_DATE as date)
       or coalesce(t.application_dt, t.parent_application_dt) is null)
) distributed randomly;

-- Шаг 2.3. Связь авто по questionnaire_id = application_id.
-- Откуда: прямое равенство ID из требований, флаги и даты заявки — из готовой TAS.
-- Зачем: сохранить связанные пары, анкеты без заявки и заявки без анкеты через FULL JOIN.
-- Копирование: новый FULL JOIN двух последних шагов авто; исходные RK не генерируются.
drop table if exists &db_sbx.prt_if2_auto_fin;
create table &db_sbx.prt_if2_auto_fin
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select distinct
    cast(q.questionnaire_rk as bigint) as questionnaire_rk,
    cast(q.questionnaire_dttm as timestamp) as questionnaire_dttm,
    cast(q.quest_verification_flg as boolean) as quest_verification_flg,
    cast(t.parent_application_rk as bigint) as parent_application_rk,
    cast(t.parent_application_dt as date) as parent_application_dt,
    cast(t.parent_open_flg as boolean) as parent_open_flg,
    cast(t.parent_prescoring_flg as boolean) as parent_prescoring_flg,
    cast(t.parent_at_work_flg as boolean) as parent_at_work_flg,
    cast(t.parent_approved_flg as boolean) as parent_approved_flg,
    cast(t.application_rk as bigint) as application_rk,
    cast(t.application_dt as date) as application_dt,
    cast(t.deal_issue_date as date) as deal_issue_date,
    cast(t.create_flg as boolean) as create_flg,
    cast(t.at_work_flg as boolean) as at_work_flg,
    cast(t.final_approved_flg as boolean) as final_approved_flg,
    cast(t.agr_signed_flg as boolean) as agr_signed_flg,
    cast(coalesce(t.level25_product_bp_nm, q.level25_product_bp_nm) as text) as level25_product_bp_nm,
    cast(coalesce(t.level25_product_bp_nm, q.level25_product_bp_nm) as text) as level35_product_bp_nm,
    cast(&p_report_timestamp as timestamp(0)) as processed_dttm
from &db_sbx.prt_if2_auto_verification q
full join &db_sbx.prt_if2_auto_tas t
    on q.questionnaire_id = t.application_id
) distributed randomly;

-- ==================== 3. ОБЪЕДИНЕНИЕ ДВУХ ВЕТОК ====================

-- Шаг 3.1. Единая витрина из 19 согласованных атрибутов.
-- Откуда: два итоговых шага КН/КК и авто; атрибутивный состав — из функциональных требований.
-- Зачем: объединить ветки в одном формате; оба уровня продукта рассчитаны одинаково.
-- Копирование: новый UNION ALL; прежний прототип и его результаты этим SQL не затрагиваются.
drop table if exists &db_sbx.prt_if2_tech_internet_funnel;
create table &db_sbx.prt_if2_tech_internet_funnel
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    k.questionnaire_rk,
    k.questionnaire_dttm,
    k.quest_verification_flg,
    k.parent_application_rk,
    k.parent_application_dt,
    k.parent_open_flg,
    k.parent_prescoring_flg,
    k.parent_at_work_flg,
    k.parent_approved_flg,
    k.application_rk,
    k.application_dt,
    k.deal_issue_date,
    k.create_flg,
    k.at_work_flg,
    k.final_approved_flg,
    k.agr_signed_flg,
    k.level25_product_bp_nm,
    k.level35_product_bp_nm,
    k.processed_dttm
from &db_sbx.prt_if2_kn_kk_fin k
union all
select
    a.questionnaire_rk,
    a.questionnaire_dttm,
    a.quest_verification_flg,
    a.parent_application_rk,
    a.parent_application_dt,
    a.parent_open_flg,
    a.parent_prescoring_flg,
    a.parent_at_work_flg,
    a.parent_approved_flg,
    a.application_rk,
    a.application_dt,
    a.deal_issue_date,
    a.create_flg,
    a.at_work_flg,
    a.final_approved_flg,
    a.agr_signed_flg,
    a.level25_product_bp_nm,
    a.level35_product_bp_nm,
    a.processed_dttm
from &db_sbx.prt_if2_auto_fin a
) distributed randomly;

-- Шаг 3.2. Оценка связки на итоговой базе: read-only отчёт, не шаг очистки.
-- Откуда: ранее заданный ориентир >=10%; версия DIRECT/UZ выбирается макропеременной.
-- Зачем: считать уникальные RK, не увеличивая покрытие за счёт повторов статусов/номеров.
-- Примечание: заявки считаются по паре parent_application_rk/application_rk;
-- строки без обоих RK не входят в знаменатель заявок. Источники TAS в этой схеме имеют общие BDM RK.
select
    count(distinct questionnaire_rk) as questionnaire_count,
    count(distinct case when parent_application_rk is not null or application_rk is not null
                        then questionnaire_rk end) as linked_questionnaire_count,
    round(100.0 * count(distinct case when parent_application_rk is not null or application_rk is not null
                                     then questionnaire_rk end)
        / nullif(count(distinct questionnaire_rk), 0), 2) as questionnaire_link_pct,
    count(distinct case when parent_application_rk is not null or application_rk is not null
                        then row(parent_application_rk, application_rk) end) as application_count,
    count(distinct case when questionnaire_rk is not null
                         and (parent_application_rk is not null or application_rk is not null)
                        then row(parent_application_rk, application_rk) end) as linked_application_count
from &db_sbx.prt_if2_tech_internet_funnel;
