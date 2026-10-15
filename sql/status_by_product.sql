/*
ПОДГОТОВКА К ЭТАПУ 1. Кандидаты для флага по скриншотам status_by_product.
Это не импорт исходного Excel: самого файла в репозитории нет.
Здесь восстановлены ТОЛЬКО пять видимых строк с жёлтой заливкой.
Значение цвета и бизнес-смысл флага пока НЕ подтверждены.
DONE («Выдача») и «одобрено» сами по себе не доказывают верификацию.
Зелёные статусы одобрения/выдачи автоматически в правило не включаются.

Выполнить перед workflow/01_questionnaire_verification.sql.
Диалект/хранение: Greenplum, как на предоставленном примере.
*/

drop table if exists sbx_pre_orb_fd.prt_qs_status_by_product;
create table sbx_pre_orb_fd.prt_qs_status_by_product
with (appendonly = true, orientation = column, compresstype = zstd, compresslevel = 5)
as
select
    cast(s.product_branch as text) as product_branch,
    cast(s.level25_product_bp_nm as text) as level25_product_bp_nm,
    cast(s.status_cd as text) as status_cd,
    cast(s.status_name as text) as status_name,
    cast('YELLOW' as text) as screenshot_highlight_cd,
    cast('SCREENSHOT_YELLOW' as text) as evidence_origin
from (
    values
        ('KN',   'Потребкредит',    'одобрено',         'одобрено'),
        ('KN',   'Потребкредит',    'CHECK_LIST_EMPTY', 'Одобрено'),
        ('KK',   'Кредитные карты', 'DONE',             'Выдача'),
        ('AUTO', 'Автокредит',      'VERIFICATION',     'VERIFICATION'),
        ('AUTO', 'Автокредит',      'DEAL_VER',         'Верификация')
) s(product_branch, level25_product_bp_nm, status_cd, status_name)
distributed randomly;

-- Контроль: пять кандидатов; это ещё не подтверждённый справочник правил.
select product_branch, level25_product_bp_nm, status_cd, status_name, evidence_origin
from sbx_pre_orb_fd.prt_qs_status_by_product
order by product_branch, status_cd;

-- Ожидается 0 строк: справочник не должен размножать строки истории.
select product_branch, level25_product_bp_nm, status_cd, count(*) as row_count
from sbx_pre_orb_fd.prt_qs_status_by_product
group by product_branch, level25_product_bp_nm, status_cd
having count(*) > 1;
