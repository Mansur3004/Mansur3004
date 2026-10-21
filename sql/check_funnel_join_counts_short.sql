/* Запускать запросы ПО ОДНОМУ, не параллельно. Только чтение; новых таблиц нет.
   &db_sbx = sbx_pre_orb_fd; &P_BEGIN_DATE — как в проверяемом запуске.
   Имена prt_if2_* — из последнего V2; если переименованы, заменить на свои.
   Все промежуточные таблицы должны относиться к одному запуску.
   Даже один COUNT DISTINCT требует памяти; несколько таких счетчиков не объединять. */

-- 1–2. КН/КК: сколько ID было до получения RK и сколько получило непустой RK.
select count(distinct questionnaire_id) as ids_before_rk
from &db_sbx.prt_if2_tqs_questionnaire_all
where questionnaire_dttm >= cast(&P_BEGIN_DATE as timestamp) or questionnaire_dttm is null;

select count(distinct questionnaire_id) as ids_with_rk
from &db_sbx.prt_if2_tech_questionnaire_status
where questionnaire_rk is not null
  and (questionnaire_dttm >= cast(&P_BEGIN_DATE as timestamp) or questionnaire_dttm is null);

-- 3–6. КН/КК: база анкет -> есть номер -> найден BDM -> найдена TAS.
select count(distinct questionnaire_rk) as kn_kk_q_total
from &db_sbx.prt_if2_kn_kk_bdm;

select count(distinct questionnaire_rk) as kn_kk_q_with_number
from &db_sbx.prt_if2_kn_kk_bdm where application_num is not null;

select count(distinct questionnaire_rk) as kn_kk_q_found_bdm
from &db_sbx.prt_if2_kn_kk_bdm where bdm_application_rk is not null;

select count(distinct q_questionnaire_rk) as kn_kk_q_found_tas
from &db_sbx.prt_if2_kn_kk_matches;

-- 7–8. Авто: база анкет и сколько получило хотя бы один заявочный RK.
select count(distinct questionnaire_rk) as auto_q_total
from &db_sbx.prt_if2_auto_verification;

select count(distinct questionnaire_rk) as auto_q_found_tas
from &db_sbx.prt_if2_auto_fin
where parent_application_rk is not null or application_rk is not null;

-- 9–11. TAS КН/КК: база пар -> сохранено после JOIN -> связано с анкетой.
select count(distinct row(parent_application_rk, application_rk)) as kn_kk_a_before
from &db_sbx.prt_if2_kn_kk_tas
where parent_application_rk is not null or application_rk is not null;

select count(distinct row(parent_application_rk, application_rk)) as kn_kk_a_after
from &db_sbx.prt_if2_kn_kk_fin
where parent_application_rk is not null or application_rk is not null;

select count(distinct row(parent_application_rk, application_rk)) as kn_kk_a_linked
from &db_sbx.prt_if2_kn_kk_fin
where questionnaire_rk is not null
  and (parent_application_rk is not null or application_rk is not null);

-- 12–14. TAS авто: те же три счетчика.
select count(distinct row(parent_application_rk, application_rk)) as auto_a_before
from &db_sbx.prt_if2_auto_tas
where parent_application_rk is not null or application_rk is not null;

select count(distinct row(parent_application_rk, application_rk)) as auto_a_after
from &db_sbx.prt_if2_auto_fin
where parent_application_rk is not null or application_rk is not null;

select count(distinct row(parent_application_rk, application_rk)) as auto_a_linked
from &db_sbx.prt_if2_auto_fin
where questionnaire_rk is not null
  and (parent_application_rk is not null or application_rk is not null);
