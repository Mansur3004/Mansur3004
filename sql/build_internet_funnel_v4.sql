/*
ПРОТОТИП V4. MISREP-4455 TECH_INTERNET_FUNNEL.
СРАВНЕНИЕ: скриншоты 0.png–13.png из последнего сообщения пользователя.
[ИЗМЕНЕНО] — изменённый блок/выражение относительно этого скрипта.
[НОВОЕ] — отдельный шаг или CTE, которого там не было.
[СОХРАНЕНО] — прежняя бизнес-логика; возможны переименования/форматирование.
«Старые строки» — номера на скриншотах, не номера строк этого V4.
Поиск пометок: [ИЗМЕНЕНО] и [НОВОЕ]. Карта: docs/v4_vs_screenshots.txt.
[ИЗМЕНЕНО] Шапка, старые строки 1–59: объект и заявка исправлены на TIF/MISREP-4455;
итог без истории версий; неиспользуемые параметры источников/режима связи удалены.
Актуальная версия по ФТ от 03.11.2026. Таблицы прототипа: man_prt_tif_.
Регламент целевого объекта: ежедневно после обновления источников;
начальное наполнение с 01.01.2025, далее пересчёт с начала прошлого квартала.
Итог без истории версий, реализация в dm_pik_fd_cdmr.
В прототипе результаты создаются в &db_sbx (по умолчанию sbx_pre_orb_fd).
КН/КК: копия кредитной части tech_questionnaire_status с application_num ->
верификация -> bdm.application -> tech_application_status.
Авто: готовая tech_questionnaire_status -> верификация -> tech_application_status.
Итог: &db_sbx.man_prt_tif_tech_internet_funnel, ровно 19 согласованных полей.
Все создаваемые таблицы имеют префикс man_prt_tif_; при запуске они пересоздаются.

Макропеременные (подстановка SQL-клиентом/ETL, как в исходных прототипах):
  &db_sbx                     - схема результатов; по умолчанию: sbx_pre_orb_fd
  &p_db_rawd                  - схема RAW; по умолчанию: rd_raw_orb
  &p_db_cdmr                  - схема TQS/TAS и связи с RK; по умолчанию: dm_pik_fd_cdmr
  &p_db_bdm                   - схема заявок BDM; по умолчанию: bdm
  &p_max_date                 - максимальная дата; по умолчанию: '2999-12-31'
  &p_min_dttm                 - замена NULL в сортировке; по умолчанию: '1900-01-01 00:00:00'
  &p_rds_report_dt_date       - начало выборки RAW, как в вашей копии TQS; по умолчанию: '2025-01-01'
  &P_BEGIN_DATE               - начало пересчитываемой выборки; начальное наполнение: '2025-01-01'
  &p_report_timestamp         - один момент этой загрузки; пример: '2026-11-03 00:00:00'

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

Регламент параметра P_BEGIN_DATE: первый запуск — '2025-01-01'; ежедневно —
GREATEST(DATE '2025-01-01', DATE_TRUNC('quarter', report_timestamp)::date - INTERVAL '3 months').
Параметр задаётся ETL/SQL-клиентом. Прототип пересоздаёт расчётную выборку в sbx;
загрузчик целевого объекта должен сохранять результат за пределами окна пересчёта.
Это не DELETE/INSERT целевой витрины dm_pik_fd_cdmr.

Имена схем задаются без кавычек; строки/даты — в одинарных кавычках;
списки — SQL-значения через запятую без внешних скобок; числа — без кавычек.

В 1.1 оставлены исходные CAST, WHERE, MIN и ROW_NUMBER в одном запросе.
Как на скриншотах, отбор КН/КК выполняется в ветках 1.2/1.3 после подготовки RAW.
Отдельных RAW/parsed/checked/ranked-таблиц нет. Исходные фильтры и формула
EXTRACT(SECONDS) здесь не исправляются и не дополняются новыми проверками.
TQS-цепочка копируется только для КН/КК; для авто RAW не используется.
Предварительный флаг — MAX(CASE ... THEN 1 ELSE 0 END) по ВСЕЙ истории.
Итоговый флаг: при найденной связи анкеты с TAS — true независимо от статусов;
для анкеты без заявки — исторический флаг; для заявки без анкеты — NULL.
Все три итоговых RK обязательны: отсутствующая сущность обозначается -1.
Значение -1 не считается существующей сущностью и не участвует в связях.
Статусы берутся из макросписков, соответствующих всем выделениям Excel.
Верификация/соединения анкет после назначения продукта не фильтруют q.src_cd.

В 1.6 INNER JOIN получает готовые RK из актуального среза TQS, а не TQXC. Поэтому базой КН/КК
являются анкеты, прошедшие исходный ETL TQS, включая наличие RK. Новые RK
не генерируются. Все номера переживших исходную дедупликацию статусов
сохраняются и участвуют в связи. Версии не отбрасываются до расчёта флага.

TAS хранит только последнее состояние заявки: изменения переписывают строку.
Временного JOIN с TAS нет; processed_dttm не используется как начало версии.
КН/КК и авто сохраняют несвязанные анкеты и заявки внутри своих когорт.
level25 берётся из TAS, при NULL — из анкеты. level35 берётся из собственного
поля TAS; если заявки или значения нет — NULL, как в ФТ 1.4.
Правки и ограничения: docs/prototype_v4_steps.txt.
КН/КК соединяются только по app.application_rk = tas.parent_application_rk
и app.src_cd = tas.parent_src_cd. Прямого пути на tas.application_rk больше нет.
Для авто флаг рассчитывается по всей истории TQS; ID для связи берётся
из текущего среза TQS после агрегации истории. Итог не хранит версии статусов.
DISTINCT сохранён только в исходном RAW-этапе 1.1. Далее агрегируются
номера/ключи связей, строки TAS и финальные атрибуты не дедуплицируются.
Проверки: sql/check_internet_funnel.sql. Каждый SELECT выполняется отдельно.
*/

-- ==================== 1. КН/КК: КОПИЯ TQS -> ФЛАГ -> ЗАЯВКА ====================

-- Шаг 1.1. Очистка и подгонка RAW, как в начале tech_questionnaire_status.
-- [СОХРАНЕНО] Старые строки 61–139: исходная очистка, MIN даты, ROW_NUMBER и DISTINCT.
-- [ИЗМЕНЕНО] Старый вывод строки 137 раскрыт явным списком полей; имена таблиц согласованы.
-- Откуда: исходный prt_tqs_questionnaire, скриншот строк 53–131.
-- Зачем: сохранить исходную очистку и MIN/ROW_NUMBER; продуктовые ветки ниже оставят только КН/КК.
-- Копирование: исходный prt_tqs_questionnaire; явно перечислить поля и сохранить src_cd_src и application_num.
drop table if exists &db_sbx.man_prt_tif_tqs_questionnaire;
create table &db_sbx.man_prt_tif_tqs_questionnaire
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
)
-- [ИЗМЕНЕНО] Старые строки 137–138: явная проекция вместо звёздочки, rn = 1 сохранено.
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
-- [СОХРАНЕНО] Старые строки 142–195: продукт КК, CASE статусов, условия ветки и длина ID.
-- [ИЗМЕНЕНО] Технически: единые имена таблиц без повторного tif_; квалифицированные имена полей.
-- Откуда: раздел «Кредитные карты», строки 134–187 tech_questionnaire_status.
-- Зачем: присвоить level25_product_bp_nm тем же способом; далее продукт фильтруется по этому полю.
-- Копирование: можно полностью скопировать из tech_questionnaire_status; заменить только имена таблиц/макроимена.
drop table if exists &db_sbx.man_prt_tif_tqs_kk_questionnaire;
create table &db_sbx.man_prt_tif_tqs_kk_questionnaire
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
from &db_sbx.man_prt_tif_tqs_questionnaire r
where 1=1
  and (r.src_cd_src like &p_quest_src_cd_kk_list or r.product_type_code in (&p_quest_product_kk_list))
  and length(r.questionnaire_id) not in (&p_quest_not_len_id_kk_list)
) distributed randomly;

-- Шаг 1.3. Ветка KN: продукт и статусы исходного TQS.
-- [СОХРАНЕНО] Старые строки 197–306: продукт КН, статусы, все 47 приоритетов и отбор ветки.
-- [ИЗМЕНЕНО] Технически: имена таблиц/алиасов согласованы с соседними шагами.
-- Откуда: раздел «Кредит наличными», строки 190–299 tech_questionnaire_status.
-- Зачем: присвоить level25_product_bp_nm тем же способом; далее продукт фильтруется по этому полю.
-- Копирование: можно полностью скопировать из tech_questionnaire_status; заменить только имена таблиц/макроимена.
drop table if exists &db_sbx.man_prt_tif_tqs_kn_questionnaire;
create table &db_sbx.man_prt_tif_tqs_kn_questionnaire
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
from &db_sbx.man_prt_tif_tqs_questionnaire r
where 1=1
  and (r.src_cd_src like &p_quest_src_cd_kn_list or r.product_type_code in (&p_quest_product_kn_list))
  and r.src_cd_src not like &p_quest_src_cd_kk_list
) distributed randomly;

-- Шаг 1.4. Сдвиг совпадающих времён статусов только КН.
-- [СОХРАНЕНО] Старые строки 308–398: сдвиг совпавшего времени по приоритету статусов КН.
-- [ИЗМЕНЕНО] Убрана сортировка только для авто; переименование UTM/status перенесено в 1.5.
-- [ИЗМЕНЕНО] Технические границы: первый diff_sec равен 1 вместо -1, сравнение >= вместо >;
--               для первой строки и равенства число добавленных секунд остаётся тем же.
-- Откуда: prt_tqs_kn_auto_dk_questionnaire, строки 659–787 tech_questionnaire_status.
-- Зачем: сохранить исходное построение effective_from_dttm, не добавляя отдельные проверки.
-- Копирование: скопировать исходный шаг; оставить только КН и пронести application_num через оба SELECT.
drop table if exists &db_sbx.man_prt_tif_tqs_kn_timeline;
create table &db_sbx.man_prt_tif_tqs_kn_timeline
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
from &db_sbx.man_prt_tif_tqs_kn_questionnaire
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
-- [СОХРАНЕНО] Старые строки 400–452: UNION ALL КК/КН, application_num сохранён в обеих ветках.
-- [ИЗМЕНЕНО] Явные поля/переименования согласованы с выходом 1.4; таблицы названы единообразно.
-- Откуда: prt_tqs_questionnaire_all, строки 789–840 tech_questionnaire_status.
-- Зачем: получить исходный состав TQS после переименований UTM/status/src и сохранить номер заявки.
-- Копирование: скопировать UNION КК/КН; убрать остальные продукты, добавить application_num в оба плеча.
drop table if exists &db_sbx.man_prt_tif_tqs_questionnaire_all;
create table &db_sbx.man_prt_tif_tqs_questionnaire_all
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
from &db_sbx.man_prt_tif_tqs_kk_questionnaire kk
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
from &db_sbx.man_prt_tif_tqs_kn_timeline kn
) distributed randomly;

-- Шаг 1.6. Получение RK и интервалов TQS для КН/КК.
-- [ИЗМЕНЕНО] Старые строки 454–498: RK берётся из готовой TQS вместо TQXC.
--               Актуальные пары ID/RK сгруппированы, отсутствующие RK исключены; INNER JOIN сохранён.
-- Откуда: готовая tech_questionnaire_status, по уточнённому ФТ; исходные данные — результат 1.5.
-- Зачем: взять готовый RK анкеты из TQS, сохранив подготовленные статусы и все application_num.
-- Копирование: в финальной сборке TQS заменить источник RK на готовую TQS; убрать повторы пар ID/RK.
drop table if exists &db_sbx.man_prt_tif_tech_questionnaire_status;
create table &db_sbx.man_prt_tif_tech_questionnaire_status
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    cast(tqs.questionnaire_rk as bigint) as questionnaire_rk,
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
        partition by tqs.questionnaire_rk order by base.effective_from_dttm
    ) as timestamp) as effective_to_dttm,
    cast(&p_report_timestamp as timestamp) as processed_dttm
from &db_sbx.man_prt_tif_tqs_questionnaire_all base
-- [ИЗМЕНЕНО] Старые строки 485–496: источник RK — актуальная TQS, не TQXC.
inner join (
    select questionnaire_id, questionnaire_rk
    from &p_db_cdmr.tech_questionnaire_status
    where effective_to_dttm = cast(&p_max_date as timestamp)
      and questionnaire_rk is not null
      and questionnaire_rk <> -1
    group by 1, 2
) tqs on tqs.questionnaire_id = base.questionnaire_id
) distributed randomly;

-- Шаг 1.7. Предварительный флаг верификации КН/КК по всей истории TQS.
-- [СОХРАНЕНО] Старые строки 500–548: MAX по всей истории и спискам статусов продукта.
-- [ИЗМЕНЕНО] Это предварительный флаг: найденная связь с TAS выставит true в 1.13/2.3.
-- Откуда: новый шаг; MAX(CASE) взят из стиля флагов tech_application_status, статусы — из выделений Excel.
-- Зачем: рассчитать флаг для анкет без связи; при найденной связи шаг 1.13 установит true.
-- Копирование: это добавляемый шаг, целиком из TQS его скопировать нельзя.
drop table if exists &db_sbx.man_prt_tif_kn_kk_verification;
create table &db_sbx.man_prt_tif_kn_kk_verification
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
from &db_sbx.man_prt_tif_tech_questionnaire_status
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
from &db_sbx.man_prt_tif_tech_questionnaire_status q
inner join verification v
    on v.questionnaire_rk = q.questionnaire_rk
   and v.level25_product_bp_nm = q.level25_product_bp_nm
) distributed randomly;

-- Шаг 1.8. Одна анкета КН/КК после расчёта флага по истории.
-- [НОВОЕ] После старых строк 500–548: отдельная база анкет RK + продукт, независимо от номера.
--           MIN даты и MAX флага сворачивают историю, а не атрибуты TAS.
-- Откуда: история 1.7; итоговая витрина по ФТ не хранит версии статусов.
-- Зачем: сохранить все анкеты, включая не имеющие application_num; агрегировать историю, не строки TAS.
drop table if exists &db_sbx.man_prt_tif_kn_kk_questionnaire;
create table &db_sbx.man_prt_tif_kn_kk_questionnaire
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    q.questionnaire_rk,
    q.level25_product_bp_nm,
    min(q.questionnaire_dttm) as questionnaire_dttm,
    cast(max(cast(q.quest_verification_flg as integer)) as boolean) as quest_verification_flg
from &db_sbx.man_prt_tif_kn_kk_verification q
group by q.questionnaire_rk, q.level25_product_bp_nm
having min(q.questionnaire_dttm) >= cast(&P_BEGIN_DATE as timestamp)
    or min(q.questionnaire_dttm) is null
) distributed randomly;

-- Шаг 1.9. Все номера анкеты, пережившие исходную дедупликацию.
-- [НОВОЕ] Из старого большого BDM-шага (550–580) выделено отношение анкета/продукт/номер.
--           Повторы номера на разных статусах свернуты по ключу; все разные номера сохраняются.
-- Откуда: application_num из исходной цепочки TQS; ключ связи — анкета, продукт, номер.
-- Зачем: один номер не должен повторяться из-за статусов; разные номера сохраняются.
drop table if exists &db_sbx.man_prt_tif_kn_kk_numbers;
create table &db_sbx.man_prt_tif_kn_kk_numbers
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    q.questionnaire_rk,
    q.level25_product_bp_nm,
    q.application_num
from &db_sbx.man_prt_tif_kn_kk_verification q
inner join &db_sbx.man_prt_tif_kn_kk_questionnaire b
    on b.questionnaire_rk = q.questionnaire_rk
   and b.level25_product_bp_nm = q.level25_product_bp_nm
where q.application_num is not null
group by q.questionnaire_rk, q.level25_product_bp_nm, q.application_num
) distributed randomly;

-- Шаг 1.10. application_num -> ключ BDM.APPLICATION.
-- [ИЗМЕНЕНО] Вместо старых строк 550–580: перевод только ключей номеров в ключи BDM, без DISTINCT.
--               LEFT JOIN заменён INNER JOIN в мосте; все анкеты отдельно сохранены в 1.8.
--               Убраны ограничения старой даты создания родителя и списка источников BDM;
--               источник теперь проверяется по parent_src_cd при соединении в 1.12.
-- Откуда: ФТ 1.2, строка 4; источник ключа далее сравнивается с parent_src_cd TAS.
-- Зачем: свернуть только повтор одной связи через разные номера; не выбирать случайную заявку.
drop table if exists &db_sbx.man_prt_tif_kn_kk_bdm;
create table &db_sbx.man_prt_tif_kn_kk_bdm
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
from &db_sbx.man_prt_tif_kn_kk_numbers q
-- [ИЗМЕНЕНО] Старые строки 569–577: источник ключа не ограничивается прежними кодами/датой родителя.
inner join &p_db_bdm.application app
    on app.application_num = q.application_num
   and app.effective_to_date = cast(&p_max_date as date)
   and app.application_rk is not null
   and app.application_rk <> -1
group by q.questionnaire_rk, q.level25_product_bp_nm, app.application_rk, app.src_cd
) distributed randomly;

-- Шаг 1.11. Готовая TAS КН/КК без удаления дублей.
-- [ИЗМЕНЕНО] Старые строки 582–619: TAS без DISTINCT; COALESCE(RK, -1) вместо NULLIF.
--               Отбор по продукту вместо источников; NULL-продукт разрешён при найденной целевой анкете.
--               Дополнительно исключены строки без обоих реальных заявочных ключей.
-- Откуда: TAS, предоставленный состав 22 полей; отбор по продуктам из ФТ 1.2.1.
-- Зачем: сохранить все исходные строки; DISTINCT не должен скрывать нарушение ключа TAS.
drop table if exists &db_sbx.man_prt_tif_kn_kk_tas;
create table &db_sbx.man_prt_tif_kn_kk_tas
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
-- [ИЗМЕНЕНО] Старые строки 592/601: оба заявочных ключа сохраняют -1 вместо превращения в NULL.
    coalesce(t.parent_application_rk, -1) as parent_application_rk,
    t.parent_application_id,
    t.parent_application_dt,
    t.parent_src_cd,
    t.parent_approved_dttm,
    cast(t.parent_open_flg as boolean) as parent_open_flg,
    cast(t.parent_prescoring_flg as boolean) as parent_prescoring_flg,
    cast(t.parent_at_work_flg as boolean) as parent_at_work_flg,
    cast(t.parent_approved_flg as boolean) as parent_approved_flg,
    coalesce(t.application_rk, -1) as application_rk,
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
-- [ИЗМЕНЕНО] Отбор по продукту и отдельно оговорённая связь для NULL-продукта.
where (t.level25_product_bp_nm in (&p_quest_25lvl_product_kn_list, &p_quest_25lvl_product_kk_list)
       or (t.level25_product_bp_nm is null and exists (
           select 1 from &db_sbx.man_prt_tif_kn_kk_bdm q
           where q.bdm_application_rk = t.parent_application_rk
             and q.bdm_src_cd = t.parent_src_cd
       )))
  and (coalesce(t.application_dt, t.parent_application_dt) >= cast(&P_BEGIN_DATE as date)
       or coalesce(t.application_dt, t.parent_application_dt) is null)
  and (coalesce(t.parent_application_rk, -1) <> -1
       or coalesce(t.application_rk, -1) <> -1)
) distributed randomly;

-- Шаг 1.12. Единственное соединение BDM -> родительский ключ TAS.
-- [ИЗМЕНЕНО] Полная замена старого JOIN в строках 621–670: только родительский ключ + его источник.
--               Прямой путь, отдельный путь собственного RK УЗ и переключатель режимов удалены.
--               GROUP BY хранит ключи отношений; полные строки TAS не дедуплицируются.
-- Откуда: ФТ 1.2.4: app.application_rk = tas.parent_application_rk; совпадение источников.
-- Зачем: получить ключи найденных пар; прямой путь на tas.application_rk исключён.
drop table if exists &db_sbx.man_prt_tif_kn_kk_matches;
create table &db_sbx.man_prt_tif_kn_kk_matches
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    q.questionnaire_rk,
    q.level25_product_bp_nm,
    t.parent_application_rk,
    t.application_rk
from &db_sbx.man_prt_tif_kn_kk_bdm q
inner join &db_sbx.man_prt_tif_kn_kk_tas t
-- [ИЗМЕНЕНО] Старые строки 660–669: единственное условие ключа, источник — родительский.
    on q.bdm_application_rk = t.parent_application_rk
   and q.bdm_src_cd = t.parent_src_cd
group by q.questionnaire_rk, q.level25_product_bp_nm,
         t.parent_application_rk, t.application_rk
) distributed randomly;

-- Шаг 1.13. Анкеты КН/КК и найденные заявки через LEFT JOIN.
-- [ИЗМЕНЕНО] Вместо старых строк 672–759: одна анкетная ветка LEFT JOIN, без трёх частей и DISTINCT.
--               Заявки без анкеты перенесены в общий шаг 3.2. При связи флаг true; отсутствующие RK -1.
--               level35 берётся только из собственного поля TAS; исправлены старые недоступные алиасы.
-- Откуда: ФТ: анкеты без заявки сохраняются; наличие связи устанавливает флаг true.
-- Зачем: каждую анкету без связи вывести один раз; заявки без анкеты будут добавлены только в 3.2.
drop table if exists &db_sbx.man_prt_tif_kn_kk_fin;
create table &db_sbx.man_prt_tif_kn_kk_fin
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    cast(q.questionnaire_rk as bigint) as questionnaire_rk,
    cast(q.questionnaire_dttm as timestamp) as questionnaire_dttm,
-- [ИЗМЕНЕНО] Старая строка 684: найденная заявка устанавливает true независимо от статусов.
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
    cast(coalesce(t.level25_product_bp_nm, q.level25_product_bp_nm) as text) as level25_product_bp_nm,
-- [ИЗМЕНЕНО] Старые строки 699/721: собственное поле TAS; без заявки/значения — NULL.
    cast(t.level35_product_bp_nm as text) as level35_product_bp_nm,
    cast(&p_report_timestamp as timestamp(0)) as processed_dttm
from &db_sbx.man_prt_tif_kn_kk_questionnaire q
-- [ИЗМЕНЕНО] Здесь сохраняется только анкетная сторона; остаток TAS добавляется в 3.2.
left join &db_sbx.man_prt_tif_kn_kk_matches m
    on m.questionnaire_rk = q.questionnaire_rk
   and m.level25_product_bp_nm = q.level25_product_bp_nm
left join &db_sbx.man_prt_tif_kn_kk_tas t
    on t.parent_application_rk = m.parent_application_rk
   and t.application_rk = m.application_rk
) distributed randomly;

-- Шаг 2.1. Готовая TQS авто и предварительный флаг верификации по истории.
-- [ИЗМЕНЕНО] Старые строки 761–782: исторический MAX сначала считается по RK/продукту без ID.
-- [НОВОЕ] Затем current_ids берёт актуальный ID из TQS; старые ID не создают лишние строки.
--           MIN даты и все статусы истории сохраняются; RK NULL/-1 исключаются.
-- Откуда: tech_questionnaire_status напрямую; MAX(CASE) — стиль флагов tech_application_status.
-- Зачем: вычислить флаг по всей истории, затем получить актуальный ID анкеты для связи со снимком TAS.
-- Копирование: новая агрегация готовой TQS; имена status_cd/RK/даты/продукта — из её DDL.
drop table if exists &db_sbx.man_prt_tif_auto_verification;
create table &db_sbx.man_prt_tif_auto_verification
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
with verification as (
select
    q.questionnaire_rk,
    min(q.questionnaire_dttm) as questionnaire_dttm,
    cast(max(case when q.status_cd in (&p_auto_verification_status) then 1 else 0 end) as boolean)
        as quest_verification_flg,
    q.level25_product_bp_nm
from &p_db_cdmr.tech_questionnaire_status q
where q.level25_product_bp_nm = cast(&p_quest_25lvl_product_auto_list as text)
  and q.questionnaire_rk is not null
  and q.questionnaire_rk <> -1
group by q.questionnaire_rk, q.level25_product_bp_nm
having min(q.questionnaire_dttm) >= cast(&P_BEGIN_DATE as timestamp)
    or min(q.questionnaire_dttm) is null
),
-- [НОВОЕ] Текущий ID выбирается ПОСЛЕ исторического флага, а не вместо истории.
current_ids as (
select
    q.questionnaire_id,
    q.questionnaire_rk,
    q.level25_product_bp_nm
from &p_db_cdmr.tech_questionnaire_status q
where q.level25_product_bp_nm = cast(&p_quest_25lvl_product_auto_list as text)
  and q.effective_to_dttm = cast(&p_max_date as timestamp)
  and q.questionnaire_rk is not null
  and q.questionnaire_rk <> -1
group by q.questionnaire_id, q.questionnaire_rk, q.level25_product_bp_nm
)
select
    q.questionnaire_id,
    v.questionnaire_rk,
    v.questionnaire_dttm,
    v.quest_verification_flg,
    v.level25_product_bp_nm
from verification v
inner join current_ids q
    on q.questionnaire_rk = v.questionnaire_rk
   and q.level25_product_bp_nm = v.level25_product_bp_nm
) distributed randomly;

-- Шаг 2.2. Готовая TAS авто без удаления дублей.
-- [ИЗМЕНЕНО] Старые строки 784–820: TAS без DISTINCT, COALESCE ключей вместо NULLIF.
--               Отбор по продукту авто вместо источника; NULL-продукт — только при связи с анкетой.
--               TAS уже хранит последнее состояние; выбор версии по processed_dttm не добавляется.
-- Откуда: TAS, предоставленный состав 22 полей; продукт из ФТ 1.2.1.
-- Зачем: взять последнее состояние каждой заявки, которое хранит TAS; дополнительные версии не выбираются.
drop table if exists &db_sbx.man_prt_tif_auto_tas;
create table &db_sbx.man_prt_tif_auto_tas
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
-- [ИЗМЕНЕНО] Старые строки 794/803: оба заявочных ключа сохраняют -1 вместо превращения в NULL.
    coalesce(t.parent_application_rk, -1) as parent_application_rk,
    t.parent_application_id,
    t.parent_application_dt,
    t.parent_src_cd,
    t.parent_approved_dttm,
    cast(t.parent_open_flg as boolean) as parent_open_flg,
    cast(t.parent_prescoring_flg as boolean) as parent_prescoring_flg,
    cast(t.parent_at_work_flg as boolean) as parent_at_work_flg,
    cast(t.parent_approved_flg as boolean) as parent_approved_flg,
    coalesce(t.application_rk, -1) as application_rk,
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
-- [ИЗМЕНЕНО] Отбор по продукту и отдельно оговорённая связь для NULL-продукта.
where (t.level25_product_bp_nm = cast(&p_quest_25lvl_product_auto_list as text)
       or (t.level25_product_bp_nm is null and exists (
           select 1 from &db_sbx.man_prt_tif_auto_verification q
           where q.questionnaire_id = t.application_id
       )))
  and (coalesce(t.application_dt, t.parent_application_dt) >= cast(&P_BEGIN_DATE as date)
       or coalesce(t.application_dt, t.parent_application_dt) is null)
  and (coalesce(t.parent_application_rk, -1) <> -1
       or coalesce(t.application_rk, -1) <> -1)
) distributed randomly;

-- Шаг 2.3. Анкеты авто и найденные заявки через LEFT JOIN.
-- [ИЗМЕНЕНО] Старые строки 823–854: FULL JOIN заменён LEFT JOIN от текущих ID анкет.
--               Исправлены имена входных таблиц; флаг при связи true; отсутствующие RK -1.
--               level35 — собственное поле TAS. Оставшиеся заявки добавляются только в 3.2.
-- Откуда: ФТ 1.2.3: актуальный questionnaire_id TQS = application_id снимка TAS.
-- Зачем: сохранить анкетную сторону; остаток TAS добавляется отдельно, не через FULL JOIN.
drop table if exists &db_sbx.man_prt_tif_auto_fin;
create table &db_sbx.man_prt_tif_auto_fin
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    cast(q.questionnaire_rk as bigint) as questionnaire_rk,
    cast(q.questionnaire_dttm as timestamp) as questionnaire_dttm,
-- [ИЗМЕНЕНО] Старая строка 834: найденная заявка устанавливает true независимо от статусов.
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
    cast(coalesce(t.level25_product_bp_nm, q.level25_product_bp_nm) as text) as level25_product_bp_nm,
-- [ИЗМЕНЕНО] Старые строки 849: собственное поле TAS; без заявки/значения — NULL.
    cast(t.level35_product_bp_nm as text) as level35_product_bp_nm,
    cast(&p_report_timestamp as timestamp(0)) as processed_dttm
from &db_sbx.man_prt_tif_auto_verification q
-- [ИЗМЕНЕНО] Здесь сохраняется только анкетная сторона; остаток TAS добавляется в 3.2.
left join &db_sbx.man_prt_tif_auto_tas t
    on q.questionnaire_id = t.application_id
) distributed randomly;

-- Шаг 3.1. Первая таблица: все анкеты с найденными заявками или без них.
-- [ИЗМЕНЕНО] Старые строки 856–908: эта первая таблица объединяет только анкетные ветки.
--               Это ещё не весь итог: связанные заявки уже здесь, остаток добавится отдельно.
-- Откуда: результаты 1.13 и 2.3; ФТ 1.2.5 требует исключить повторное добавление связанных заявок.
-- Зачем: сформировать анкетную часть, относительно которой проверяется остаток TAS.
drop table if exists &db_sbx.man_prt_tif_questionnaire_funnel;
create table &db_sbx.man_prt_tif_questionnaire_funnel
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
from &db_sbx.man_prt_tif_kn_kk_fin k
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
from &db_sbx.man_prt_tif_auto_fin a
) distributed randomly;

-- Шаг 3.2. Только заявки TAS, не попавшие в первую таблицу.
-- [НОВОЕ] Общая ветка остатка TAS вместо локального остатка КН/КК (старые строки 731–758)
--           и заявочной стороны прежнего FULL JOIN авто. Проверяется вся первая таблица 3.1.
--           NOT EXISTS использует полную пару ключей TAS; DISTINCT/UNION для подавления повторов нет.
-- Откуда: ФТ 1.2.5: исключить заявки, уже соединившиеся с анкетами.
-- Зачем: NOT EXISTS по полному ключу TAS; дочерние заявки одной УЗ не исключают друг друга.
drop table if exists &db_sbx.man_prt_tif_remaining_tas;
create table &db_sbx.man_prt_tif_remaining_tas
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
with tas as (
select
    k.parent_application_rk,
    k.parent_application_id,
    k.parent_application_dt,
    k.parent_src_cd,
    k.parent_approved_dttm,
    k.parent_open_flg,
    k.parent_prescoring_flg,
    k.parent_at_work_flg,
    k.parent_approved_flg,
    k.application_rk,
    k.application_id,
    k.application_dt,
    k.src_cd,
    k.application_type_cd,
    k.deal_issue_date,
    k.create_flg,
    k.at_work_flg,
    k.final_approved_flg,
    k.agr_signed_flg,
    k.level25_product_bp_nm,
    k.level35_product_bp_nm,
    k.processed_dttm
from &db_sbx.man_prt_tif_kn_kk_tas k
union all
select
    a.parent_application_rk,
    a.parent_application_id,
    a.parent_application_dt,
    a.parent_src_cd,
    a.parent_approved_dttm,
    a.parent_open_flg,
    a.parent_prescoring_flg,
    a.parent_at_work_flg,
    a.parent_approved_flg,
    a.application_rk,
    a.application_id,
    a.application_dt,
    a.src_cd,
    a.application_type_cd,
    a.deal_issue_date,
    a.create_flg,
    a.at_work_flg,
    a.final_approved_flg,
    a.agr_signed_flg,
    a.level25_product_bp_nm,
    a.level35_product_bp_nm,
    a.processed_dttm
from &db_sbx.man_prt_tif_auto_tas a
)
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
-- [СОХРАНЕНО] Старая строка 749 уже брала собственный уровень 35 TAS; убран лишь COALESCE с NULL.
    cast(t.level35_product_bp_nm as text) as level35_product_bp_nm,
    cast(&p_report_timestamp as timestamp(0)) as processed_dttm
from tas t
-- [НОВОЕ] Общий остаток: полная пара RK отсутствует во всей анкетной таблице, а не только в своей ветке.
where not exists (
    select 1
    from &db_sbx.man_prt_tif_questionnaire_funnel f
    where f.parent_application_rk = t.parent_application_rk
      and f.application_rk = t.application_rk
)
) distributed randomly;

-- Шаг 3.3. Итог: первая таблица плюс только оставшиеся заявки.
-- [ИЗМЕНЕНО] Вместо прежней конечной сборки (856–908): первая таблица + только остаток TAS.
--               UNION ALL и состав 19 полей сохранены.
-- Откуда: ФТ, 19 итоговых атрибутов; наборы разделены условием NOT EXISTS в 3.2.
-- Зачем: исключить повторное добавление связанной заявки без маскировки DISTINCT.
drop table if exists &db_sbx.man_prt_tif_tech_internet_funnel;
create table &db_sbx.man_prt_tif_tech_internet_funnel
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
from &db_sbx.man_prt_tif_questionnaire_funnel q
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
from &db_sbx.man_prt_tif_remaining_tas t
) distributed randomly;

-- [ИЗМЕНЕНО] Старые строки 910–923: проверка вынесена в sql/check_internet_funnel.sql.
-- Отдельные SELECT вместо одновременных DISTINCT; наличие сущности проверяется по RK <> -1.
