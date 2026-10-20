/*
ОТДЕЛЬНЫЙ РАСЧЁТ ПОКРЫТИЯ ПО УЖЕ ГОТОВОЙ ВИТРИНЕ. Greenplum.
Можно запускать без повторения основного ETL; используется только три RK-поля.

Макропеременные:
  &db_sbx         - схема для четырёх таблиц расчёта; по умолчанию: sbx_pre_orb_fd
  &p_funnel_table - полное имя готовой витрины БЕЗ кавычек;
                    по умолчанию: sbx_pre_orb_fd.prt_if2_tech_internet_funnel
                    Для вашей копии укажите её фактическое имя из FROM упавшего запроса.

Выполнять шаги последовательно, с остановкой на ошибке. Исходная витрина
читается и не изменяется. Заменяет последний запрос из нескольких COUNT DISTINCT.
Итоговые показатели точные, смысл NULL и составной пары RK сохранён.

Операции разнесены по запросам, используются узкие таблицы и группировки.
Потребление памяти всё равно зависит от объёма, плана, перекоса и параллельной
нагрузки ресурсной группы. На Greenplum/банковских объёмах в этой среде не проверено.
Настройки памяти и квоты ресурсной группы скрипт не меняет.
*/

-- Шаг 3.2. Одна строка на RK анкеты и признак найденной связи.
-- Откуда: расчёт покрытия уже построенной витрины; исправление ошибки high VMEM usage.
-- Зачем: заменить несколько одновременных DISTINCT одной группировкой по RK анкеты.
-- Копирование: новый расчёт показателей; подготовка источников и связки не меняются.
drop table if exists &db_sbx.prt_if2_coverage_questionnaires;
create table &db_sbx.prt_if2_coverage_questionnaires
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    questionnaire_rk,
    max(case when parent_application_rk is not null or application_rk is not null
             then 1 else 0 end) as linked_flg
from &p_funnel_table
where questionnaire_rk is not null
group by questionnaire_rk
) distributed by (questionnaire_rk);

-- Шаг 3.3. Счётчики уникальных анкет из подготовленной группировки.
-- Откуда: расчёт покрытия уже построенной витрины; исправление ошибки high VMEM usage.
-- Зачем: получить одну строку COUNT/SUM без DISTINCT и освободить агрегацию перед подсчётом заявок.
-- Копирование: новый расчёт показателей; подготовка источников и связки не меняются.
drop table if exists &db_sbx.prt_if2_coverage_questionnaire_counts;
create table &db_sbx.prt_if2_coverage_questionnaire_counts
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    count(*) as questionnaire_count,
    cast(coalesce(sum(linked_flg), 0) as bigint) as linked_questionnaire_count
from &db_sbx.prt_if2_coverage_questionnaires
) distributed randomly;

-- Шаг 3.4. Одна строка на пару RK заявки и признак найденной анкеты.
-- Откуда: расчёт покрытия уже построенной витрины; исправление ошибки high VMEM usage.
-- Зачем: группировать два bigint вместо DISTINCT составного ROW; распределять по обоим RK.
-- Копирование: новый расчёт показателей; подготовка источников и связки не меняются.
drop table if exists &db_sbx.prt_if2_coverage_applications;
create table &db_sbx.prt_if2_coverage_applications
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    parent_application_rk,
    application_rk,
    max(case when questionnaire_rk is not null then 1 else 0 end) as linked_flg
from &p_funnel_table
where parent_application_rk is not null or application_rk is not null
group by parent_application_rk, application_rk
) distributed by (parent_application_rk, application_rk);

-- Шаг 3.5. Счётчики уникальных заявочных пар из подготовленной группировки.
-- Откуда: расчёт покрытия уже построенной витрины; исправление ошибки high VMEM usage.
-- Зачем: получить одну строку COUNT/SUM без хранения ещё одного набора DISTINCT.
-- Копирование: новый расчёт показателей; подготовка источников и связки не меняются.
drop table if exists &db_sbx.prt_if2_coverage_application_counts;
create table &db_sbx.prt_if2_coverage_application_counts
with (APPENDONLY = true,
      ORIENTATION = column,
      COMPRESSTYPE = zstd,
      COMPRESSLEVEL = 5)
as (
select
    count(*) as application_count,
    cast(coalesce(sum(linked_flg), 0) as bigint) as linked_application_count
from &db_sbx.prt_if2_coverage_applications
) distributed randomly;

-- Шаг 3.6. Итоговый отчёт о связке из двух однострочных таблиц счётчиков.
-- Откуда: те же пять показателей прежнего запроса покрытия, без одновременных COUNT(DISTINCT).
-- Зачем: посчитать процент уже после группировок; CROSS JOIN здесь соединяет ровно две строки.
-- Заявочная сущность — пара parent_application_rk/application_rk, как до исправления.
-- Строки без обоих заявочных RK не входят в знаменатель заявок; NULL процента означает пустую базу анкет.
select
    q.questionnaire_count,
    q.linked_questionnaire_count,
    round(100.0 * q.linked_questionnaire_count / nullif(q.questionnaire_count, 0), 2)
        as questionnaire_link_pct,
    a.application_count,
    a.linked_application_count
from &db_sbx.prt_if2_coverage_questionnaire_counts q
cross join &db_sbx.prt_if2_coverage_application_counts a;
