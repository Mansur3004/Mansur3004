/*
ЕДИНЫЙ СКРИПТ. Greenplum. Выполнять последовательно с остановкой на ошибке.
Порядок: 1 — очистка RAW и верификация анкеты; 2 — КН/КК; 3 — авто; 4 — итог и контроли.
Итог (19 бизнес-полей): &db_sbx.prt_tech_internet_funnel.
Полные атрибуты и диагностика: &db_sbx.prt_qas_funnel_detail.
Состав каждой таблицы и сопоставление полей: docs/attributes_catalog.txt.

0.1. Макропеременные (значения подставляет ETL/SQL-клиент перед запуском):

  &db_sbx                    - схема результатов и технических витрин;
                               по умолчанию: sbx_pre_orb_fd
  &p_db_bdm                  - схема BDM; по умолчанию: bdm
  &p_db_rawd                 - схема RAW; по умолчанию: rd_raw_orb
  &p_db_cdmr                 - схема связей анкеты с RK; по умолчанию: dm_pik_fd_cdmr
  &p_quest_src_cd_kn_list     - шаблон ветки КН в исходном ETL; по умолчанию: '1376%'
  &p_quest_src_cd_kk_list     - шаблон ветки КК в исходном ETL; по умолчанию: '1383%'
  &p_quest_src_cd_ak_list     - шаблон ветки авто в исходном ETL; по умолчанию: '1388%'
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
p_quest_src_cd_*_list — один строковый шаблон LIKE на ветку, как в исходнике;
исторический суффикс _list у этих трёх параметров не означает IN-список.
&p_report_timestamp задаётся фиксированным значением один раз перед запуском,
чтобы все шаги использовали тот же момент отчёта, как и раньше.

ПОДТВЕРЖДЁННОЕ ПРАВИЛО: любой выделенный зелёным/жёлтым статус означает,
что верификация была пройдена. Флаг — наличие такого статуса КОГДА-ЛИБО
в доступной истории до report_dttm. Цвет не участвует в расчёте.
Все 20 выделенных статусов со скриншотов — значения по умолчанию списков
макропеременных в блоке 0.1. Дополнительные статусы добавлять в эти списки.

ЦЕПОЧКА АНКЕТ (восстановлена кредитная часть показанного tech_questionnaire_status):
  RAW -> очистка -> prt_tqs_questionnaire -> отдельные КК / КН / авто
  -> исходные status_name и все status_priority -> сдвиг совпавших дат КН/авто
  -> prt_tqs_questionnaire_all с application_num -> актуальные пары ID/RK из
  &p_db_cdmr.tech_questionnaire_x_customer -> LEAD интервалов статусов
  -> prt_qas_tech_questionnaire_status (все атрибуты TQS + application_num)
  -> верификация по истории -> текущая анкета и ВСЕ номера -> BDM/TAS.

level25_product_bp_nm присваивается константой ВНУТРИ продуктовой ветки,
как на скриншотах: исходный src_cd_src LIKE ... OR product_type_code IN (...).
Для КН также сохранено NOT LIKE источника КК, для КК — ограничение длины ID.
Это восстановление исходной маршрутизации, а не предположение «источник = продукт».
В последующей верификации/соединениях q.src_cd не фильтруется: только level25.
В TQS src_cd = RAW.src_cd_src, как в исходном UNION; RAW.src_cd сохранён отдельно.
При пересечении веток строки не выбрасываются; есть отдельный контроль маршрутизации.
ДК/депозиты/текущие счета в задачу трёх кредитных продуктов не включены.

questionnaire_rk НЕ генерируется: берётся из актуальных distinct ID/RK связей,
как в конце исходного ETL. Несколько клиентов на одинаковой паре не размножают
строки. Несколько РАЗНЫХ RK не сворачиваются в MIN; все сохраняются и проверяются.
Отличие от исходного INNER JOIN: LEFT JOIN сохраняет анкету без RK с NULL и
диагностикой. Без этого не выполняется требование сохранить несвязанные анкеты.
q_entity_id — только технический номер пересборки, не заменяет настоящий RK.

Сохранены полный видимый ORDER BY очистки, обе исходные даты, 47 приоритетов
КН, 186 приоритетов авто и 187 для NULL, исходные CASE status_name.
Сдвиг одинаковых времён для КН/авто и LEAD воспроизводят показанную цепочку.
EXTRACT(SECONDS FROM interval) оставлен как в исходнике (это компонент секунд,
не полная длительность); его ограничения и неположительные интервалы диагностируются.
В LEAD добавлены критерии при равных временах, чтобы результат был повторяемым.
Вместо MAX_DATE по одной текущей строке берётся версия, действующая в report_dttm.

Обработка грязных данных сохранена с явными защитами: NOT LIKE ANY заменён
исключением совпадения с любым тестовым шаблоном; даты проверяются до CAST;
NULL/пустые ID не склеиваются; строки после report_dttm отбраковываются.
Верификация — по доступной истории ДО текущего среза; в ней сохранены номера
всех переживших исходную дедупликацию статусов. Флаг считается по RK + продукту,
для ещё не сопоставленного ID — по ID + продукту, без объединения разных NULL ID.

Итоговые поля уровня 25/35 берутся из TAS; level25 при NULL дополняется из анкеты.
Для анкеты без TAS level35 остаётся NULL: в показанном TQS такого атрибута нет.
Требуется справочник/правило уровня 35, если он должен заполняться для таких строк.
processed_dttm — единый момент текущей загрузки, приведённый к timestamp(0).
Информация вне 19 бизнес-полей остаётся в detail и промежуточных таблицах.

TAS предполагается актуальным снимком: подтверждённого поля окончания версии
в её DDL нет. processed_dttm не заменяет фильтр актуальности.

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

-- 1.6. Исходные условия продуктовых веток; ни одна строка пока не удаляется.
drop table if exists &db_sbx.prt_tqs_questionnaire_routing;
create table &db_sbx.prt_tqs_questionnaire_routing
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
    case when (q.src_cd_src like &p_quest_src_cd_kn_list
                    or q.product_type_code in (&p_quest_product_kn_list))
               and q.src_cd_src not like &p_quest_src_cd_kk_list then 1 else 0 end as is_kn,
    case when q.src_cd_src like &p_quest_src_cd_kk_list
               or q.product_type_code in (&p_quest_product_kk_list) then 1 else 0 end as is_kk,
    case when q.src_cd_src like &p_quest_src_cd_ak_list
               or q.product_type_code in (&p_quest_product_ak_list) then 1 else 0 end as is_auto
from &db_sbx.prt_tqs_questionnaire q
distributed randomly;

-- 1.7. Ветка KK: исходные status_name/приоритеты, продукт-константа; application_num сохранён.
drop table if exists &db_sbx.prt_tqs_kk_questionnaire;
create table &db_sbx.prt_tqs_kk_questionnaire
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    r.source_row_id,
    r.application_num,
    r.questionnaire_id,
    r.questionnaire_dttm,
    r.utmcn as utmcn_info,
    r.utmcmd as utmcmd_info,
    r.utmcsr as utmcsr_info,
    r.utmctr as utmctr_info,
    r.utmcct as utmcct_info,
    r.status as status_cd,
    r.scoring_status_nm,
    r.prescoring_status_nm,
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
        else coalesce(r.status, 'Не определено') end as status_name,
    r.program_type,
    r.src_cd as raw_src_cd,
    r.src_cd_src as src_cd,
    cast(&p_prod_kk_name as text) as level25_product_bp_nm,
    cast('KK' as text) as product_branch,
    cast(null as integer) as status_priority,
    r.original_effective_from_dttm_kk_dk as original_effective_from_dttm,
    r.original_effective_from_dttm_auto_kn,
    r.original_effective_from_dttm_kk_dk,
    r.status_observed_dttm
from &db_sbx.prt_tqs_questionnaire_routing r
where r.is_kk = 1
  and length(r.questionnaire_id) not in (&p_quest_not_len_id_kk_list)
distributed randomly;

-- 1.8. Ветка KN: исходные status_name/приоритеты, продукт-константа; application_num сохранён.
drop table if exists &db_sbx.prt_tqs_kn_questionnaire;
create table &db_sbx.prt_tqs_kn_questionnaire
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    r.source_row_id,
    r.application_num,
    r.questionnaire_id,
    r.questionnaire_dttm,
    r.utmcn as utmcn_info,
    r.utmcmd as utmcmd_info,
    r.utmcsr as utmcsr_info,
    r.utmctr as utmctr_info,
    r.utmcct as utmcct_info,
    r.status as status_cd,
    r.scoring_status_nm,
    r.prescoring_status_nm,
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
        else coalesce(r.status, 'Не определено') end as status_name,
    r.program_type,
    r.src_cd as raw_src_cd,
    r.src_cd_src as src_cd,
    cast(&p_prod_kn_name as text) as level25_product_bp_nm,
    cast('KN' as text) as product_branch,
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
    r.original_effective_from_dttm_auto_kn as original_effective_from_dttm,
    r.original_effective_from_dttm_auto_kn,
    r.original_effective_from_dttm_kk_dk,
    r.status_observed_dttm
from &db_sbx.prt_tqs_questionnaire_routing r
where r.is_kn = 1
distributed randomly;

-- 1.9. Ветка AUTO: исходные status_name/приоритеты, продукт-константа; application_num сохранён.
drop table if exists &db_sbx.prt_tqs_auto_questionnaire;
create table &db_sbx.prt_tqs_auto_questionnaire
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    r.source_row_id,
    r.application_num,
    r.questionnaire_id,
    r.questionnaire_dttm,
    r.utmcn as utmcn_info,
    r.utmcmd as utmcmd_info,
    r.utmcsr as utmcsr_info,
    r.utmctr as utmctr_info,
    r.utmcct as utmcct_info,
    r.status as status_cd,
    r.scoring_status_nm,
    r.prescoring_status_nm,
    r.product_type_code as product_type_cd,
    case
        when r.status in ('OFFER_EXPIRED', 'OFFER_CLOSED', 'OFFER_CLOSED_END', 'OFFER_EXPIRED_ERROR') then 'Анкета в архиве'
        when r.status in ('ANTIFRAUD_REVIEW') then 'Антифрод'
        when r.status in ('ERROR_BL_CHECK') then 'В процессе комплексной проверки ожидается ручная обработка нефатальной ошибки'
        when r.status in ('CALCULATED', 'DOCUMENTS_CREATED', 'DOCUMENTS_SIGNED', 'DOCUMENTS_VIEWED', 'DOCUMENTS_CREATED_DS', 'CALCULATOR', 'CLIENT_DENIED', 'DS_SIGNED_TIMEOUT', 'EFS_SIGNED_SUCCESS', 'TESSA_ORDER_COMPLETE', 'DOCUMENTS_SIGNING_OPERATION_CREATED_SUCCESS', 'MASTER_ACCOUNT_ERROR', 'DOCUMENTS_SIGNED_SUCCESS', 'INITIATION_MDM_START', 'INITIATION_MDM_SUCCESS', 'DS_COD_IN_PROGRESS', 'DS_SIGNED_TIMEOUT_DEAL', 'DS_EFS_IN_PROGRESS', 'CAR_AMOUNT_CHANGED', 'ANTIFRAUD_SUCCESS', 'EFS_SIGNING_OPERATION_CREATED_SUCCESS', 'AUTO_INFO', 'EFS_CREATED_DS', 'DEALER_SELECTED', 'DOCUMENTS_CREATED_DS') then 'В работе'
        when r.status in ('TESSA_VER', 'DEAL_VER') then 'Верификация'
        when r.status in ('TESSA_VER_REVISION', 'TESSA_VER_ERROR', 'ORDER_CREATED_ERROR', 'TESSA_VER_TIMEOUT', 'DOSSIER_UPLOADED_ERROR') then 'Верификация не пройдена'
        when r.status in ('ORDER_CREATED', 'DOSSIER_UPLOADED', 'CREDIT_ISSUED', 'TESSA_VER_COMPLETE', 'DRIVER_CARD_ISSUE_UPLOADED', 'DRIVER_CARD_ISSUE') then 'Выдача'
        when r.status in ('HARD_DECLINE') then 'Жесткий отказ'
        when r.status in ('DS_SIGNED_ERROR_TECH', 'DS_SIGNED_ERROR') then 'Завершить оформление'
        when r.status in ('CLIENT_DENIED_END', 'PEOPLE_CARD_DATA_NOT_MATCH', 'CONTRACT_CANCEL_TIMEOUT', 'COMPLEX_ERROR', 'COMPLEX_REQUEST_DENY', 'COMPLEX_TECH_DENY', 'EFS_CREATED_ERROR', 'RCC_DENY_TECHNICAL_PROFILE') then 'Закрыта'
        when r.status in ('AUTOTEKA_REQUEST') then 'Запрос в Автотеку'
        when r.status in ('DECLINE_CALL2_BZK_IP') then 'Клиент не соответствует условиям программы'
        when r.status in ('LIMIT_PSK_SUCCESS', 'NO_CONSENT_FORM', 'NEED_DOCUMENTS_SIGN') then 'На доработку'
        when r.status in ('SCORING', 'BL_CHECK_SUCCESS', 'RECEIVED', 'CONDITIONS_SELECTED', 'SIGNED', 'BL_CHECK_AUTO_ABR', 'COMPLEX_ARBITRAGE_ABR') then 'На проверке'
        when r.status in ('UNDERWRITING') then 'На проверке риск-менеджером'
        when r.status in ('BL_CHECK', 'APPROVE_CALL0_CHECKED') then 'На рассмотрении'
        when r.status in ('DATA_CORRECTION_WAITING') then 'Корректировка данных (ожидание)'
        when r.status in ('NEED_PHYSICAL_APPROVE') then 'Необходим визит в ТП'
        when r.status in ('ACCEPT_VEHICLE') then 'Одобрение по транспортному средству'
        when r.status in ('APPROVE_CALL2', 'PRE_APPROVED', 'APPROVED', 'APPROVE_RKK', 'APPROVE_CALL3', 'APPROVE') then 'Одобрено'
        when r.status in ('PRODUCT_BASKET_SIGNED') then 'Ожидает зачисления'
        when r.status in ('DECLINE_CALL2_SOFT', 'DECLINE_CALL2_HARD', 'DECLINE_CALL0_MORATOR', 'DECLINE_CALL0_MIN_REQUIREMENTS', 'DECLINE_CALL3_HARD', 'DECLINE_CALL3_SOFT', 'DECLINE_CALL0_PASSPORT', 'DECLINE_BL_CHECK', 'DECLINE_UNEMPLOYED', 'RCC_DENIED_SOFT', 'DECLINE_CALL2_NO_AGREEMENTS', 'RCC_DENIED', 'DECLINE_FORBIDDEN_REGIONS') then 'Отказ'
        when r.status in ('LIMIT_PSK_CRITICAL', 'ANTIFRAUD_DENY', 'LIABILITY_DENIED', 'DECLINE_VISUAL_CHECK') then 'Отказ банка'
        when r.status in ('CLIENT_DENIED_FINISH', 'DS_CLIENT_DENIED', 'CONTRACT_DELETED', 'RESTART_DENY', 'RESTART_EXPIRED') then 'Отказ по инициативе клиента'
        when r.status in ('DECLINE_BY_PRODUCT_PARAM') then 'Отказ по параметрам продукта'
        when r.status in ('TO_BE_DELETED', 'SPM_CHECK', 'SPM_SUCCESS', 'CONTRACT_CREATED', 'PRODUCT_BASKET_START', 'PRODUCT_BASKET_CREATED', 'SPM_DECLINE', 'PRODUCT_BASKET_DENIED', 'PRODUCT_BASKET_TIMEOUT', 'SIGN_WAY_NEEDED', 'ERROR_ONBOARD', 'CONTRACT_EXPIRED_ERROR', 'RCC_MISMATCH_GP', 'TESSA_TECH_ERROR', 'SPM_ERROR', 'CONTRACT_ERROR_TIMEOUT', 'INCORRECT_PAYMENT_DETAILS', 'CREATE_TRNS_PLAN_ERROR', 'CONTRACT_DENY_ERROR', 'PRODUCT_BASKET_ERROR', 'SUA_ID_SEARCH_ERROR', 'PRODUCT_BASKET_CRITICAL', 'INSURANCE_POLICY_CREATED_ERROR', 'ORDER_CREATED_ERROR_TIMEOUT', 'COMPLEX_REQUEST_TECH_ERROR', 'DRIVER_CARD_ISSUE_UPLOAD_ERROR', 'PRODUCT_BASKET_UNKNOWN', 'TAX_CODE_SEARCH_ERROR', 'SPM_ERROR_FATAL', 'LIMIT_PSK_ERROR', 'DECLINE_CALL0_TECH', 'EFS_UPLOAD_ERROR', 'CLIENT_DENIED_ERROR', 'INITIATION_MDM_ERROR') then 'Ошибка'
        when r.status in ('AUTOTEKA_ERROR') then 'Ошибка при запросе в Автотеку'
        when r.status in ('INVALID_DATA', 'ERROR_CALL0', 'CONTRACT_ERROR', 'ERROR_FATAL', 'ERROR_CALL3', 'INITIATION_CALL2', 'TESSA_VER_REJECT', 'RCC_CORRECT_PLEDGE', 'RCC_CALL6_ERROR', 'RCC_RETRY', 'ACCOUNT_BLOCKED', 'RCC_CORRECT_RETRY', 'RCC_PROCESSING_SUPPORT', 'RCC_CALL5_ERROR', 'DOCUMENTS_CREATED_ERROR', 'ERROR_CALL3', 'ANTIFRAUD_ERROR', 'CAR_OVERPRICED', 'RCC_CALL4_ERROR', 'RCC_CORRECT_PLEDGE_AND_SELLER', 'ERROR_APPROVED', 'PEOPLE_CARD_DATA_ERROR', 'RCC_CORRECT_SELLER', 'COMPLEX_REQUEST_TIMEOUT_ERROR', 'SFR_ERROR_UNC_UNDEFINED', 'RCC_DENY_TECHNICAL', 'CAR_AMOUNT_CHANGED_CRITICAL') then 'Проверка не пройдена'
        when r.status in ('CORRECTION_CALL3') then 'Проверка риск-менеджером не пройдена'
        when r.status in ('DECLINE_CALL2_TECH') then 'Технический отказ на call2'
        when r.status in ('DECLINE_CALL3_TECH') then 'Технический отказ на call3'
        when r.status in ('ERROR_FATAL_AUTOTEKA') then 'Фатальная ошибка при запросе в Автотеку'
        when r.status in ('BL_ERROR_FATAL') then 'Фатальная ошибка при обращении к ОС Комплексные проверки /ОС Комплаенс через сервис alpp-cmn-checks'
        when r.status in ('EFS_UPLOAD_TRANSFER_SUCCESS', 'HASH_EFS_SUCCESS', 'EFS_UPLOAD_SUCCESS', 'COMPLEX_SUCCESS', 'EFS_UPLOAD_TRANSFER_ERROR') then 'Формирование КОД'
        when r.status in ('APPROVE_CALL0', 'DRAFT', 'FROZEN', 'PRESCORING') then 'Черновик'
        else coalesce(r.status, 'Не определено') end as status_name,
    r.program_type,
    r.src_cd as raw_src_cd,
    r.src_cd_src as src_cd,
    cast(&p_prod_auto_name as text) as level25_product_bp_nm,
    cast('AUTO' as text) as product_branch,
    case when r.status is null then 187 else case r.status
        when 'ISSUANCE_STATUS_TIMEOUT' then 1
        when 'INCORRECT_PAYMENT_DETAILS' then 2
        when 'ANTIFRAUD_REVIEW' then 3
        when 'ERROR_ONBOARD' then 4
        when 'DEAL_VER' then 5
        when 'INITIATION_MDM_NO_CLIENT' then 6
        when 'INITIATION_MDM_START' then 7
        when 'AFL_OPERATION_CREATED_SUCCESS' then 8
        when 'TESSA_ORDER_COMPLETE' then 9
        when 'APPROVE_RKK' then 10
        when 'DECLINE_BY_PRODUCT_PARAM' then 11
        when 'DS_AFL_IN_PROGRESS' then 12
        when 'TESSA_ORDER_REJECT' then 13
        when 'DECLINE_UNEMPLOYED' then 14
        when 'CREATE_TRNS_PLAN_ERROR' then 15
        when 'AFL_ORDER_ERROR_CRIT' then 16
        when 'INITIATION_MDM_SUCCESS' then 17
        when 'DS_COD_IN_PROGRESS' then 18
        when 'EFS_SIGNED_SUCCESS' then 19
        when 'CONTRACT_CREATED' then 20
        when 'DOCUMENTS_SIGNED' then 21
        when 'EFS_SIGNING_OPERATION_CREATED_SUCCESS' then 22
        when 'CLIENT_DENIED' then 23
        when 'CLIENT_DENIED_FINISH' then 24
        when 'DOCUMENTS_SIGNING_OPERATION_CREATED_SUCCESS' then 25
        when 'DS_EFS_IN_PROGRESS' then 26
        when 'DS_SIGNED_TIMEOUT_DEAL' then 27
        when 'MASTER_ACCOUNT_ERROR' then 28
        when 'DOCUMENTS_VIEWED' then 29
        when 'ANTIFRAUD_SUCCESS' then 30
        when 'DS_SIGNED_TIMEOUT' then 31
        when 'CALCULATOR' then 32
        when 'CALCULATED' then 33
        when 'DOCUMENTS_CREATED' then 34
        when 'CAR_AMOUNT_CHANGED' then 35
        when 'DOCUMENTS_CREATED_DS' then 36
        when 'OFFER_CLOSED' then 37
        when 'OFFER_EXPIRED' then 38
        when 'OFFER_CLOSED_END' then 39
        when 'TESSA_VER' then 40
        when 'TESSA_VER_REVISION' then 41
        when 'TESSA_VER_TIMEOUT' then 42
        when 'ORDER_CREATED_ERROR' then 43
        when 'TESSA_VER_ERROR' then 44
        when 'DOSSIER_UPLOADED_ERROR' then 45
        when 'FROZEN' then 46
        when 'DRAFT' then 47
        when 'APPROVE_CALL0' then 48
        when 'PRESCORING' then 49
        when 'LIMIT_PSK_SUCCESS' then 50
        when 'NEED_DOCUMENTS_SIGN' then 51
        when 'NO_CONSENT_FORM' then 52
        when 'APPROVE_CALL0_CHECKED' then 53
        when 'BL_CHECK' then 54
        when 'SCORING' then 55
        when 'CONDITIONS_SELECTED' then 56
        when 'BL_CHECK_AUTO_ABR' then 57
        when 'RECEIVED' then 58
        when 'BL_CHECK_SUCCESS' then 59
        when 'SIGNED' then 60
        when 'UNDERWRITING' then 61
        when 'RCC_CALL5_ERROR' then 62
        when 'PEOPLE_CARD_DATA_ERROR' then 63
        when 'ERROR_CALL3' then 64
        when 'RCC_DENY_TECHNICAL' then 65
        when 'CONTRACT_ERROR' then 66
        when 'INVALID_DATA' then 67
        when 'ERROR_FATAL' then 68
        when 'DOCUMENTS_CREATED_ERROR' then 69
        when 'RCC_CORRECT_RETRY' then 70
        when 'ERROR_CALL2' then 71
        when 'ERROR_CALL0' then 72
        when 'TESSA_VER_REJECT' then 73
        when 'RCC_CORRECT_PLEDGE_AND_SELLER' then 74
        when 'COMPLEX_REQUEST_TIMEOUT_ERROR' then 75
        when 'ACCOUNT_BLOCKED' then 76
        when 'RCC_CALL6_ERROR' then 77
        when 'RCC_RETRY' then 78
        when 'RCC_CALL4_ERROR' then 79
        when 'CAR_OVERPRICED' then 80
        when 'RCC_CORRECT_PLEDGE' then 81
        when 'CORRECTION_CALL2' then 82
        when 'RCC_PROCESSING_SUPPORT' then 83
        when 'ERROR_APPROVED' then 84
        when 'ANTIFRAUD_ERROR' then 85
        when 'CORRECTION_CALL3' then 86
        when 'CONTRACT_EXPIRED_ERROR' then 87
        when 'PRODUCT_BASKET_DENIED' then 88
        when 'DRIVER_CARD_ISSUE_UPLOAD_ERROR' then 89
        when 'PRODUCT_BASKET_TIMEOUT' then 90
        when 'ORDER_CREATED_ERROR_TIMEOUT' then 91
        when 'PRODUCT_BASKET_ERROR' then 92
        when 'PRODUCT_BASKET_CREATED' then 93
        when 'LIMIT_PSK_ERROR' then 94
        when 'CONTRACT_ERROR_TIMEOUT' then 95
        when 'CONTRACT_DENY_ERROR' then 96
        when 'TESSA_TECH_ERROR' then 97
        when 'SIGN_WAY_NEEDED' then 98
        when 'PRODUCT_BASKET_UNKNOWN' then 99
        when 'TO_BE_DELETED' then 100
        when 'PRODUCT_BASKET_CRITICAL' then 101
        when 'PRODUCT_BASKET_START' then 102
        when 'INSURANCE_POLICY_CREATED_ERROR' then 103
        when 'SPM_ERROR' then 104
        when 'SPM_DECLINE' then 105
        when 'SPM_SUCCESS' then 106
        when 'SUA_ID_SEARCH_ERROR' then 107
        when 'CONTRACT_CANCEL_TIMEOUT' then 108
        when 'RCC_MISMATCH_GP' then 109
        when 'SPM_CHECK' then 110
        when 'NEED_PHYSICAL_APPROVE' then 111
        when 'DS_SIGNED_ERROR_TECH' then 112
        when 'DS_SIGNED_ERROR' then 113
        when 'BL_ERROR_FATAL' then 114
        when 'AUTOTEKA_REQUEST' then 115
        when 'ERROR_BL_CHECK' then 116
        when 'EFS_UPLOAD_TRANSFER_SUCCESS' then 117
        when 'EFS_UPLOAD_SUCCESS' then 118
        when 'COMPLEX_SUCCESS' then 119
        when 'HASH_EFS_SUCCESS' then 120
        when 'EFS_UPLOAD_TRANSFER_ERROR' then 121
        when 'DECLINE_VEHICLE' then 122
        when 'CONTRACT_DELETED' then 123
        when 'DS_CLIENT_DENIED' then 124
        when 'RESTART_DENY' then 125
        when 'DECLINE_CALL3_SOFT' then 126
        when 'DECLINE_CALL2_SOFT' then 127
        when 'DECLINE_CALL0_MORATOR' then 128
        when 'DECLINE_CALL0_PASSPORT' then 129
        when 'RCC_DENIED' then 130
        when 'RCC_DENIED_SOFT' then 131
        when 'DECLINE_CALL0_MIN_REQUIREMENTS' then 132
        when 'DECLINE_BL_CHECK' then 133
        when 'DECLINE_CALL2_NO_AGREEMENTS' then 134
        when 'DECLINE_CALL3_HARD' then 135
        when 'DECLINE_CALL2_HARD' then 136
        when 'LIABILITY_DENIED' then 137
        when 'DECLINE_VISUAL_CHECK' then 138
        when 'ANTIFRAUD_DENY' then 139
        when 'LIMIT_PSK_CRITICAL' then 140
        when 'DECLINE_CALL2_TECH' then 141
        when 'ACCEPT_VEHICLE' then 142
        when 'APPROVE' then 143
        when 'APPROVE_CALL3' then 144
        when 'APPROVE_CALL2' then 145
        when 'PRE_APPROVED' then 146
        when 'APPROVED' then 147
        when 'PRODUCT_BASKET_SIGNED' then 148
        when 'DOSSIER_UPLOADED' then 149
        when 'CREDIT_ISSUED' then 150
        when 'ORDER_CREATED' then 151
        when 'TESSA_VER_COMPLETE' then 152
        when 'DRIVER_CARD_ISSUE_UPLOADED' then 153
        when 'DRIVER_CARD_ISSUE' then 154
        when 'CLIENT_DENIED_END' then 155
        when 'COMPLEX_ERROR' then 156
        when 'RCC_DENY_TECHNICAL_PROFILE' then 157
        when 'PEOPLE_CARD_DATA_NOT_MATCH' then 158
        when 'DOCUMENTS_SIGNED_SUCCESS' then 159
        when 'DEAL_EXECUTION_DELAY' then 160
        when 'AFL_ORDER_SIGNED' then 161
        when 'PTI_CHANGED' then 162
        when 'DECISION_EXPIRED_SELFLOCK' then 163
        when 'AFL_ORDER_TIMEOUT' then 164
        when 'TAX_CODE_SEARCH_ERROR' then 165
        when 'DECISION_EXPIRED_NOT_RECEIVED_INN' then 166
        when 'AFL_READY_CONFIRMATION' then 167
        when 'RCC_FORBIDDEN' then 168
        when 'COMPLEX_REQUEST_DENY' then 169
        when 'RCC_CORRECT_SELLER' then 170
        when 'EFS_CREATED_ERROR' then 171
        when 'COMPLEX_TECH_DENY' then 172
        when 'INITIATION_MDM_NO_UNK' then 173
        when 'DECLINE_FORBIDDEN_REGIONS' then 174
        when 'SPM_ERROR_FATAL' then 175
        when 'COMPLEX_REQUEST_TECH_ERROR' then 176
        when 'PTI_UPDATE_ERROR' then 177
        when 'DECLINE_CALL0_TECH' then 178
        when 'AFL_ORDER_REJECT' then 179
        when 'RCC_FORBIDDEN_NOT_FOUND' then 180
        when 'SEARCH_EFS' then 181
        when 'HASH_EFS_TECH_ERROR' then 182
        when 'INITIATION_MDM_ERROR' then 183
        when 'RCC_FORBIDDEN_ONLINE' then 184
        when 'AUTOTEKA_ERROR' then 185
        when 'ERROR_FATAL_AUTOTEKA' then 186
        else null end end as status_priority,
    r.original_effective_from_dttm_auto_kn as original_effective_from_dttm,
    r.original_effective_from_dttm_auto_kn,
    r.original_effective_from_dttm_kk_dk,
    r.status_observed_dttm
from &db_sbx.prt_tqs_questionnaire_routing r
where r.is_auto = 1
distributed randomly;

-- 1.10. КН/авто: исходный LAG/COUNT для совпадающих времён статусов.
drop table if exists &db_sbx.prt_tqs_kn_auto_pre_eff_calc;
create table &db_sbx.prt_tqs_kn_auto_pre_eff_calc
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
with kn_auto as (
select
    k.source_row_id,
    k.application_num,
    k.questionnaire_id,
    k.questionnaire_dttm,
    k.utmcn_info,
    k.utmcmd_info,
    k.utmcsr_info,
    k.utmctr_info,
    k.utmcct_info,
    k.status_cd,
    k.scoring_status_nm,
    k.prescoring_status_nm,
    k.product_type_cd,
    k.status_name,
    k.program_type,
    k.raw_src_cd,
    k.src_cd,
    k.level25_product_bp_nm,
    k.product_branch,
    k.status_priority,
    k.original_effective_from_dttm,
    k.original_effective_from_dttm_auto_kn,
    k.original_effective_from_dttm_kk_dk,
    k.status_observed_dttm
from &db_sbx.prt_tqs_kn_questionnaire k
union all
select
    a.source_row_id,
    a.application_num,
    a.questionnaire_id,
    a.questionnaire_dttm,
    a.utmcn_info,
    a.utmcmd_info,
    a.utmcsr_info,
    a.utmctr_info,
    a.utmcct_info,
    a.status_cd,
    a.scoring_status_nm,
    a.prescoring_status_nm,
    a.product_type_cd,
    a.status_name,
    a.program_type,
    a.raw_src_cd,
    a.src_cd,
    a.level25_product_bp_nm,
    a.product_branch,
    a.status_priority,
    a.original_effective_from_dttm,
    a.original_effective_from_dttm_auto_kn,
    a.original_effective_from_dttm_kk_dk,
    a.status_observed_dttm
from &db_sbx.prt_tqs_auto_questionnaire a
)
select
    source_row_id,
    application_num,
    questionnaire_id,
    questionnaire_dttm,
    utmcn_info,
    utmcmd_info,
    utmcsr_info,
    utmctr_info,
    utmcct_info,
    status_cd,
    scoring_status_nm,
    prescoring_status_nm,
    product_type_cd,
    status_name,
    program_type,
    raw_src_cd,
    src_cd,
    level25_product_bp_nm,
    product_branch,
    status_priority,
    original_effective_from_dttm,
    original_effective_from_dttm_auto_kn,
    original_effective_from_dttm_kk_dk,
    status_observed_dttm,
    coalesce(extract(seconds from (original_effective_from_dttm -
        lag(original_effective_from_dttm) over (partition by questionnaire_id, case when nullif(btrim(questionnaire_id), '') is null then source_row_id else null end order by original_effective_from_dttm, status_priority, case when status_priority is null and level25_product_bp_nm = cast(&p_prod_auto_name as text) then status_name else '1' end asc))), 1) as diff_sec,
    count(*) over (partition by questionnaire_id, case when nullif(btrim(questionnaire_id), '') is null then source_row_id else null end, original_effective_from_dttm
        order by status_priority, case when status_priority is null and level25_product_bp_nm = cast(&p_prod_auto_name as text) then status_name else '1' end asc) as count_eq_ef,
    count(*) over (partition by questionnaire_id, case when nullif(btrim(questionnaire_id), '') is null then source_row_id else null end, original_effective_from_dttm) as count_eq_ef_not_ordered,
    extract(epoch from (original_effective_from_dttm -
        lag(original_effective_from_dttm) over (partition by questionnaire_id, case when nullif(btrim(questionnaire_id), '') is null then source_row_id else null end order by original_effective_from_dttm, status_priority, case when status_priority is null and level25_product_bp_nm = cast(&p_prod_auto_name as text) then status_name else '1' end asc))) as full_diff_seconds
from kn_auto
distributed randomly;

-- 1.11. КН/авто: сдвиг на секунды по исходной формуле, без потери номера.
drop table if exists &db_sbx.prt_tqs_kn_auto_questionnaire;
create table &db_sbx.prt_tqs_kn_auto_questionnaire
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    source_row_id,
    application_num,
    questionnaire_id,
    questionnaire_dttm,
    utmcn_info,
    utmcmd_info,
    utmcsr_info,
    utmctr_info,
    utmcct_info,
    status_cd,
    scoring_status_nm,
    prescoring_status_nm,
    product_type_cd,
    status_name,
    program_type,
    raw_src_cd,
    src_cd,
    level25_product_bp_nm,
    product_branch,
    status_priority,
    original_effective_from_dttm,
    original_effective_from_dttm_auto_kn,
    original_effective_from_dttm_kk_dk,
    status_observed_dttm,
    case when diff_sec = 0 then original_effective_from_dttm + (count_eq_ef - 1) * interval '1 second'
         when diff_sec > 0 and coalesce(lag(count_eq_ef_not_ordered) over
                (partition by questionnaire_id, case when nullif(btrim(questionnaire_id), '') is null then source_row_id else null end order by original_effective_from_dttm, status_priority), 0) >= diff_sec
         then original_effective_from_dttm + (lag(count_eq_ef_not_ordered) over
                (partition by questionnaire_id, case when nullif(btrim(questionnaire_id), '') is null then source_row_id else null end order by original_effective_from_dttm, status_priority) - diff_sec) * interval '1 second'
         else original_effective_from_dttm end as effective_from_dttm
from &db_sbx.prt_tqs_kn_auto_pre_eff_calc
distributed randomly;

-- 1.12. Общая история трёх продуктов: все атрибуты исходного TQS и application_num.
drop table if exists &db_sbx.prt_tqs_questionnaire_all;
create table &db_sbx.prt_tqs_questionnaire_all
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    k.source_row_id,
    k.application_num,
    k.questionnaire_id,
    k.questionnaire_dttm,
    k.utmcn_info,
    k.utmcmd_info,
    k.utmcsr_info,
    k.utmctr_info,
    k.utmcct_info,
    k.status_cd,
    k.scoring_status_nm,
    k.prescoring_status_nm,
    k.product_type_cd,
    k.status_name,
    k.program_type,
    k.raw_src_cd,
    k.src_cd,
    k.level25_product_bp_nm,
    k.product_branch,
    k.status_priority,
    k.original_effective_from_dttm,
    k.original_effective_from_dttm_auto_kn,
    k.original_effective_from_dttm_kk_dk,
    k.status_observed_dttm,
    k.original_effective_from_dttm as effective_from_dttm
from &db_sbx.prt_tqs_kk_questionnaire k
union all
select
    a.source_row_id,
    a.application_num,
    a.questionnaire_id,
    a.questionnaire_dttm,
    a.utmcn_info,
    a.utmcmd_info,
    a.utmcsr_info,
    a.utmctr_info,
    a.utmcct_info,
    a.status_cd,
    a.scoring_status_nm,
    a.prescoring_status_nm,
    a.product_type_cd,
    a.status_name,
    a.program_type,
    a.raw_src_cd,
    a.src_cd,
    a.level25_product_bp_nm,
    a.product_branch,
    a.status_priority,
    a.original_effective_from_dttm,
    a.original_effective_from_dttm_auto_kn,
    a.original_effective_from_dttm_kk_dk,
    a.status_observed_dttm,
    a.effective_from_dttm
from &db_sbx.prt_tqs_kn_auto_questionnaire a
distributed randomly;

-- 1.13. Новый источник RK: актуальные уникальные пары ID/RK из связи анкета–клиент.
drop table if exists &db_sbx.prt_tqs_questionnaire_rk;
create table &db_sbx.prt_tqs_questionnaire_rk
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select distinct
    cast(x.questionnaire_id as text) as questionnaire_id,
    cast(x.questionnaire_rk as bigint) as questionnaire_rk
from &p_db_cdmr.tech_questionnaire_x_customer x
where x.effective_to_dttm = cast(&p_max_date as timestamp)
  and x.questionnaire_rk is not null and x.questionnaire_rk <> -1
  and nullif(btrim(x.questionnaire_id), '') is not null
distributed randomly;

-- 1.14. Присоединяем настоящий RK; анкеты без RK остаются, разные RK не схлопываем.
drop table if exists &db_sbx.prt_tqs_questionnaire_with_rk;
create table &db_sbx.prt_tqs_questionnaire_with_rk
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    m.questionnaire_rk,
    a.source_row_id,
    a.application_num,
    a.questionnaire_id,
    a.questionnaire_dttm,
    a.utmcn_info,
    a.utmcmd_info,
    a.utmcsr_info,
    a.utmctr_info,
    a.utmcct_info,
    a.status_cd,
    a.scoring_status_nm,
    a.prescoring_status_nm,
    a.product_type_cd,
    a.status_name,
    a.program_type,
    a.raw_src_cd,
    a.src_cd,
    a.level25_product_bp_nm,
    a.product_branch,
    a.status_priority,
    a.original_effective_from_dttm,
    a.original_effective_from_dttm_auto_kn,
    a.original_effective_from_dttm_kk_dk,
    a.status_observed_dttm,
    a.effective_from_dttm,
    coalesce(m.rk_mapping_count, 0) as rk_mapping_count
from &db_sbx.prt_tqs_questionnaire_all a
left join (
    select questionnaire_id, questionnaire_rk,
           count(*) over (partition by questionnaire_id) as rk_mapping_count
    from &db_sbx.prt_tqs_questionnaire_rk
) m on m.questionnaire_id = a.questionnaire_id
distributed randomly;

-- 1.15. Копия кредитной цепочки tech_questionnaire_status: LEAD интервалов + номер заявки.
drop table if exists &db_sbx.prt_qas_tech_questionnaire_status;
create table &db_sbx.prt_qas_tech_questionnaire_status
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    q.questionnaire_rk,
    q.source_row_id,
    q.application_num,
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
    q.raw_src_cd,
    q.src_cd,
    q.level25_product_bp_nm,
    q.product_branch,
    q.status_priority,
    q.original_effective_from_dttm,
    q.original_effective_from_dttm_auto_kn,
    q.original_effective_from_dttm_kk_dk,
    q.status_observed_dttm,
    q.effective_from_dttm,
    q.rk_mapping_count,
    cast(lead(q.effective_from_dttm, 1, cast(&p_max_date as timestamp)) over (
        partition by q.questionnaire_rk, case when q.questionnaire_rk is null then q.questionnaire_id else null end, case when q.questionnaire_rk is null then q.level25_product_bp_nm else null end, case when nullif(btrim(q.questionnaire_id), '') is null then q.source_row_id else null end
        order by q.effective_from_dttm, q.status_priority nulls last, q.status_name nulls last,
                 q.source_row_id, q.questionnaire_id
    ) as timestamp) as effective_to_dttm,
    cast(&p_report_timestamp as timestamp) as processed_dttm
from &db_sbx.prt_tqs_questionnaire_with_rk q
distributed randomly;

-- 1.16. Верификация и все номера по истории ДО выбора действующей версии.
drop table if exists &db_sbx.prt_tqs_questionnaire_verified;
create table &db_sbx.prt_tqs_questionnaire_verified
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    q.questionnaire_rk,
    q.source_row_id,
    q.application_num,
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
    q.raw_src_cd,
    q.src_cd,
    q.level25_product_bp_nm,
    q.product_branch,
    q.status_priority,
    q.original_effective_from_dttm,
    q.original_effective_from_dttm_auto_kn,
    q.original_effective_from_dttm_kk_dk,
    q.status_observed_dttm,
    q.effective_from_dttm,
    q.rk_mapping_count,
    q.effective_to_dttm,
    q.processed_dttm,
    case when nullif(btrim(q.questionnaire_id), '') is null then cast(null as boolean)
         else max(case
             when q.level25_product_bp_nm = cast(&p_prod_kn_name as text) and q.status_cd in (&p_kn_verification_status) then 1
             when q.level25_product_bp_nm = cast(&p_prod_kk_name as text) and q.status_cd in (&p_kk_verification_status) then 1
             when q.level25_product_bp_nm = cast(&p_prod_auto_name as text) and q.status_cd in (&p_auto_verification_status) then 1
             else 0 end) over (partition by q.questionnaire_rk, case when q.questionnaire_rk is null then q.questionnaire_id else null end, case when q.questionnaire_rk is null then q.level25_product_bp_nm else null end, case when nullif(btrim(q.questionnaire_id), '') is null then q.source_row_id else null end, q.level25_product_bp_nm) = 1 end as verification_flg,
    array_agg(q.application_num) over (partition by q.questionnaire_rk, case when q.questionnaire_rk is null then q.questionnaire_id else null end, case when q.questionnaire_rk is null then q.level25_product_bp_nm else null end, case when nullif(btrim(q.questionnaire_id), '') is null then q.source_row_id else null end, q.level25_product_bp_nm) as application_nums,
    count(*) over (partition by q.questionnaire_rk, case when q.questionnaire_rk is null then q.questionnaire_id else null end, case when q.questionnaire_rk is null then q.level25_product_bp_nm else null end, case when nullif(btrim(q.questionnaire_id), '') is null then q.source_row_id else null end, q.level25_product_bp_nm) as history_row_count,
    count(q.status_cd) over (partition by q.questionnaire_rk, case when q.questionnaire_rk is null then q.questionnaire_id else null end, case when q.questionnaire_rk is null then q.level25_product_bp_nm else null end, case when nullif(btrim(q.questionnaire_id), '') is null then q.source_row_id else null end, q.level25_product_bp_nm) as status_count
from &db_sbx.prt_qas_tech_questionnaire_status q
distributed randomly;

-- 1.17. Действующая версия анкеты с RK, верификацией и всеми номерами истории.
drop table if exists &db_sbx.prt_qas_questionnaire;
create table &db_sbx.prt_qas_questionnaire
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    row_number() over (order by q.questionnaire_rk, q.questionnaire_id, q.level25_product_bp_nm, q.source_row_id) as q_entity_id,
    q.questionnaire_id,
    q.questionnaire_rk,
    q.rk_mapping_count,
    q.application_num,
    q.application_nums,
    q.src_cd as q_src_cd,
    q.raw_src_cd,
    q.src_cd as src_cd_src,
    q.utmcn_info as utmcn,
    q.utmcmd_info as utmcmd,
    q.utmcsr_info as utmcsr,
    q.utmctr_info as utmctr,
    q.utmcct_info as utmcct,
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
    q.effective_to_dttm,
    q.status_observed_dttm,
    q.product_branch,
    1 as product_match_flg,
    q.history_row_count,
    case when nullif(btrim(q.questionnaire_id), '') is null then 0 else 1 end as id_count,
    q.status_count,
    q.verification_flg
from &db_sbx.prt_tqs_questionnaire_verified q
where q.effective_from_dttm <= cast(&p_report_timestamp as timestamp)
  and q.effective_to_dttm > cast(&p_report_timestamp as timestamp)
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
    q.questionnaire_rk,
    q.rk_mapping_count,
    q.application_num,
    q.application_nums,
    q.q_src_cd,
    q.raw_src_cd,
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
    q.effective_to_dttm,
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
    q.questionnaire_rk as q_questionnaire_rk,
    q.rk_mapping_count as q_rk_mapping_count,
    q.raw_src_cd as q_raw_src_cd,
    q.effective_to_dttm as q_effective_to_dttm,
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
    q.questionnaire_rk,
    q.rk_mapping_count,
    q.application_num,
    q.application_nums,
    q.q_src_cd,
    q.raw_src_cd,
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
    q.effective_to_dttm,
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
    q.questionnaire_rk as q_questionnaire_rk,
    q.rk_mapping_count as q_rk_mapping_count,
    q.raw_src_cd as q_raw_src_cd,
    q.effective_to_dttm as q_effective_to_dttm,
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

-- 4.1. Полный результат связей: все атрибуты и диагностика остаются в detail.
drop table if exists &db_sbx.prt_qas_funnel_detail;
create table &db_sbx.prt_qas_funnel_detail
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
    q_questionnaire_rk,
    q_rk_mapping_count,
    q_raw_src_cd,
    q_effective_to_dttm,
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
    q_questionnaire_rk,
    q_rk_mapping_count,
    q_raw_src_cd,
    q_effective_to_dttm,
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

-- 4.2. Целевая tech_internet_funnel: ровно 19 бизнес-атрибутов, явные типы.
drop table if exists &db_sbx.prt_tech_internet_funnel;
create table &db_sbx.prt_tech_internet_funnel
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    cast(q_questionnaire_rk as bigint) as questionnaire_rk,
    cast(q_questionnaire_dttm as timestamp) as questionnaire_dttm,
    cast(verification_flg as boolean) as quest_verification_flg,
    cast(tas_parent_application_rk as bigint) as parent_application_rk,
    cast(tas_parent_application_dt as date) as parent_application_dt,
    cast(tas_parent_open_flg as boolean) as parent_open_flg,
    cast(tas_parent_prescoring_flg as boolean) as parent_prescoring_flg,
    cast(tas_parent_at_work_flg as boolean) as parent_at_work_flg,
    cast(tas_parent_approved_flg as boolean) as parent_approved_flg,
    cast(tas_application_rk as bigint) as application_rk,
    cast(tas_application_dt as date) as application_dt,
    cast(tas_deal_issue_date as date) as deal_issue_date,
    cast(tas_create_flg as boolean) as create_flg,
    cast(tas_at_work_flg as boolean) as at_work_flg,
    cast(tas_final_approved_flg as boolean) as final_approved_flg,
    cast(tas_agr_signed_flg as boolean) as agr_signed_flg,
    cast(coalesce(tas_level25_product_bp_nm, q_level25_product_bp_nm) as text) as level25_product_bp_nm,
    cast(tas_level35_product_bp_nm as text) as level35_product_bp_nm,
    cast(&p_report_timestamp as timestamp(0)) as processed_dttm
from &db_sbx.prt_qas_funnel_detail
distributed randomly;

-- 4.3. Покрытие уникальных сущностей по веткам и общей базе; строки пары не знаменатель.
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
    from &db_sbx.prt_qas_funnel_detail group by product_branch
    union all
    select 'ALL', count(distinct q_entity_id),
           count(distinct case when record_type = 'MATCHED' then q_entity_id end),
           count(distinct tas_entity_id),
           count(distinct case when record_type = 'MATCHED' then tas_entity_id end)
    from &db_sbx.prt_qas_funnel_detail
)
select t.product_branch, t.q_total, t.q_matched,
       round(100.0 * t.q_matched / nullif(t.q_total, 0), 2) as q_coverage_pct,
       t.app_total, t.app_matched,
       round(100.0 * t.app_matched / nullif(t.app_total, 0), 2) as app_coverage_pct,
       round(100.0 * (t.q_matched + t.app_matched) / nullif(t.q_total + t.app_total, 0), 2) as entity_coverage_pct,
       cast(&p_min_coverage_pct as numeric) as reference_coverage_pct
from totals t
distributed randomly;

-- 4.4. Контроли сохранности/уникальности. Все error_count должны быть 0.
drop table if exists &db_sbx.prt_qas_checks;
create table &db_sbx.prt_qas_checks
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select cast('MISSING_QUESTIONNAIRES' as text) as check_name, count(*) as error_count
from &db_sbx.prt_qas_questionnaire q
where not exists (select 1 from &db_sbx.prt_qas_funnel_detail f where f.q_entity_id = q.q_entity_id)
union all
select 'MISSING_KN_KK_TAS', count(*) from &db_sbx.prt_qas_kn_kk_tas t
where not exists (select 1 from &db_sbx.prt_qas_funnel_detail f
                  where f.tas_entity_id = 'KN_KK:' || cast(t.app_entity_id as text))
union all
select 'MISSING_AUTO_TAS', count(*) from &db_sbx.prt_qas_auto_tas t
where not exists (select 1 from &db_sbx.prt_qas_funnel_detail f
                  where f.tas_entity_id = 'AUTO:' || cast(t.app_entity_id as text))
union all
select 'DUPLICATE_FINAL_PAIRS', count(*) from (
    select q_entity_id, tas_entity_id
    from &db_sbx.prt_qas_funnel_detail
    group by q_entity_id, tas_entity_id having count(*) > 1
) d
union all
select 'DUPLICATE_QUESTIONNAIRE_KEYS', count(*) from (
    select questionnaire_rk, questionnaire_id, level25_product_bp_nm from &db_sbx.prt_qas_questionnaire
    where nullif(btrim(questionnaire_id), '') is not null
    group by questionnaire_rk, questionnaire_id, level25_product_bp_nm having count(*) > 1
) d
union all
select 'INCONSISTENT_VERIFICATION_FLAGS', count(*) from (
    select q_entity_id from &db_sbx.prt_qas_funnel_detail
    where q_entity_id is not null
    group by q_entity_id having count(distinct verification_flg) > 1
) d
union all
select 'EMPTY_FINAL_ROWS', count(*) from &db_sbx.prt_qas_funnel_detail
where q_entity_id is null and tas_entity_id is null
union all
select 'FINAL_PROJECTION_ROW_COUNT_MISMATCH', abs(
    (select count(*) from &db_sbx.prt_qas_funnel_detail) -
    (select count(*) from &db_sbx.prt_tech_internet_funnel))
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
from &db_sbx.prt_qas_funnel_detail
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

-- Результат 4.10: отбраковка RAW и плохие даты, без персональных данных.
select source_filter_reason, count(*) as source_rows,
       sum(invalid_date_field_count) as invalid_date_fields
from &db_sbx.prt_tqs_questionnaire_checked
group by source_filter_reason order by source_filter_reason;

-- Результат 4.11: маршрутизация исходного ETL; пересечения и непройденные ветки.
select product_type_code, src_cd_src, is_kn, is_kk, is_auto, count(*) as source_rows
from &db_sbx.prt_tqs_questionnaire_routing
group by product_type_code, src_cd_src, is_kn, is_kk, is_auto
order by product_type_code, src_cd_src;

-- Результат 4.12: актуальный RK отсутствует либо один ID связан с несколькими RK.
select rk_mapping_count, count(*) as current_questionnaire_rows
from &db_sbx.prt_qas_questionnaire
group by rk_mapping_count order by rk_mapping_count;

-- Результат 4.13: одни ID/status и разные продукты до исходной дедупликации.
select count(*) as conflicting_product_groups
from (
    select questionnaire_id, status
    from &db_sbx.prt_tqs_questionnaire_checked
    where source_filter_reason = 'OK' and questionnaire_id is not null
    group by questionnaire_id, status having count(distinct product_type_code) > 1
) d;

-- Результат 4.14: ограничения исходной временной формулы, не скрываем проблемные интервалы.
select cast('NONPOSITIVE_TQS_INTERVALS' as text) as diagnostic, count(*) as row_count
from &db_sbx.prt_qas_tech_questionnaire_status where effective_to_dttm <= effective_from_dttm
union all
select 'SECONDS_COMPONENT_DIFFERS_FROM_DURATION', count(*)
from &db_sbx.prt_tqs_kn_auto_pre_eff_calc where full_diff_seconds <> diff_sec;

-- Результат 4.15: уровень 35 не выдумывается для анкеты без TAS; конфликт уровня 25 виден.
select record_type,
       sum(case when tas_level35_product_bp_nm is null then 1 else 0 end) as missing_level35_count,
       sum(case when q_level25_product_bp_nm is not null and tas_level25_product_bp_nm is not null
                     and q_level25_product_bp_nm <> tas_level25_product_bp_nm then 1 else 0 end) as level25_conflict_count
from &db_sbx.prt_qas_funnel_detail group by record_type order by record_type;

-- Результат 4.16: проекция не теряет ни одной строки подробного результата.
select (select count(*) from &db_sbx.prt_qas_funnel_detail) as detail_rows,
       (select count(*) from &db_sbx.prt_tech_internet_funnel) as final_rows;

-- Результат 4.17: RK связан с несколькими ID; историю объединяет исходный LEAD по RK.
select count(*) as rk_with_multiple_ids
from (
    select questionnaire_rk from &db_sbx.prt_tqs_questionnaire_rk
    group by questionnaire_rk having count(distinct questionnaire_id) > 1
) d;
