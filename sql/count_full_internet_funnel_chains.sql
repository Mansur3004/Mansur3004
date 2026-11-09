/*
Количество полных цепочек «анкета -> заявка -> выдача» в готовом TIF V5.
Один SELECT: итог по всей выборке и разрез по продукту итоговой витрины.
Ничего не создаёт, не удаляет и не изменяет в витрине.

Полная цепочка: реальный questionnaire_rk + реальный application_rk
и заполненная deal_issue_date. Родитель для Автокредита необязателен.
Равенство всех промежуточных флагов true дополнительно не требуется.

Единица счёта — тройка questionnaire_rk / parent_application_rk / application_rk.
full_chain_count — количество различных цепочек.
full_chain_row_count — количество строк с признаками полной цепочки.
Если числа различаются, есть повторные строки одной цепочки в данном разрезе.
Одна анкета с двумя выданными заявками — две цепочки.

product_scope=ALL — общий итог, PRODUCT — отдельный продукт.
Для ALL имя продукта NULL; для PRODUCT оно берётся из level25_product_bp_nm.
Непустая строка ALL с нулевыми счётчиками возвращается и при отсутствии цепочек.
При противоречивом продукте одной цепочки сумма продуктов может превышать итог.

Источник по умолчанию — результат V5 в sbx_pre_orb_fd.
Если рабочая таблица называется иначе, заменить только имя таблицы в FROM.
*/

with full_chains as (
    select
        f.questionnaire_rk,
        coalesce(f.parent_application_rk, -1) as parent_application_rk,
        f.application_rk,
        f.level25_product_bp_nm
    from sbx_pre_orb_fd.man_prt_tif_v5_tech_internet_funnel f
    where f.questionnaire_rk is not null
      and f.questionnaire_rk <> -1
      and f.application_rk is not null
      and f.application_rk <> -1
      and f.deal_issue_date is not null
)
select
    cast('ALL' as text) as product_scope,
    cast(null as text) as level25_product_bp_nm,
    count(distinct row(questionnaire_rk, parent_application_rk, application_rk))
        as full_chain_count,
    count(*) as full_chain_row_count
from full_chains

union all

select
    cast('PRODUCT' as text) as product_scope,
    level25_product_bp_nm,
    count(distinct row(questionnaire_rk, parent_application_rk, application_rk))
        as full_chain_count,
    count(*) as full_chain_row_count
from full_chains
group by level25_product_bp_nm
order by product_scope, level25_product_bp_nm;
