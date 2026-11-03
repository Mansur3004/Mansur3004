/*
Проверки актуального V4. Каждый SELECT выполнять отдельно; таблицы не создаются.
Сначала проверить уникальность источников, затем сохранность и покрытия.
NULL / -1 не считаются реальными ключами. Разрез продуктов для анкет берётся
из анкетной ветки, для заявок — из TAS, а не из общего числа строк финала.
*/

-- 1. Исторический ключ TQS включает effective_from_dttm, а не только RK.
select questionnaire_rk, effective_from_dttm, count(*) as row_count
from dm_pik_fd_cdmr.tech_questionnaire_status
group by questionnaire_rk, effective_from_dttm
having count(*) > 1;

-- 2. TAS хранит последнее состояние; повторы пары ключей требуют разбора, не DISTINCT.
select coalesce(parent_application_rk, -1) as parent_application_rk,
       coalesce(application_rk, -1) as application_rk, count(*) as row_count
from dm_pik_fd_cdmr.tech_application_status
where level25_product_bp_nm in ('Потребкредит', 'Кредитные карты', 'Автокредит')
group by coalesce(parent_application_rk, -1), coalesce(application_rk, -1)
having count(*) > 1;

-- 3. Ключ строки итогового снимка; ожидается пустой результат при уникальной TAS.
select questionnaire_rk, parent_application_rk, application_rk, count(*) as row_count
from sbx_pre_orb_fd.man_prt_tif_tech_internet_funnel
group by questionnaire_rk, parent_application_rk, application_rk
having count(*) > 1;

-- 4. Заполнение ключей; ожидается 0.
select count(*) as invalid_keys
from sbx_pre_orb_fd.man_prt_tif_tech_internet_funnel
where questionnaire_rk is null or parent_application_rk is null or application_rk is null
   or (questionnaire_rk = -1 and parent_application_rk = -1 and application_rk = -1);

-- 5. Уже связанные пары не должны повторно попадать в оставшиеся заявки; ожидается 0.
select count(*) as repeated_linked_applications
from sbx_pre_orb_fd.man_prt_tif_remaining_tas t
where exists (
    select 1 from sbx_pre_orb_fd.man_prt_tif_questionnaire_funnel q
    where q.parent_application_rk = t.parent_application_rk
      and q.application_rk = t.application_rk
);

-- 6. При найденной связи флаг true; ожидается 0.
select count(*) as invalid_linked_flags
from sbx_pre_orb_fd.man_prt_tif_tech_internet_funnel
where questionnaire_rk <> -1
  and (parent_application_rk <> -1 or application_rk <> -1)
  and quest_verification_flg is distinct from true;

-- 7. Без анкеты флаг NULL; ожидается 0.
select count(*) as invalid_missing_questionnaire_flags
from sbx_pre_orb_fd.man_prt_tif_tech_internet_funnel
where questionnaire_rk = -1 and quest_verification_flg is not null;

-- 8. Все анкеты по продуктам; один COUNT DISTINCT в запросе.
with q as (
    select questionnaire_rk, level25_product_bp_nm
    from sbx_pre_orb_fd.man_prt_tif_kn_kk_questionnaire
    union all
    select questionnaire_rk, level25_product_bp_nm
    from sbx_pre_orb_fd.man_prt_tif_auto_verification
)
select level25_product_bp_nm, count(distinct questionnaire_rk) as questionnaire_count
from q
group by level25_product_bp_nm;

-- 9. Связанные анкеты по исходному продукту анкеты.
with q as (
    select questionnaire_rk, level25_product_bp_nm
    from sbx_pre_orb_fd.man_prt_tif_kn_kk_matches
    union all
    select questionnaire_rk, level25_product_bp_nm
    from sbx_pre_orb_fd.man_prt_tif_auto_fin
    where parent_application_rk <> -1 or application_rk <> -1
)
select level25_product_bp_nm, count(distinct questionnaire_rk) as linked_questionnaire_count
from q
group by level25_product_bp_nm;

-- 10. Все заявочные пары по продуктам TAS.
with t as (
    select parent_application_rk, application_rk, level25_product_bp_nm
    from sbx_pre_orb_fd.man_prt_tif_kn_kk_tas
    union all
    select parent_application_rk, application_rk, level25_product_bp_nm
    from sbx_pre_orb_fd.man_prt_tif_auto_tas
)
select level25_product_bp_nm,
       count(distinct row(parent_application_rk, application_rk)) as application_count
from t
group by level25_product_bp_nm;

-- 11. Связанные заявочные пары по исходному продукту TAS, как в знаменателе 10.
-- NULL-продукт источника показывается отдельной группой, без смены знаменателя.
with t as (
    select parent_application_rk, application_rk, level25_product_bp_nm
    from sbx_pre_orb_fd.man_prt_tif_kn_kk_tas
    union all
    select parent_application_rk, application_rk, level25_product_bp_nm
    from sbx_pre_orb_fd.man_prt_tif_auto_tas
)
select t.level25_product_bp_nm,
       count(distinct row(t.parent_application_rk, t.application_rk)) as linked_application_count
from t
where exists (
    select 1 from sbx_pre_orb_fd.man_prt_tif_questionnaire_funnel f
    where f.parent_application_rk = t.parent_application_rk
      and f.application_rk = t.application_rk
)
group by t.level25_product_bp_nm;

-- 12. Пропавшие заявочные пары; ожидается пустой результат.
with t as (
    select parent_application_rk, application_rk
    from sbx_pre_orb_fd.man_prt_tif_kn_kk_tas
    union all
    select parent_application_rk, application_rk
    from sbx_pre_orb_fd.man_prt_tif_auto_tas
)
select t.parent_application_rk, t.application_rk
from t
where not exists (
    select 1 from sbx_pre_orb_fd.man_prt_tif_tech_internet_funnel f
    where f.parent_application_rk = t.parent_application_rk
      and f.application_rk = t.application_rk
);
