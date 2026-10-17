/*
ЕДИНЫЙ СКРИПТ. Greenplum. Выполнять последовательно с остановкой на ошибке.
Порядок: 1 — очистка RAW и верификация анкеты; 2 — КН/КК; 3 — авто; 4 — итог и контроли.
Итог: &db_sbx.prt_tech_questionnaire_application_status.

0.1. Макропеременные (значения подставляет ETL/SQL-клиент перед запуском):

  &db_sbx                    - схема результатов и технических витрин;
                               по умолчанию: sbx_pre_orb_fd
  &p_db_bdm                  - схема BDM; по умолчанию: bdm
  &p_db_rawd                 - схема RAW; по умолчанию: rd_raw_orb
  &p_rds_report_dt_date      - нижняя граница выборки RAW из исходного ETL;
                               по умолчанию: '2024-10-01'
  &p_min_dttm                - замена NULL в приоритетах дат;
                               по умолчанию: '1900-01-01 00:00:00'

  &p_test_first_nm_like_text_list - шаблоны тестовых имён; по умолчанию:
                               '%ТЕСТ%', '%ТКЕСТ%', '%ТКЕКСТ%', '%ТЕМСТ%',
                               '%ЛИПОВЫЙ%', '%ЗАЯВК%', 'ПЕНСИОНН%', 'МУЛЬТИКАРТ%',
                               'АРХАНГЕЛЬСК%', 'ЗВОНИТЬ%', 'AAA%'
  &p_test_first_nm_in_text_list - тестовые имена IN; по умолчанию:
                               'ПЕНСЫ', 'ЛИД', 'НОВОКУЗНЕЦК', 'ТЕСТ', 'ЛЕХА',
                               'ДЯДЯ', 'ПРОЛД', 'АРОПР', 'ООО'
  &p_test_last_nm_in_text_list - тестовые фамилии; по умолчанию: 'ТЕСТ'
  &p_test_middle_nm_like_text_list - шаблон отчества; по умолчанию: 'ТЕСТОВНА'

  &p_quest_product_kn_list    - коды продукта RAW для КН; по умолчанию:
                               'cm.LiabilityType.Loan', 'RF', 'KN'
  &p_quest_product_kk_list    - коды продукта RAW для КК; по умолчанию:
                               'cm.LiabilityType.CreditCard', 'CreditCard',
                               'cm.LiabilityType.CreditCard cm.LiabilityType.Loan'
  &p_quest_product_ak_list    - коды продукта RAW для авто; по умолчанию:
                               'AutoCredit', 'AutoCreditR', 'AutoLoan',
                               'cm.LoanApplicationTy', 'cm.LoanApplicationType.Standar',
                               'cm.LoanApplicationType.Standard'
  &p_quest_not_len_id_kk_list - длины партнёрских ID КК, исключаемых по прототипу;
                               по умолчанию: 6
  &P_BEGIN_DATE              - начало периода; по умолчанию: '2025-01-01'
  &p_max_date                - максимальная дата; по умолчанию: '2999-12-31'
  &p_report_timestamp        - момент начала ETL, ОДНО значение на весь запуск;
                               пример: '2026-10-16 00:00:00'
  &p_min_coverage_pct        - ориентир покрытия в процентах; по умолчанию: 10.0
  &p_kn_kk_link_mode         - режим связей КН/КК; по умолчанию: 'ALL';
                               допустимые значения: 'ALL', 'DIRECT', 'UZ'
  &p_bdm_limit_by_begin_date - ограничивать BDM началом периода;
                               по умолчанию: true; для отключения: false

  &p_prod_kn_name            - наименование продукта 25/35 уровня по бизнес-плану
                               для Потребкредитов; по умолчанию: 'Потребкредит'
  &p_prod_kk_name            - наименование продукта 25/35 уровня по бизнес-плану
                               для Кредитных карт; по умолчанию: 'Кредитные карты'
  &p_prod_auto_name          - наименование продукта 25/35 уровня по бизнес-плану
                               для Автокредитов; по умолчанию: 'Автокредит'

  &p_kn_verification_status  - статусы пройденной верификации Потребкредита;
                               по умолчанию: '0', '10.0', 'одобрено', 'CHECK_LIST_EMPTY',
                               'CHECK_LIST_ANTIFRAUD_OR_PRODUCT'
  &p_kk_verification_status  - статусы пройденной верификации Кредитных карт;
                               по умолчанию: 'DONE', 'COURIER'
  &p_auto_verification_status - статусы пройденной верификации Автокредита;
                               по умолчанию: 'APPROVE_RKK', 'APPROVED', 'PRE_APPROVED',
                               'APPROVE_CALL2', 'APPROVE_CALL3', 'ORDER_CREATED',
                               'VERIFICATION', 'DRIVER_CARD_ISSUE',
                               'DRIVER_CARD_ISSUE_UPLOADED', 'DOSSIER_UPLOADED',
                               'DEAL_VER', 'CREDIT_ISSUED', 'PRODUCT_BASKET_SIGNED'

Это параметры макроподстановки, а не SQL-команды объявления переменных.
Имена схем подставляются БЕЗ кавычек; даты/время/строки — в одинарных кавычках;
числа и true/false — БЕЗ кавычек. Кавычки внутри SQL повторно не добавляются.
Списки статусов — SQL-строки через запятую, без внешних скобок;
в запросах используются как status_cd in (&p_kn_verification_status) и аналогично.
&p_report_timestamp задаётся фиксированным значением один раз перед запуском,
чтобы все шаги использовали тот же момент отчёта, как и раньше.

ПОДТВЕРЖДЁННОЕ ПРАВИЛО: любой выделенный зелёным/жёлтым статус означает,
что верификация была пройдена. Флаг — наличие такого статуса КОГДА-ЛИБО
в доступной истории до report_dttm. Цвет не участвует в расчёте.
Все 20 выделенных статусов со скриншотов — значения по умолчанию списков
макропеременных в блоке 0.1. Дополнительные статусы добавлять в эти списки.

ЦЕПОЧКА АНКЕТ:
  &p_db_rawd.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention
  -> RAW -> разбор дат -> причины отбраковки -> приоритеты
  -> prt_tqs_questionnaire (одна строка questionnaire_id/status, как в прототипе)
  -> продукт/status_name -> верификация по всей доступной истории
  -> prt_qas_questionnaire (представитель анкеты с ВСЕМИ application_num)
  -> ветка КН/КК через application_num -> BDM -> TAS; отдельно ветка авто.

Готовая tech_questionnaire_status и чужая man_prt_tqs_questionnaire НЕ читаются.
RAW не содержит level25_product_bp_nm: он восстанавливается по product_type_code.
Ни src_cd, ни src_cd_src не определяют продукт и не ограничивают выборку.
src_cd_src сохранён в последнем критерии исходного ORDER BY и как атрибут;
src_cd передаётся только как происхождение. Имена продуктов/статусы — макросы.
Поле из DDL называется level25_product_bp_nm (не level25_product_bd_nm).

Особенности восстановления прототипа:
  - Сохранены тестовые фильтры, COALESCE дат, MIN даты анкеты, оба исходных
    effective_from и полный видимый список приоритетов ROW_NUMBER.
  - NOT LIKE ANY в примере не исключает совпадение с одним из шаблонов.
    Для требуемого исключения ЛЮБОГО тестового шаблона используется NOT EXISTS.
  - Текстовые даты проверяются до CAST, включая календарный день и високосный год.
    Плохая обязательная дата идёт в отбраковку, плохая необязательная — в NULL.
  - NULL/пустые ID не склеиваются в одну анкету; флаг для них NULL.
  - Для КК сохранено исключение партнёрских ID длиной из макроса; NULL ID КК
    тоже не проходит исходное условие LENGTH(...) NOT IN (...).
  - Источниковые OR-условия по src_cd_src из продуктовых веток намеренно
    не перенесены: последнее требование — продукт определять без источника.
  - Код дальнейшего SCD/выбора текущего статуса показан не полностью. Здесь
    представитель — последний по createtime/processed/business, затем видимый
    приоритет русского статуса КН. Все статусы и номера остаются в истории/массиве.
    Это явное предположение; флаг и связи не ограничены номером представителя.
  - RK анкеты в RAW нет: он НЕ выдумывается. Ключ — questionnaire_id + продукт;
    q_entity_id — технический номер только в рамках одной пересборки.
  - TAS читается как актуальный снимок: если она версионная, добавить реальный
    фильтр в адаптеры 2.3 и 3.1. processed_dttm не заменяет актуальность.

КН/КК: по умолчанию ALL — объединение кандидатов прямого пути и путей УЗ,
с удалением повторов одной пары и сохранением списка путей/кардинальности.
Это исследовательский режим для выбора жизнеспособного способа. После
проверки отчёта 2.7 можно выбрать DIRECT или UZ через &p_kn_kk_link_mode без переписывания.
Строка УЗ без дочки — самостоятельная сущность TAS, а не дочерняя заявка.

Технические q_entity_id/tas_entity_id действуют в рамках одной пересборки;
для внешних связей использовать бизнес-RK вместе с источником.
DROP удаляет только результаты этого скрипта с префиксами prt_tqs_/prt_qas_ и итог.
Источники не изменяются. На боевых объёмах сначала посмотреть планы загрузок.
*/

-- ==================== 1. RAW -> ОЧИСТКА -> ПРОДУКТ -> ВЕРИФИКАЦИЯ ====================

-- 1.1. Новый источник: явно выбираем атрибуты для очистки, приоритетов и витрины.
drop table if exists &db_sbx.prt_tqs_questionnaire_raw;
create table &db_sbx.prt_tqs_questionnaire_raw
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    row_number() over (order by r.questionnaire_id, r.status, r.createtime_dttm, r.sessionintention_id) as source_row_id,
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
    r.src_cd_src,
    r.questionnaire_dt,
    r.business_dt,
    r.createtime_dttm,
    r.prescoring_dt,
    r.scoring_dt,
    r.processed_dttm,
    r.sessionintention_id,
    r.globalclient_id,
    r.person_id,
    r.last_nm,
    r.first_nm,
    r.middle_nm,
    r.tax_payer_num,
    r.email,
    r.client_type,
    r.company_nm,
    r.phone_num,
    r.credit_amt,
    r.zero_visits_flg,
    r.spec_program,
    r.salary_card_flg
from &p_db_rawd.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention r
distributed randomly;

-- 1.2. Безопасный CAST текстовых дат; порядок первого COALESCE не меняем.
drop table if exists &db_sbx.prt_tqs_questionnaire_parsed;
create table &db_sbx.prt_tqs_questionnaire_parsed
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
with parsed as (
    select r.source_row_id,
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
        r.src_cd_src,
        r.questionnaire_dt,
        r.business_dt,
        r.createtime_dttm,
        r.prescoring_dt,
        r.scoring_dt,
        r.processed_dttm,
        r.sessionintention_id,
        r.globalclient_id,
        r.person_id,
        r.last_nm,
        r.first_nm,
        r.middle_nm,
        r.tax_payer_num,
        r.email,
        r.client_type,
        r.company_nm,
        r.phone_num,
        r.credit_amt,
        r.zero_visits_flg,
        r.spec_program,
        r.salary_card_flg,
        case when r.questionnaire_dt ~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])[ T]([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]([.][0-9]+)?([ ]?([Zz]|[+-](0[0-9]|1[0-5])(:[0-5][0-9])?))?$' then
        case when cast(substring(r.questionnaire_dt from 1 for 4) as integer) >= 1 and cast(substring(r.questionnaire_dt from 9 for 2) as integer) <=
             case substring(r.questionnaire_dt from 6 for 2)
                 when '02' then 28 + case when mod(cast(substring(r.questionnaire_dt from 1 for 4) as integer),4) = 0
                     and (mod(cast(substring(r.questionnaire_dt from 1 for 4) as integer),100) <> 0 or mod(cast(substring(r.questionnaire_dt from 1 for 4) as integer),400) = 0) then 1 else 0 end
                 when '04' then 30 when '06' then 30 when '09' then 30 when '11' then 30
                 else 31 end
             then cast(r.questionnaire_dt as timestamp) else null end
        else null end as parsed_questionnaire_dt,
        case when r.business_dt ~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])[ T]([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]([.][0-9]+)?([ ]?([Zz]|[+-](0[0-9]|1[0-5])(:[0-5][0-9])?))?$' then
        case when cast(substring(r.business_dt from 1 for 4) as integer) >= 1 and cast(substring(r.business_dt from 9 for 2) as integer) <=
             case substring(r.business_dt from 6 for 2)
                 when '02' then 28 + case when mod(cast(substring(r.business_dt from 1 for 4) as integer),4) = 0
                     and (mod(cast(substring(r.business_dt from 1 for 4) as integer),100) <> 0 or mod(cast(substring(r.business_dt from 1 for 4) as integer),400) = 0) then 1 else 0 end
                 when '04' then 30 when '06' then 30 when '09' then 30 when '11' then 30
                 else 31 end
             then cast(r.business_dt as timestamp) else null end
        else null end as parsed_business_dt,
        case when r.createtime_dttm ~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])[ T]([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]([.][0-9]+)?([ ]?([Zz]|[+-](0[0-9]|1[0-5])(:[0-5][0-9])?))?$' then
        case when cast(substring(r.createtime_dttm from 1 for 4) as integer) >= 1 and cast(substring(r.createtime_dttm from 9 for 2) as integer) <=
             case substring(r.createtime_dttm from 6 for 2)
                 when '02' then 28 + case when mod(cast(substring(r.createtime_dttm from 1 for 4) as integer),4) = 0
                     and (mod(cast(substring(r.createtime_dttm from 1 for 4) as integer),100) <> 0 or mod(cast(substring(r.createtime_dttm from 1 for 4) as integer),400) = 0) then 1 else 0 end
                 when '04' then 30 when '06' then 30 when '09' then 30 when '11' then 30
                 else 31 end
             then cast(r.createtime_dttm as timestamp) else null end
        else null end as parsed_createtime_dttm,
        case when r.prescoring_dt ~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])[ T]([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]([.][0-9]+)?([ ]?([Zz]|[+-](0[0-9]|1[0-5])(:[0-5][0-9])?))?$' then
        case when cast(substring(r.prescoring_dt from 1 for 4) as integer) >= 1 and cast(substring(r.prescoring_dt from 9 for 2) as integer) <=
             case substring(r.prescoring_dt from 6 for 2)
                 when '02' then 28 + case when mod(cast(substring(r.prescoring_dt from 1 for 4) as integer),4) = 0
                     and (mod(cast(substring(r.prescoring_dt from 1 for 4) as integer),100) <> 0 or mod(cast(substring(r.prescoring_dt from 1 for 4) as integer),400) = 0) then 1 else 0 end
                 when '04' then 30 when '06' then 30 when '09' then 30 when '11' then 30
                 else 31 end
             then cast(r.prescoring_dt as timestamp) else null end
        else null end as parsed_prescoring_dt,
        case when r.scoring_dt ~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])[ T]([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]([.][0-9]+)?([ ]?([Zz]|[+-](0[0-9]|1[0-5])(:[0-5][0-9])?))?$' then
        case when cast(substring(r.scoring_dt from 1 for 4) as integer) >= 1 and cast(substring(r.scoring_dt from 9 for 2) as integer) <=
             case substring(r.scoring_dt from 6 for 2)
                 when '02' then 28 + case when mod(cast(substring(r.scoring_dt from 1 for 4) as integer),4) = 0
                     and (mod(cast(substring(r.scoring_dt from 1 for 4) as integer),100) <> 0 or mod(cast(substring(r.scoring_dt from 1 for 4) as integer),400) = 0) then 1 else 0 end
                 when '04' then 30 when '06' then 30 when '09' then 30 when '11' then 30
                 else 31 end
             then cast(r.scoring_dt as timestamp) else null end
        else null end as parsed_scoring_dt,
        case when r.processed_dttm ~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])[ T]([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]([.][0-9]+)?([ ]?([Zz]|[+-](0[0-9]|1[0-5])(:[0-5][0-9])?))?$' then
        case when cast(substring(r.processed_dttm from 1 for 4) as integer) >= 1 and cast(substring(r.processed_dttm from 9 for 2) as integer) <=
             case substring(r.processed_dttm from 6 for 2)
                 when '02' then 28 + case when mod(cast(substring(r.processed_dttm from 1 for 4) as integer),4) = 0
                     and (mod(cast(substring(r.processed_dttm from 1 for 4) as integer),100) <> 0 or mod(cast(substring(r.processed_dttm from 1 for 4) as integer),400) = 0) then 1 else 0 end
                 when '04' then 30 when '06' then 30 when '09' then 30 when '11' then 30
                 else 31 end
             then cast(r.processed_dttm as timestamp) else null end
        else null end as parsed_processed_dttm
    from &db_sbx.prt_tqs_questionnaire_raw r
)
select p.source_row_id,
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
    p.src_cd_src,
    p.questionnaire_dt,
    p.business_dt,
    p.createtime_dttm,
    p.prescoring_dt,
    p.scoring_dt,
    p.processed_dttm,
    p.sessionintention_id,
    p.globalclient_id,
    p.person_id,
    p.last_nm,
    p.first_nm,
    p.middle_nm,
    p.tax_payer_num,
    p.email,
    p.client_type,
    p.company_nm,
    p.phone_num,
    p.credit_amt,
    p.zero_visits_flg,
    p.spec_program,
    p.salary_card_flg,
    p.parsed_questionnaire_dt,
    p.parsed_business_dt,
    p.parsed_createtime_dttm,
    p.parsed_prescoring_dt,
    p.parsed_scoring_dt,
    p.parsed_processed_dttm,
    case when p.questionnaire_dt is not null then p.parsed_questionnaire_dt
         when p.business_dt is not null then p.parsed_business_dt
         else p.parsed_createtime_dttm end as first_source_dttm
from parsed p
distributed randomly;

-- 1.3. Причины отбраковки: тестовые ФИО, маски дат, календарь, период и будущее.
drop table if exists &db_sbx.prt_tqs_questionnaire_checked;
create table &db_sbx.prt_tqs_questionnaire_checked
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    p.source_row_id,
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
    p.src_cd_src,
    p.questionnaire_dt,
    p.business_dt,
    p.createtime_dttm,
    p.prescoring_dt,
    p.scoring_dt,
    p.processed_dttm,
    p.sessionintention_id,
    p.globalclient_id,
    p.person_id,
    p.last_nm,
    p.first_nm,
    p.middle_nm,
    p.tax_payer_num,
    p.email,
    p.client_type,
    p.company_nm,
    p.phone_num,
    p.credit_amt,
    p.zero_visits_flg,
    p.spec_program,
    p.salary_card_flg,
    p.parsed_questionnaire_dt,
    p.parsed_business_dt,
    p.parsed_createtime_dttm,
    p.parsed_prescoring_dt,
    p.parsed_scoring_dt,
    p.parsed_processed_dttm,
    p.first_source_dttm,
    case when p.questionnaire_dt is not null and p.parsed_questionnaire_dt is null then 1 else 0 end + case when p.business_dt is not null and p.parsed_business_dt is null then 1 else 0 end + case when p.createtime_dttm is not null and p.parsed_createtime_dttm is null then 1 else 0 end + case when p.prescoring_dt is not null and p.parsed_prescoring_dt is null then 1 else 0 end + case when p.scoring_dt is not null and p.parsed_scoring_dt is null then 1 else 0 end + case when p.processed_dttm is not null and p.parsed_processed_dttm is null then 1 else 0 end as invalid_date_field_count,
    case
        when exists (
            select 1 from unnest(array[&p_test_first_nm_like_text_list]) as t(pattern)
            where coalesce(upper(p.first_nm), '#') like t.pattern
        ) then 'TEST_FIRST_NAME_PATTERN'
        when coalesce(upper(p.first_nm), '#') in (&p_test_first_nm_in_text_list) then 'TEST_FIRST_NAME'
        when coalesce(upper(p.last_nm), '#') in (&p_test_last_nm_in_text_list) then 'TEST_LAST_NAME'
        when coalesce(upper(p.middle_nm), '#') like &p_test_middle_nm_like_text_list then 'TEST_MIDDLE_NAME'
        when position('%' in coalesce(p.questionnaire_dt, p.business_dt, p.createtime_dttm)) > 0 then 'MASKED_PRIMARY_DATE'
        when p.first_source_dttm is null then 'INVALID_PRIMARY_DATE'
        when p.first_source_dttm < cast(&p_rds_report_dt_date as timestamp) then 'BEFORE_RAW_BEGIN_DATE'
        when coalesce(p.parsed_createtime_dttm, p.parsed_processed_dttm, p.parsed_business_dt,
                      p.parsed_questionnaire_dt) > cast(&p_report_timestamp as timestamp) then 'FUTURE_RECORD'
        else 'OK'
    end as source_filter_reason
from &db_sbx.prt_tqs_questionnaire_parsed p
distributed randomly;

-- 1.4. Приоритеты прототипа: одна победившая строка на questionnaire_id/status.
drop table if exists &db_sbx.prt_tqs_questionnaire_ranked;
create table &db_sbx.prt_tqs_questionnaire_ranked
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    r.source_row_id,
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
    r.src_cd_src,
    min(r.first_source_dttm) over (partition by r.questionnaire_id, case when nullif(btrim(r.questionnaire_id), '') is null then r.source_row_id else null end) as questionnaire_dttm,
    date_trunc('seconds', coalesce(r.parsed_questionnaire_dt, r.parsed_business_dt,
        r.parsed_createtime_dttm, r.parsed_prescoring_dt, r.parsed_scoring_dt,
        r.parsed_processed_dttm)) as original_effective_from_dttm_auto_kn,
    date_trunc('seconds', coalesce(r.parsed_business_dt, r.parsed_processed_dttm,
        r.parsed_questionnaire_dt, r.parsed_createtime_dttm, r.parsed_prescoring_dt,
        r.parsed_scoring_dt)) as original_effective_from_dttm_kk_dk,
    coalesce(r.parsed_createtime_dttm, r.parsed_processed_dttm, r.parsed_business_dt,
             r.parsed_questionnaire_dt) as status_observed_dttm,
    row_number() over (
        partition by r.questionnaire_id, r.status, case when nullif(btrim(r.questionnaire_id), '') is null then r.source_row_id else null end
        order by coalesce(r.parsed_createtime_dttm, cast(&p_min_dttm as timestamp)) desc,
                 r.sessionintention_id asc nulls last,
                 coalesce(r.parsed_processed_dttm, cast(&p_min_dttm as timestamp)) desc,
                 coalesce(r.parsed_business_dt, cast(&p_min_dttm as timestamp)) desc,
                 r.utmcn desc nulls first,
                 r.utmcct desc nulls first,
                 r.utmcmd desc nulls first,
                 coalesce(r.globalclient_id, '#') desc,
                 coalesce(r.person_id, '#') desc,
                 coalesce(r.last_nm, r.first_nm, r.middle_nm, '#') desc,
                 coalesce(r.tax_payer_num, '#') desc,
                 coalesce(r.email, '#') desc,
                 coalesce(r.client_type, '#') desc,
                 coalesce(r.company_nm, '#') desc,
                 cast(case when r.phone_num not like ('%%%') then 1 else 0 end as integer) desc,
                 r.credit_amt desc nulls first,
                 r.zero_visits_flg desc nulls first,
                 r.product_type_code asc nulls last,
                 coalesce(r.parsed_questionnaire_dt, cast(&p_min_dttm as timestamp)) desc,
                 r.program_type asc nulls last,
                 coalesce(r.parsed_scoring_dt, cast(&p_min_dttm as timestamp)) desc,
                 coalesce(r.parsed_prescoring_dt, cast(&p_min_dttm as timestamp)) desc,
                 r.application_num desc nulls first,
                 coalesce(r.scoring_status_nm, '#') desc,
                 coalesce(r.prescoring_status_nm, '#') desc,
                 coalesce(r.spec_program, '#') desc,
                 coalesce(r.src_cd_src, '#') desc,
                 r.salary_card_flg desc nulls first,
                 r.phone_num asc nulls last
    ) as source_status_rn
from &db_sbx.prt_tqs_questionnaire_checked r
where r.source_filter_reason = 'OK'
distributed randomly;

-- 1.5. prt_tqs_questionnaire: очищенный результат первого шага; только нужные атрибуты.
drop table if exists &db_sbx.prt_tqs_questionnaire;
create table &db_sbx.prt_tqs_questionnaire
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    r.source_row_id,
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
    r.src_cd_src,
    r.questionnaire_dttm,
    r.original_effective_from_dttm_auto_kn,
    r.original_effective_from_dttm_kk_dk,
    r.status_observed_dttm
from &db_sbx.prt_tqs_questionnaire_ranked r
where r.source_status_rn = 1
distributed randomly;

-- 1.6. Продукт по product_type_code; названия статусов/правила КК из прототипа.
drop table if exists &db_sbx.prt_tqs_questionnaire_product;
create table &db_sbx.prt_tqs_questionnaire_product
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
with codes as (
    select q.source_row_id,
        q.questionnaire_id,
        q.application_num,
        q.utmcn,
        q.utmcmd,
        q.utmcsr,
        q.utmctr,
        q.utmcct,
        q.status,
        q.scoring_status_nm,
        q.prescoring_status_nm,
        q.product_type_code,
        q.program_type,
        q.src_cd,
        q.src_cd_src,
        q.questionnaire_dttm,
        q.original_effective_from_dttm_auto_kn,
        q.original_effective_from_dttm_kk_dk,
        q.status_observed_dttm,
        case when q.product_type_code in (&p_quest_product_kn_list) then 1 else 0 end as is_kn,
        case when q.product_type_code in (&p_quest_product_kk_list) then 1 else 0 end as is_kk,
        case when q.product_type_code in (&p_quest_product_ak_list) then 1 else 0 end as is_auto
    from &db_sbx.prt_tqs_questionnaire q
), mapped as (
    select c.source_row_id,
        c.questionnaire_id,
        c.application_num,
        c.utmcn,
        c.utmcmd,
        c.utmcsr,
        c.utmctr,
        c.utmcct,
        c.status,
        c.scoring_status_nm,
        c.prescoring_status_nm,
        c.product_type_code,
        c.program_type,
        c.src_cd,
        c.src_cd_src,
        c.questionnaire_dttm,
        c.original_effective_from_dttm_auto_kn,
        c.original_effective_from_dttm_kk_dk,
        c.status_observed_dttm,
        c.is_kn + c.is_kk + c.is_auto as product_match_count,
        case when c.is_kn + c.is_kk + c.is_auto <> 1 then cast(null as text)
             when c.is_kn = 1 then cast(&p_prod_kn_name as text)
             when c.is_kk = 1 then cast(&p_prod_kk_name as text)
             when c.is_auto = 1 then cast(&p_prod_auto_name as text) end as level25_product_bp_nm
    from codes c
)
select p.source_row_id,
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
    p.src_cd_src,
    p.questionnaire_dttm,
    p.original_effective_from_dttm_auto_kn,
    p.original_effective_from_dttm_kk_dk,
    p.status_observed_dttm,
    p.level25_product_bp_nm,
    p.product_match_count,
    case when p.level25_product_bp_nm = cast(&p_prod_kn_name as text) then 'KN'
         when p.level25_product_bp_nm = cast(&p_prod_kk_name as text) then 'KK'
         when p.level25_product_bp_nm = cast(&p_prod_auto_name as text) then 'AUTO' end as product_branch,
    case when p.level25_product_bp_nm = cast(&p_prod_kn_name as text) then case p.status
            when '0' then 'Создана'
            when '71' then 'Ошибка на прескоринге'
            when '72' then 'Ошибка на скоринге'
            when '90' then 'Закрыта'
            when 'CLIENT_DECLINE' then 'Закрыта'
            when 'CHECK_LIST_EMPTY' then 'Одобрено'
            when 'CHECK_LIST_UNDERWRITING' then 'Одобрено'
            when 'CHECK_LIST_ANTIFRAUD_OR_PRODUCT' then 'Одобрено'
            when 'HARD_DECLINE' then 'Жесткий отказ'
            when 'SOFT_DECLINE' then 'Не мораторный отказ'
            when 'SHORT_FORM' then 'Предварительно одобрено (call0)'
            when 'DONE' then 'Кредит выдан'
            when 'SCORING' then 'В процессе скоринга'
            when 'CONFIGURATION' then 'Подбор продукта'
            when 'ANTIFRAUD' then 'Антифрод'
            when 'CHOICE_CONFIRMATION' then 'Выбор способа подтверждения'
            when 'DATA_CORRECTION' then 'Корректировка данных'
            when 'DATA_CORRECTION_WAITING' then 'Корректировка данных (ожидание)'
            when 'FINAL_SCAN' then 'Сканирование документов'
            when 'FULL_FORM' then 'Полная заявка'
            when 'PRODUCT_ISSUE' then 'Формирование КОД'
            when 'UNDERWRITING' then 'Андеррайтинг'
            when 'TECHNICAL_DECLINE' then 'Отказ по техническим причинам'
            when 'IDENTIFICATION' then 'Идентификация'
            when 'CLARIFICATION' then 'Уточнение'
            when 'UNKNOWN-ERROR' then 'Неизвестная ошибка'
            else coalesce(p.status, 'Не определено') end
         when p.level25_product_bp_nm = cast(&p_prod_kk_name as text) then case p.status
            when 'CANCELLED' then 'Отмена'
            when 'CHECKING' then 'На проверке'
            when 'CLIENT_DECLINE' then 'Отказ по инициативе клиента'
            when 'COURIER' then 'Курьер'
            when 'CREATED' then 'Создана'
            when 'DECLINE' then 'Отказ'
            when 'DELIVERY' then 'Доставка'
            when 'DONE' then 'Выдача'
            when 'DRAFT' then 'Черновик'
            when 'EXPIRED' then 'Просрочено'
            when 'FAILED' then 'Ошибка'
            when 'NEED_BKI' then 'Требуется проверка в БКИ'
            when 'NO_OFFER' then 'Нет предложения'
            when 'ONLY_SALE_POINT' then 'Выдача только в ТП'
            when 'SALE_POINT' then 'Необходим визит в ТП'
            when 'SCORING' then 'В процессе скоринга'
            when 'SELECT_CARD' then 'Выбор карты'
            else coalesce(p.status, 'Не определено') end
         else p.status end as status_name,
    case when p.level25_product_bp_nm = cast(&p_prod_kn_name as text) then case p.status
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
        else null end else null end as kn_status_priority,
    case when p.product_match_count = 0 then 'OUTSIDE_OR_UNMAPPED_PRODUCT'
         when p.product_match_count > 1 then 'AMBIGUOUS_PRODUCT_CODE'
         when p.level25_product_bp_nm = cast(&p_prod_kk_name as text)
              and (p.questionnaire_id is null or length(p.questionnaire_id) in (&p_quest_not_len_id_kk_list))
              then 'KK_PARTNER_OR_MISSING_ID'
         else 'OK' end as product_filter_reason
from mapped p
distributed randomly;

-- 1.7. Верификация по продукту и всей очищенной истории; все номера передаются дальше.
drop table if exists &db_sbx.prt_tqs_questionnaire_verified;
create table &db_sbx.prt_tqs_questionnaire_verified
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    q.source_row_id,
    q.questionnaire_id,
    q.application_num,
    q.utmcn,
    q.utmcmd,
    q.utmcsr,
    q.utmctr,
    q.utmcct,
    q.status,
    q.scoring_status_nm,
    q.prescoring_status_nm,
    q.product_type_code,
    q.program_type,
    q.src_cd,
    q.src_cd_src,
    q.questionnaire_dttm,
    q.original_effective_from_dttm_auto_kn,
    q.original_effective_from_dttm_kk_dk,
    q.status_observed_dttm,
    q.level25_product_bp_nm,
    q.product_match_count,
    q.product_branch,
    q.status_name,
    q.kn_status_priority,
    q.product_filter_reason,
    case when nullif(btrim(q.questionnaire_id), '') is null then cast(null as boolean)
         else max(case
        when q.level25_product_bp_nm = cast(&p_prod_kn_name as text)
         and q.status in (&p_kn_verification_status) then 1
        when q.level25_product_bp_nm = cast(&p_prod_kk_name as text)
         and q.status in (&p_kk_verification_status) then 1
        when q.level25_product_bp_nm = cast(&p_prod_auto_name as text)
         and q.status in (&p_auto_verification_status) then 1 else 0 end) over (partition by q.questionnaire_id, q.level25_product_bp_nm, case when nullif(btrim(q.questionnaire_id), '') is null then q.source_row_id else null end) = 1 end as verification_flg,
    array_agg(q.application_num) over (partition by q.questionnaire_id, q.level25_product_bp_nm, case when nullif(btrim(q.questionnaire_id), '') is null then q.source_row_id else null end) as application_nums,
    count(*) over (partition by q.questionnaire_id, q.level25_product_bp_nm, case when nullif(btrim(q.questionnaire_id), '') is null then q.source_row_id else null end) as history_row_count,
    count(q.status) over (partition by q.questionnaire_id, q.level25_product_bp_nm, case when nullif(btrim(q.questionnaire_id), '') is null then q.source_row_id else null end) as status_count,
    case when q.level25_product_bp_nm = cast(&p_prod_kk_name as text)
         then q.original_effective_from_dttm_kk_dk
         else q.original_effective_from_dttm_auto_kn end as effective_from_dttm,
    row_number() over (
        partition by q.questionnaire_id, q.level25_product_bp_nm, case when nullif(btrim(q.questionnaire_id), '') is null then q.source_row_id else null end
        order by q.status_observed_dttm desc nulls last, q.kn_status_priority desc nulls last,
                 q.source_row_id desc
    ) as entity_status_rn
from &db_sbx.prt_tqs_questionnaire_product q
where q.product_filter_reason = 'OK'
distributed randomly;

-- 1.8. Представитель анкеты для соединений; номера всех статусов сохранены в application_nums.
drop table if exists &db_sbx.prt_qas_questionnaire;
create table &db_sbx.prt_qas_questionnaire
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    row_number() over (order by q.questionnaire_id, q.level25_product_bp_nm, q.source_row_id) as q_entity_id,
    q.questionnaire_id as questionnaire_id,
    q.application_num as application_num,
    q.application_nums as application_nums,
    q.src_cd as q_src_cd,
    q.src_cd_src as src_cd_src,
    q.utmcn as utmcn,
    q.utmcmd as utmcmd,
    q.utmcsr as utmcsr,
    q.utmctr as utmctr,
    q.utmcct as utmcct,
    q.questionnaire_dttm as questionnaire_dttm,
    q.status as status_cd,
    q.status_name as status_name,
    q.scoring_status_nm as scoring_status_nm,
    q.prescoring_status_nm as prescoring_status_nm,
    q.product_type_code as product_type_cd,
    q.program_type as program_type,
    q.level25_product_bp_nm as level25_product_bp_nm,
    q.original_effective_from_dttm_auto_kn as original_effective_from_dttm_auto_kn,
    q.original_effective_from_dttm_kk_dk as original_effective_from_dttm_kk_dk,
    q.effective_from_dttm as effective_from_dttm,
    q.status_observed_dttm as status_observed_dttm,
    q.product_branch as product_branch,
    case when q.product_match_count = 1 then 1 else 0 end as product_match_flg,
    q.history_row_count as history_row_count,
    case when nullif(btrim(q.questionnaire_id), '') is null then 0 else 1 end as id_count,
    q.status_count as status_count,
    q.verification_flg as verification_flg
from &db_sbx.prt_tqs_questionnaire_verified q
where q.entity_status_rn = 1
  and (q.questionnaire_dttm >= cast(&P_BEGIN_DATE as timestamp) or q.questionnaire_dttm is null)
distributed randomly;

-- ==================== 2. ВЕТКА КН/КК ====================
-- Анкеты этой ветки — продолжение подготовленного RAW, не новый источник.

-- 2.1. Анкеты КН/КК с атрибутами, флагом и номерами; фильтр только по level25.
drop table if exists &db_sbx.prt_qas_kn_kk_questionnaire;
create table &db_sbx.prt_qas_kn_kk_questionnaire
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    q.q_entity_id,
    q.questionnaire_id,
    q.application_num,
    q.application_nums,
    q.q_src_cd,
    q.src_cd_src,
    q.utmcn,
    q.utmcmd,
    q.utmcsr,
    q.utmctr,
    q.utmcct,
    q.questionnaire_dttm,
    q.status_cd,
    q.status_name,
    q.scoring_status_nm,
    q.prescoring_status_nm,
    q.product_type_cd,
    q.program_type,
    q.level25_product_bp_nm,
    q.original_effective_from_dttm_auto_kn,
    q.original_effective_from_dttm_kk_dk,
    q.effective_from_dttm,
    q.status_observed_dttm,
    q.product_branch,
    q.product_match_flg,
    q.history_row_count,
    q.id_count,
    q.status_count,
    q.verification_flg
from &db_sbx.prt_qas_questionnaire q
where q.level25_product_bp_nm in (&p_prod_kn_name, &p_prod_kk_name)
distributed randomly;

-- 2.2. Текущие BDM-заявки продуктовых систем и УЗ.
drop table if exists &db_sbx.prt_qas_kn_kk_bdm_application;
create table &db_sbx.prt_qas_kn_kk_bdm_application
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select distinct
    a.application_rk, a.application_num, a.src_cd
from &p_db_bdm.application a
where a.effective_to_date = cast(&p_max_date as date)
  and (not cast(&p_bdm_limit_by_begin_date as boolean) or a.application_begin_date >= cast(&P_BEGIN_DATE as date))
  and a.src_cd in ('MSSA', 'MSCL', 'CCPP_CRCA', 'CCPP_BATR')
  and a.application_rk is not null and a.application_rk <> -1
  and nullif(btrim(a.application_num), '') is not null
distributed randomly;

-- 2.3. Загрузка TAS: предполагаемый актуальный снимок; -1 -> NULL перед связями.
drop table if exists &db_sbx.prt_qas_kn_kk_tas_raw;
create table &db_sbx.prt_qas_kn_kk_tas_raw
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
from &db_sbx.tech_application_status t
where (t.src_cd in ('MSCL', 'CCPP_CRCA', 'CCPP_BATR', 'MSSA')
       or (t.src_cd is null and t.parent_src_cd = 'MSSA'
           and nullif(t.parent_application_rk, -1) is not null))
  and (coalesce(t.application_dt, t.parent_application_dt) >= cast(&P_BEGIN_DATE as date)
       or coalesce(t.application_dt, t.parent_application_dt) is null)
-- При версионной TAS добавить подтверждённый фильтр актуальности ЗДЕСЬ.
distributed randomly;

-- 2.4. Сущности TAS: ключ родителя + ребёнка; конфликты атрибутов не выбираем произвольно.
drop table if exists &db_sbx.prt_qas_kn_kk_tas;
create table &db_sbx.prt_qas_kn_kk_tas
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
    from &db_sbx.prt_qas_kn_kk_tas_raw r
    group by r.parent_application_rk, r.parent_src_cd, r.application_rk, r.src_cd, case when r.application_rk is null and r.parent_application_rk is null then r.tas_row_id else null end
) g
distributed randomly;

-- 2.5. Каждый application_num подготовленной анкеты -> BDM application_rk.
drop table if exists &db_sbx.prt_qas_kn_kk_questionnaire_bdm;
create table &db_sbx.prt_qas_kn_kk_questionnaire_bdm
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select distinct
    q.q_entity_id,
    q.product_branch,
    n.application_num,
    a.application_rk,
    a.src_cd
from &db_sbx.prt_qas_kn_kk_questionnaire q
cross join lateral unnest(q.application_nums) as n(application_num)
join &db_sbx.prt_qas_kn_kk_bdm_application a on a.application_num = n.application_num
where nullif(btrim(n.application_num), '') is not null
  and (a.src_cd = 'MSSA'
       or (q.level25_product_bp_nm = cast(&p_prod_kn_name as text) and a.src_cd = 'MSCL')
       or (q.level25_product_bp_nm = cast(&p_prod_kk_name as text) and a.src_cd in ('CCPP_CRCA', 'CCPP_BATR')))
distributed randomly;

-- 2.6. Кандидаты: прямой путь, родитель УЗ, УЗ без ребёнка, собственный ключ УЗ.
drop table if exists &db_sbx.prt_qas_kn_kk_link_candidates;
create table &db_sbx.prt_qas_kn_kk_link_candidates
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select distinct
    b.product_branch, b.q_entity_id, t.app_entity_id, cast('DIRECT_PRODUCT' as text) as link_route
from &db_sbx.prt_qas_kn_kk_questionnaire_bdm b
join &db_sbx.prt_qas_kn_kk_tas t
  on t.application_rk = b.application_rk and t.src_cd = b.src_cd
where b.src_cd <> 'MSSA'
union all
select distinct b.product_branch, b.q_entity_id, t.app_entity_id, 'UZ_PARENT'
from &db_sbx.prt_qas_kn_kk_questionnaire_bdm b
join &db_sbx.prt_qas_kn_kk_tas t
  on t.parent_application_rk = b.application_rk and t.parent_src_cd = 'MSSA'
 and t.product_branch = b.product_branch and t.application_rk is not null
where b.src_cd = 'MSSA'
union all
select distinct b.product_branch, b.q_entity_id, t.app_entity_id, 'UZ_ONLY'
from &db_sbx.prt_qas_kn_kk_questionnaire_bdm b
join &db_sbx.prt_qas_kn_kk_tas t
  on t.parent_application_rk = b.application_rk and t.parent_src_cd = 'MSSA'
 and t.tas_entity_type = 'UZ_ONLY'
where b.src_cd = 'MSSA'
union all
select distinct b.product_branch, b.q_entity_id, t.app_entity_id, 'UZ_SELF'
from &db_sbx.prt_qas_kn_kk_questionnaire_bdm b
join &db_sbx.prt_qas_kn_kk_tas t
  on t.application_rk = b.application_rk and t.src_cd = 'MSSA'
where b.src_cd = 'MSSA'
distributed randomly;

-- 2.7. Сравнение путей: уникальные сущности, покрытие и N:M. UZ_ONLY — отдельная цель.
drop table if exists &db_sbx.prt_qas_kn_kk_link_quality;
create table &db_sbx.prt_qas_kn_kk_link_quality
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
with branches as (
    select cast('KN' as text) as product_branch union all select 'KK'
), routes as (
    select cast('DIRECT_PRODUCT' as text) as link_route
    union all select 'UZ_PARENT' union all select 'UZ_ONLY' union all select 'UZ_SELF'
), q_totals as (
    select product_branch, count(*) as q_total
    from &db_sbx.prt_qas_kn_kk_questionnaire group by product_branch
), q_degrees as (
    select product_branch, link_route, q_entity_id, count(*) as app_count
    from &db_sbx.prt_qas_kn_kk_link_candidates group by product_branch, link_route, q_entity_id
), app_degrees as (
    select product_branch, link_route, app_entity_id, count(*) as q_count
    from &db_sbx.prt_qas_kn_kk_link_candidates group by product_branch, link_route, app_entity_id
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
    from &db_sbx.prt_qas_kn_kk_link_candidates e
    join q_degrees q on q.product_branch = e.product_branch and q.link_route = e.link_route
                   and q.q_entity_id = e.q_entity_id
    join app_degrees a on a.product_branch = e.product_branch and a.link_route = e.link_route
                     and a.app_entity_id = e.app_entity_id
    group by e.product_branch, e.link_route
), target_totals as (
    select b.product_branch, r.link_route, count(t.app_entity_id) as app_total
    from branches b cross join routes r
    left join &db_sbx.prt_qas_kn_kk_tas t
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
drop table if exists &db_sbx.prt_qas_kn_kk_links;
create table &db_sbx.prt_qas_kn_kk_links
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select d.q_entity_id, d.app_entity_id, d.link_routes,
       count(*) over (partition by d.q_entity_id) as q_link_count,
       count(*) over (partition by d.app_entity_id) as app_link_count
from (
    select c.q_entity_id, c.app_entity_id,
           string_agg(c.link_route, ',' order by c.link_route) as link_routes
    from &db_sbx.prt_qas_kn_kk_link_candidates c
    where cast(&p_kn_kk_link_mode as text) = 'ALL'
       or (cast(&p_kn_kk_link_mode as text) = 'DIRECT' and c.link_route = 'DIRECT_PRODUCT')
       or (cast(&p_kn_kk_link_mode as text) = 'UZ' and c.link_route in ('UZ_PARENT', 'UZ_ONLY', 'UZ_SELF'))
    group by c.q_entity_id, c.app_entity_id
) d
distributed randomly;

-- 2.9. Ветка целиком: связанные пары + анкеты без пары + все строки TAS без пары.
drop table if exists &db_sbx.prt_qas_kn_kk_fin;
create table &db_sbx.prt_qas_kn_kk_fin
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
    q.questionnaire_id as q_questionnaire_id,
    q.application_num as q_application_num,
    q.application_nums as q_application_nums,
    q.src_cd_src as q_src_cd_src,
    q.utmcn as q_utmcn,
    q.utmcmd as q_utmcmd,
    q.utmcsr as q_utmcsr,
    q.utmctr as q_utmctr,
    q.utmcct as q_utmcct,
    q.scoring_status_nm as q_scoring_status_nm,
    q.prescoring_status_nm as q_prescoring_status_nm,
    q.original_effective_from_dttm_auto_kn as q_original_effective_from_dttm_auto_kn,
    q.original_effective_from_dttm_kk_dk as q_original_effective_from_dttm_kk_dk,
    q.effective_from_dttm as q_effective_from_dttm,
    q.status_observed_dttm as q_status_observed_dttm,
    q.q_src_cd as q_src_cd,
    q.questionnaire_dttm as q_questionnaire_dttm,
    q.status_cd as q_status_cd,
    q.status_name as q_status_name,
    q.product_type_cd as q_product_type_cd,
    q.program_type as q_program_type,
    q.level25_product_bp_nm as q_level25_product_bp_nm,
    q.product_match_flg as q_product_match_flg,
    q.history_row_count as q_history_row_count,
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
from &db_sbx.prt_qas_kn_kk_questionnaire q
left join &db_sbx.prt_qas_kn_kk_links l on l.q_entity_id = q.q_entity_id
full outer join &db_sbx.prt_qas_kn_kk_tas t on t.app_entity_id = l.app_entity_id
distributed randomly;

-- Отчёт КН/КК: прямой и родительский пути сравниваются на одной базе анкет.
-- У UZ_ONLY/UZ_SELF другой набор целевых сущностей TAS; app_coverage не смешиваем.
select product_branch, link_route, q_total, q_matched, q_coverage_pct,
       pair_count, many_to_many_pairs
from &db_sbx.prt_qas_kn_kk_link_quality order by product_branch, link_route;

-- ==================== 3. ВЕТКА АВТОКРЕДИТОВ ====================

-- 3.0. Анкеты авто — продолжение общей подготовленной цепочки, фильтр по level25.
drop table if exists &db_sbx.prt_qas_auto_questionnaire;
create table &db_sbx.prt_qas_auto_questionnaire
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    q.q_entity_id,
    q.questionnaire_id,
    q.application_num,
    q.application_nums,
    q.q_src_cd,
    q.src_cd_src,
    q.utmcn,
    q.utmcmd,
    q.utmcsr,
    q.utmctr,
    q.utmcct,
    q.questionnaire_dttm,
    q.status_cd,
    q.status_name,
    q.scoring_status_nm,
    q.prescoring_status_nm,
    q.product_type_cd,
    q.program_type,
    q.level25_product_bp_nm,
    q.original_effective_from_dttm_auto_kn,
    q.original_effective_from_dttm_kk_dk,
    q.effective_from_dttm,
    q.status_observed_dttm,
    q.product_branch,
    q.product_match_flg,
    q.history_row_count,
    q.id_count,
    q.status_count,
    q.verification_flg
from &db_sbx.prt_qas_questionnaire q
where q.level25_product_bp_nm = cast(&p_prod_auto_name as text)
distributed randomly;

-- 3.1. Загрузка TAS: предполагаемый актуальный снимок; -1 -> NULL перед связями.
drop table if exists &db_sbx.prt_qas_auto_tas_raw;
create table &db_sbx.prt_qas_auto_tas_raw
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
from &db_sbx.tech_application_status t
where t.src_cd = 'ALPP'
  and (coalesce(t.application_dt, t.parent_application_dt) >= cast(&P_BEGIN_DATE as date)
       or coalesce(t.application_dt, t.parent_application_dt) is null)
-- При версионной TAS добавить подтверждённый фильтр актуальности ЗДЕСЬ.
distributed randomly;

-- 3.2. Сущности TAS: ключ родителя + ребёнка; конфликты атрибутов не выбираем произвольно.
drop table if exists &db_sbx.prt_qas_auto_tas;
create table &db_sbx.prt_qas_auto_tas
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
    from &db_sbx.prt_qas_auto_tas_raw r
    group by r.parent_application_rk, r.parent_src_cd, r.application_rk, r.src_cd, case when r.application_rk is null and r.parent_application_rk is null then r.tas_row_id else null end
) g
distributed randomly;

-- 3.3. Подготовленные анкеты авто -> TAS по questionnaire_id = application_id.
drop table if exists &db_sbx.prt_qas_auto_links;
create table &db_sbx.prt_qas_auto_links
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select d.q_entity_id, d.app_entity_id,
       cast('AUTO_ID' as text) as link_routes,
       count(*) over (partition by d.q_entity_id) as q_link_count,
       count(*) over (partition by d.app_entity_id) as app_link_count
from (
    select distinct q.q_entity_id, t.app_entity_id
    from &db_sbx.prt_qas_auto_questionnaire q
    join &db_sbx.prt_qas_auto_tas t on t.application_id = q.questionnaire_id
    where q.id_count = 1
      and t.src_cd = 'ALPP' and t.application_id_count = 1
      and nullif(btrim(q.questionnaire_id), '') is not null
      and nullif(btrim(t.application_id), '') is not null
) d
distributed randomly;

-- 3.4. Ветка целиком: связанные пары + анкеты без пары + все строки TAS без пары.
drop table if exists &db_sbx.prt_qas_auto_fin;
create table &db_sbx.prt_qas_auto_fin
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
    q.questionnaire_id as q_questionnaire_id,
    q.application_num as q_application_num,
    q.application_nums as q_application_nums,
    q.src_cd_src as q_src_cd_src,
    q.utmcn as q_utmcn,
    q.utmcmd as q_utmcmd,
    q.utmcsr as q_utmcsr,
    q.utmctr as q_utmctr,
    q.utmcct as q_utmcct,
    q.scoring_status_nm as q_scoring_status_nm,
    q.prescoring_status_nm as q_prescoring_status_nm,
    q.original_effective_from_dttm_auto_kn as q_original_effective_from_dttm_auto_kn,
    q.original_effective_from_dttm_kk_dk as q_original_effective_from_dttm_kk_dk,
    q.effective_from_dttm as q_effective_from_dttm,
    q.status_observed_dttm as q_status_observed_dttm,
    q.q_src_cd as q_src_cd,
    q.questionnaire_dttm as q_questionnaire_dttm,
    q.status_cd as q_status_cd,
    q.status_name as q_status_name,
    q.product_type_cd as q_product_type_cd,
    q.program_type as q_program_type,
    q.level25_product_bp_nm as q_level25_product_bp_nm,
    q.product_match_flg as q_product_match_flg,
    q.history_row_count as q_history_row_count,
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
from &db_sbx.prt_qas_auto_questionnaire q
left join &db_sbx.prt_qas_auto_links l on l.q_entity_id = q.q_entity_id
full outer join &db_sbx.prt_qas_auto_tas t on t.app_entity_id = l.app_entity_id
distributed randomly;

-- ==================== 4. ИТОГОВАЯ ВИТРИНА И КОНТРОЛИ ====================

-- 4.1. Единая витрина. Явный состав колонок, общий флаг и обе стороны без пары.
drop table if exists &db_sbx.prt_tech_questionnaire_application_status;
create table &db_sbx.prt_tech_questionnaire_application_status
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
    q_questionnaire_id,
    q_application_num,
    q_application_nums,
    q_src_cd_src,
    q_utmcn,
    q_utmcmd,
    q_utmcsr,
    q_utmctr,
    q_utmcct,
    q_scoring_status_nm,
    q_prescoring_status_nm,
    q_original_effective_from_dttm_auto_kn,
    q_original_effective_from_dttm_kk_dk,
    q_effective_from_dttm,
    q_status_observed_dttm,
    q_src_cd,
    q_questionnaire_dttm,
    q_status_cd,
    q_status_name,
    q_product_type_cd,
    q_program_type,
    q_level25_product_bp_nm,
    q_product_match_flg,
    q_history_row_count,
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
    cast(&p_report_timestamp as timestamp) as report_dttm
from &db_sbx.prt_qas_kn_kk_fin k
union all
select
    product_branch,
    record_type,
    link_routes,
    link_cardinality,
    q_link_count,
    app_link_count,
    q_entity_id,
    q_questionnaire_id,
    q_application_num,
    q_application_nums,
    q_src_cd_src,
    q_utmcn,
    q_utmcmd,
    q_utmcsr,
    q_utmctr,
    q_utmcct,
    q_scoring_status_nm,
    q_prescoring_status_nm,
    q_original_effective_from_dttm_auto_kn,
    q_original_effective_from_dttm_kk_dk,
    q_effective_from_dttm,
    q_status_observed_dttm,
    q_src_cd,
    q_questionnaire_dttm,
    q_status_cd,
    q_status_name,
    q_product_type_cd,
    q_program_type,
    q_level25_product_bp_nm,
    q_product_match_flg,
    q_history_row_count,
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
    cast(&p_report_timestamp as timestamp) as report_dttm
from &db_sbx.prt_qas_auto_fin a
distributed randomly;

-- 4.2. Покрытие уникальных сущностей по веткам и общей базе; строки пары не знаменатель.
drop table if exists &db_sbx.prt_qas_coverage;
create table &db_sbx.prt_qas_coverage
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
with totals as (
    select product_branch,
           count(distinct q_entity_id) as q_total,
           count(distinct case when record_type = 'MATCHED' then q_entity_id end) as q_matched,
           count(distinct tas_entity_id) as app_total,
           count(distinct case when record_type = 'MATCHED' then tas_entity_id end) as app_matched
    from &db_sbx.prt_tech_questionnaire_application_status group by product_branch
    union all
    select 'ALL', count(distinct q_entity_id),
           count(distinct case when record_type = 'MATCHED' then q_entity_id end),
           count(distinct tas_entity_id),
           count(distinct case when record_type = 'MATCHED' then tas_entity_id end)
    from &db_sbx.prt_tech_questionnaire_application_status
)
select t.product_branch, t.q_total, t.q_matched,
       round(100.0 * t.q_matched / nullif(t.q_total, 0), 2) as q_coverage_pct,
       t.app_total, t.app_matched,
       round(100.0 * t.app_matched / nullif(t.app_total, 0), 2) as app_coverage_pct,
       round(100.0 * (t.q_matched + t.app_matched) / nullif(t.q_total + t.app_total, 0), 2) as entity_coverage_pct,
       cast(&p_min_coverage_pct as numeric) as reference_coverage_pct
from totals t
distributed randomly;

-- 4.3. Контроли сохранности/уникальности. Все error_count должны быть 0.
drop table if exists &db_sbx.prt_qas_checks;
create table &db_sbx.prt_qas_checks
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select cast('MISSING_QUESTIONNAIRES' as text) as check_name, count(*) as error_count
from &db_sbx.prt_qas_questionnaire q
where not exists (select 1 from &db_sbx.prt_tech_questionnaire_application_status f where f.q_entity_id = q.q_entity_id)
union all
select 'MISSING_KN_KK_TAS', count(*) from &db_sbx.prt_qas_kn_kk_tas t
where not exists (select 1 from &db_sbx.prt_tech_questionnaire_application_status f
                  where f.tas_entity_id = 'KN_KK:' || cast(t.app_entity_id as text))
union all
select 'MISSING_AUTO_TAS', count(*) from &db_sbx.prt_qas_auto_tas t
where not exists (select 1 from &db_sbx.prt_tech_questionnaire_application_status f
                  where f.tas_entity_id = 'AUTO:' || cast(t.app_entity_id as text))
union all
select 'DUPLICATE_FINAL_PAIRS', count(*) from (
    select q_entity_id, tas_entity_id
    from &db_sbx.prt_tech_questionnaire_application_status
    group by q_entity_id, tas_entity_id having count(*) > 1
) d
union all
select 'DUPLICATE_QUESTIONNAIRE_KEYS', count(*) from (
    select questionnaire_id, level25_product_bp_nm from &db_sbx.prt_qas_questionnaire
    where nullif(btrim(questionnaire_id), '') is not null
    group by questionnaire_id, level25_product_bp_nm having count(*) > 1
) d
union all
select 'INCONSISTENT_VERIFICATION_FLAGS', count(*) from (
    select q_entity_id from &db_sbx.prt_tech_questionnaire_application_status
    where q_entity_id is not null
    group by q_entity_id having count(distinct verification_flg) > 1
) d
union all
select 'EMPTY_FINAL_ROWS', count(*) from &db_sbx.prt_tech_questionnaire_application_status
where q_entity_id is null and tas_entity_id is null
union all
select 'INVALID_LINK_MODE', count(*)
where cast(&p_kn_kk_link_mode as text) not in ('ALL', 'DIRECT', 'UZ')
   or cast(&p_kn_kk_link_mode as text) is null
distributed randomly;

-- Результат 4.4: все контроли сохранности/уникальности должны быть 0.
select check_name, error_count from &db_sbx.prt_qas_checks order by check_name;

-- Результат 4.5: ориентир 10% показываем по анкетам, TAS и общей базе сущностей.
-- Общая строка ALL считает TAS-сущности один раз, даже если УЗ связалась с КН и КК.
select product_branch, q_total, q_matched, q_coverage_pct,
       app_total, app_matched, app_coverage_pct, entity_coverage_pct, reference_coverage_pct
from &db_sbx.prt_qas_coverage order by product_branch;

-- Результат 4.6: несвязанные стороны и кардинальность. N:M требует исследования.
select product_branch, record_type, link_cardinality, count(*) as row_count
from &db_sbx.prt_tech_questionnaire_application_status
group by product_branch, record_type, link_cardinality
order by product_branch, record_type, link_cardinality;

-- Результат 4.7: качество представителей анкет и объём сохранённой истории.
select product_branch, count(*) as questionnaire_count,
       sum(case when nullif(btrim(questionnaire_id), '') is null then 1 else 0 end) as missing_id_count,
       sum(case when product_match_flg <> 1 then 1 else 0 end) as product_mismatch_count,
       sum(case when id_count > 1 then 1 else 0 end) as conflicting_id_count,
       sum(case when status_count > 1 then 1 else 0 end) as questionnaires_with_history,
       sum(case when questionnaire_dttm is null then 1 else 0 end) as missing_date_count
from &db_sbx.prt_qas_questionnaire group by product_branch order by product_branch;

-- Результат 4.8: несколько разных наборов атрибутов на ключе TAS.
-- При таких конфликтах прежде всего проверить snapshot-контракт/актуальность TAS.
select cast('KN_KK' as text) as branch_group, count(*) as conflicting_tas_entities
from &db_sbx.prt_qas_kn_kk_tas where payload_variant_count > 1
union all
select 'AUTO', count(*) from &db_sbx.prt_qas_auto_tas where payload_variant_count > 1;

-- Результат 4.9: несколько номеров на одну анкету не потеряны при выборе представителя.
select q.product_branch, count(*) as questionnaires_with_multiple_nums
from &db_sbx.prt_qas_questionnaire q
where (select count(distinct n.application_num) from unnest(q.application_nums) as n(application_num)
       where nullif(btrim(n.application_num), '') is not null) > 1
group by q.product_branch order by q.product_branch;

-- Результат 4.10: причины отбраковки в исходном шаге, без персональных данных.
select source_filter_reason, count(*) as source_rows,
       sum(invalid_date_field_count) as invalid_date_fields
from &db_sbx.prt_tqs_questionnaire_checked
group by source_filter_reason order by source_filter_reason;

-- Результат 4.11: продуктовые исключения и неизвестные RAW-коды.
-- Проверить OUTSIDE_OR_UNMAPPED_PRODUCT: здесь могут быть продукты вне задачи
-- или новые коды трёх нужных продуктов, которые требуется дописать в макросписки.
select product_type_code, product_filter_reason, count(*) as source_rows
from &db_sbx.prt_tqs_questionnaire_product
where product_filter_reason <> 'OK'
group by product_type_code, product_filter_reason
order by product_filter_reason, product_type_code;

-- Результат 4.12: один ID/status с разными кодами продукта до исходной дедупликации.
-- Исходный PARTITION BY сохранён; такие случаи требуют проверки отдельно.
select count(*) as conflicting_product_groups
from (
    select questionnaire_id, status
    from &db_sbx.prt_tqs_questionnaire_checked
    where source_filter_reason = 'OK' and questionnaire_id is not null
    group by questionnaire_id, status having count(distinct product_type_code) > 1
) d;
