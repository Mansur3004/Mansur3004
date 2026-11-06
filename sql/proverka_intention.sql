/*
ПРОВЕРКА ДЕТЕРМИНИРОВАННОСТИ ROW_NUMBER В QUESTIONNAIRE_X_INTENTION.
Запускать весь файл ПО ПОРЯДКУ в одной SQL-сессии Greenplum.
Исходники и таблицы TIF не меняются. Создаются только три временные таблицы.
Перезапуск удаляет только одноимённые таблицы в pg_temp текущей сессии.

Настройка под скриншот:
  1. База анкет ниже: sbx_pre_orb_fd.man_prt_tif_questionnaire.
     Для V5 заменить её на sbx_pre_orb_fd.man_prt_tif_v5_questionnaire.
  2. only_nonnull_numbers=false: как в показанном WHERE, без фильтра номера.
     Для файла V5 установить true: в V5 есть application_num IS NOT NULL.
  3. Если в рабочем шаге меняли продуктовый отбор / ORDER BY / минимальную дату,
     применить те же изменения здесь. На другом срезе результат несопоставим.
  4. Для точечной проверки можно раскомментировать фильтр одного ID ниже.

Проверяем один зафиксированный срез RAW: порядок вычисляется ровно один раз.
DENSE_RANK использует ТОТ ЖЕ ORDER BY, что рабочий ROW_NUMBER.
priority_rank=1 содержит ВСЕ строки, претендующие на rn=1; более низкие
ранги не влияют на текущий выбор. Дополнительно даётся сводка по всем рангам.

Полное представление строки: row_to_json(r)::text, по всем реальным столбцам
источника, включая новые, отсутствующие в старом ETL. Сравниваются сами строки,
а не MD5/хеши. Без ctid и порядка физических строк.
JSON-представление используется только в диагностике, не как новый приоритет.

Результаты:
  SELECT 1 — сводка: full_duplicate_groups = только полные дубли в группе;
             different_rows_tie_groups = разные исходные строки с равным ORDER BY;
             number_conflict_groups = разные номера среди равноприоритетных строк;
             null_number_groups = приоритетная группа с NULL-номером.
  SELECT 2 — до 100 групп первого приоритета с неоднозначным выбором строки.
  SELECT 3 — различающиеся столбцы для до 100 таких групп, без вывода их значений.
  SELECT 4 — до 100 групп полных дублей, включая дубли ниже первого приоритета.

Действия:
  * Все группы первого приоритета имеют одну строку: физический выбор однозначен.
  * В первом приоритете полные дубли: DISTINCT исходных строк ДО окна, если нужно
    убрать физические копии. SELECT DISTINCT вместе с ROW_NUMBER в том же SELECT
    не поможет: разные rn сами сделают строки различными.
  * Разные строки с одинаковым ORDER BY: проверить SELECT 3 и дописать подходящие
    поля В КОНЕЦ ORDER BY, сохранив прежние бизнес-приоритеты. Само поле может уже
    входить в ORDER BY через COALESCE: например NULL и '#' дают равный приоритет.
    Если поле не поддерживает сортировку напрямую, нужно определить сравнимое
    представление с учётом его типа, а не механически добавлять любой столбец.
  * Устойчивость выводимых ID/номера и однозначность полной исходной строки —
    разные проверки. При равном ORDER BY номер уже одинаков по правилам его
    сравнения, т.к. application_num сам входит в ORDER BY. SELECT 1 это проверяет.
  * Если разные номера имеют РАЗНЫЙ приоритет, окно выбирает один определённо,
    но корректность бизнес-выбора номера — отдельный вопрос, не проверка ties.
  * Без фильтра непустого номера NULL при DESC по умолчанию идёт первым в PostgreSQL/
    Greenplum. Это может выбрать NULL, но само по себе не является недетерминизмом.

Изменения источника между запусками не являются недетерминизмом одного снимка.
GROUP BY ниже считает и классифицирует случаи; рабочие данные он не исправляет.
На большом объёме временные JSON-строки и сортировка требуют места/времени.
*/

drop table if exists pg_temp.man_prt_check_intention_groups;
drop table if exists pg_temp.man_prt_check_intention_variants;
drop table if exists pg_temp.man_prt_check_intention_ranked;

-- Подготовка A. Один снимок кандидатов, полный исходный порядок без новых полей.
create temporary table man_prt_check_intention_ranked
on commit preserve rows
as (
with settings as (
    select false as only_nonnull_numbers
)
select
    r.questionnaire_id,
    r.application_num,
    row_to_json(r)::text as source_row_json,
    dense_rank() over (
        partition by r.questionnaire_id
        order by
            coalesce(cast(r.createtime_dttm as timestamp), timestamp '1900-01-01 00:00:00') desc,
            r.sessionintention_id,
            coalesce(cast(r.processed_dttm as timestamp), timestamp '1900-01-01 00:00:00') desc,
            coalesce(cast(r.business_dt as timestamp), timestamp '1900-01-01 00:00:00') desc,
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
            coalesce(cast(r.questionnaire_dt as timestamp), timestamp '1900-01-01 00:00:00') desc,
            r.program_type,
            coalesce(cast(r.scoring_dt as timestamp), timestamp '1900-01-01 00:00:00') desc,
            coalesce(cast(r.prescoring_dt as timestamp), timestamp '1900-01-01 00:00:00') desc,
            r.application_num desc,
            coalesce(r.scoring_status_nm, '#') desc,
            coalesce(r.prescoring_status_nm, '#') desc,
            coalesce(r.spec_program, '#') desc,
            coalesce(r.src_cd_src, '#') desc,
            r.salary_card_flg desc,
            r.phone_num
    ) as priority_rank
from rd_raw_orb.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention r
where (not (select only_nonnull_numbers from settings)
       or r.application_num is not null)
  and exists (
      select 1
      from sbx_pre_orb_fd.man_prt_tif_questionnaire q
      where q.questionnaire_id = r.questionnaire_id
        and q.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
  )
  -- and r.questionnaire_id = 'ID_ДЛЯ_ТОЧЕЧНОЙ_ПРОВЕРКИ'
) distributed by (questionnaire_id);

-- Подготовка B. Различимые исходные строки и число их полных копий.
create temporary table man_prt_check_intention_variants
on commit preserve rows
as (
select
    questionnaire_id,
    priority_rank,
    application_num,
    source_row_json,
    count(*) as physical_copies
from pg_temp.man_prt_check_intention_ranked
group by questionnaire_id, priority_rank, application_num, source_row_json
) distributed by (questionnaire_id);

-- Подготовка C. Сводим копии только для измерения состава каждой группы ties.
create temporary table man_prt_check_intention_groups
on commit preserve rows
as (
select
    questionnaire_id,
    priority_rank,
    sum(physical_copies) as source_row_count,
    count(*) as different_source_rows,
    sum(physical_copies - 1) as extra_full_copies,
    count(distinct application_num)
        + max(case when application_num is null then 1 else 0 end) as different_numbers,
    max(case when application_num is null then 1 else 0 end) as has_null_number
from pg_temp.man_prt_check_intention_variants
group by questionnaire_id, priority_rank
) distributed by (questionnaire_id);

-- SELECT 1. Важнее всего строка WINNERS: состав кандидатов на rn=1.
-- Нули в счётчиках при пустой популяции не доказывают проверку непустого среза:
-- сначала смотрите source_row_count и priority_group_count.
with scopes as (
    select 'WINNERS'::text as checked_scope
    union all
    select 'ALL_PRIORITY_GROUPS'::text
)
select
    s.checked_scope,
    count(g.questionnaire_id) as priority_group_count,
    coalesce(sum(g.source_row_count), 0) as source_row_count,
    coalesce(sum(case when g.source_row_count > 1 then 1 else 0 end), 0) as tie_groups,
    coalesce(sum(case when g.source_row_count > 1 and g.different_source_rows = 1
                      then 1 else 0 end), 0) as full_duplicate_groups,
    coalesce(sum(case when g.different_source_rows > 1 then 1 else 0 end), 0)
        as different_rows_tie_groups,
    coalesce(sum(g.extra_full_copies), 0) as extra_full_copies,
    coalesce(sum(case when g.different_numbers > 1 then 1 else 0 end), 0)
        as number_conflict_groups,
    coalesce(sum(g.has_null_number), 0) as null_number_groups
from scopes s
left join pg_temp.man_prt_check_intention_groups g
    on s.checked_scope = 'ALL_PRIORITY_GROUPS' or g.priority_rank = 1
group by s.checked_scope
order by s.checked_scope;

-- SELECT 2. Примеры неоднозначного выбора полной строки первого приоритета.
select
    questionnaire_id,
    source_row_count,
    different_source_rows,
    extra_full_copies,
    different_numbers,
    has_null_number,
    case when different_source_rows = 1 then 'FULL_DUPLICATES'
         else 'DIFFERENT_SOURCE_ROWS_WITH_EQUAL_ORDER' end as tie_type
from pg_temp.man_prt_check_intention_groups
where priority_rank = 1
  and source_row_count > 1
order by questionnaire_id
limit 100;

-- SELECT 3. Какие именно исходные поля различаются при равном первом приоритете.
-- json_each разворачивается в SELECT как set-returning function: без LATERAL.
-- В value_json NULL представлен строкой 'null', текстовое значение 'null' — '"null"':
-- они не смешиваются. Значения клиентских полей в результат не выводятся.
with sample_groups as (
    select questionnaire_id, priority_rank
    from pg_temp.man_prt_check_intention_groups
    where priority_rank = 1 and different_source_rows > 1
    order by questionnaire_id
    limit 100
), expanded as (
    select
        v.questionnaire_id,
        v.priority_rank,
        json_each(cast(v.source_row_json as json)) as source_field
    from pg_temp.man_prt_check_intention_variants v
    inner join sample_groups g
        on g.questionnaire_id = v.questionnaire_id
       and g.priority_rank = v.priority_rank
), field_values as (
    select
        questionnaire_id,
        priority_rank,
        (source_field).key as column_name,
        cast((source_field).value as text) as value_json
    from expanded
)
select
    questionnaire_id,
    priority_rank,
    column_name,
    count(distinct value_json) as different_values
from field_values
group by questionnaire_id, priority_rank, column_name
having count(distinct value_json) > 1
order by questionnaire_id, column_name;

-- SELECT 4. Полные дубли в любом ранге: после DISTINCT останется одна строка.
select
    questionnaire_id,
    priority_rank,
    physical_copies
from pg_temp.man_prt_check_intention_variants
where physical_copies > 1
order by questionnaire_id, priority_rank, physical_copies desc
limit 100;
