/*
ЭТАП 1. Только метаданные; исходные таблицы не изменяются.
Диалект: Greenplum / PostgreSQL. Запускать целиком в одном соединении.
Рабочая схема из скриншотов: sbx_pre_orb_fd.
DROP относится только к диагностической таблице с префиксом man_qas_.
Если прав на CREATE в этой схеме нет, заменить схему у man_qas_*.
Отсутствие строки в information_schema может означать отсутствие прав.
*/

drop table if exists sbx_pre_orb_fd.man_qas_01_inventory;
create table sbx_pre_orb_fd.man_qas_01_inventory as
select
    c.table_schema,
    c.table_name,
    c.ordinal_position,
    c.column_name,
    c.data_type,
    c.udt_name,
    c.is_nullable
from information_schema.columns c
where (
        c.table_schema in ('sbx_pre_orb_fd', 'dm_pik_fd_cdmr')
        and (
            c.table_name like '%tech_questionnaire_status%'
            or c.table_name like '%tech_application_status%'
            or c.table_name = 'man_prt_tqs_questionnaire'
        )
    )
    or (c.table_schema = 'bdm' and c.table_name = 'application')
    or (
        c.table_schema = 'rd_raw_orb'
        and c.table_name = 'v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention'
    )
distributed randomly;

-- Результат 1: какие объекты доступны. Нужны реальные имена TQS и TAS.
select table_schema, table_name, count(*) as column_count
from sbx_pre_orb_fd.man_qas_01_inventory
group by table_schema, table_name
order by table_schema, table_name;

-- Результат 2: ключи, номер заявки, версии, продукт, источник, верификация.
-- processed_dttm — время обработки; само по себе НЕ признак актуальности.
select table_schema, table_name, ordinal_position, column_name, data_type
from sbx_pre_orb_fd.man_qas_01_inventory
where column_name in (
        'questionnaire_id', 'questionnaire_rk', 'questionnaire_dttm',
        'application_num', 'application_id', 'application_rk',
        'parent_application_id', 'parent_application_rk',
        'src_cd', 'parent_src_cd', 'src_cd_src',
        'product_type_cd', 'program_type', 'application_type_cd',
        'level25_product_bp_nm', 'level35_product_bp_nm',
        'application_begin_date', 'application_dt', 'parent_application_dt',
        'status', 'status_cd', 'status_name', 'valid_flg', 'processed_dttm'
    )
    or lower(column_name) like '%effective%'
    or lower(column_name) like '%valid%'
    or lower(column_name) like '%actual%'
    or lower(column_name) like '%current%'
    or lower(column_name) like '%verif%'
    or lower(column_name) like '%identif%'
order by table_schema, table_name, ordinal_position;

-- Результат 3: полный состав технических витрин — страховка от пропуска
-- нестандартно названного поля или источника для верификации.
select table_schema, table_name, ordinal_position, column_name, data_type
from sbx_pre_orb_fd.man_qas_01_inventory
where table_name like '%tech_questionnaire_status%'
   or table_name like '%tech_application_status%'
order by table_schema, table_name, ordinal_position;

-- Результат 4: заявленные ограничения. В Greenplum их может не быть;
-- отсутствие PK не означает уникальности или неуникальности данных.
select
    tc.table_schema, tc.table_name, tc.constraint_type,
    tc.constraint_name, kcu.column_name, kcu.ordinal_position
from information_schema.table_constraints tc
left join information_schema.key_column_usage kcu
    on kcu.constraint_catalog = tc.constraint_catalog
   and kcu.constraint_schema = tc.constraint_schema
   and kcu.constraint_name = tc.constraint_name
   and kcu.table_schema = tc.table_schema
   and kcu.table_name = tc.table_name
where exists (
    select 1
    from sbx_pre_orb_fd.man_qas_01_inventory i
    where i.table_schema = tc.table_schema and i.table_name = tc.table_name
)
order by tc.table_schema, tc.table_name, tc.constraint_name, kcu.ordinal_position;
