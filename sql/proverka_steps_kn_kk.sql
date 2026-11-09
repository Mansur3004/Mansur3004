/*
ПРОВЕРКА КАЖДОГО ШАГА TIF V5 ДЛЯ КН / КК: ГДЕ НЕ НАХОДЯТСЯ СВЯЗИ.
Только независимые SELECT COUNT(...) WHERE ...; таблицы не создаются и не меняются.
Каждый SELECT можно выполнить отдельно после полного построения V5.
Проверяется основной маршрут через application_num -> BDM -> TAS.parent_application_rk.

Параметры SQL-клиента:
  &p_product = 'Потребкредит' — выполнить для КН;
  &p_product = 'Кредитные карты' — затем повторить для КК.
  &db_sbx = sbx_pre_orb_fd; &p_db_cdmr = dm_pik_fd_cdmr;
  &p_db_rawd = rd_raw_orb; &p_db_bdm = bdm;
  &p_max_date = '2999-12-31'; &P_BEGIN_DATE = '2025-01-01'.
Дата начала ОБЯЗАТЕЛЬНО должна совпадать с проверяемым запуском V5.
Если рабочие таблицы без v5_, заменить man_prt_tif_v5_ на man_prt_tif_.
Для старых структур matches проверкам выдачи нужны application_rk/deal_issue_date.
Источник и промежуточные таблицы должны соответствовать одному состоянию данных.

Единицы счёта:
  questionnaires — уникальные RK анкет; application_pairs — пары ключей TAS;
  links — тройки анкета/родитель/заявка; source_rows — физические строки.
Нельзя вычитать число заявок из числа анкет: связь может быть 1:N.
COUNT DISTINCT здесь задаёт единицу измерения, а не исправляет рабочие данные.
Продукт анкет всегда берётся из анкетной базы, заявок — из TAS.
Для проверки сохранности в финале продукт финальной строки не ограничивается:
TAS может переопределить продукт анкеты. NULL-продукт исходной TAS требует
отдельного анализа и не приписывается автоматически одному из КН/КК.

Быстрый маршрут (одинаковая единица — анкеты):
  08 -> 13 -> 18 -> 26 -> 33.
  08 — база; 13 — есть номер; 18 — есть BDM; 26 — есть TAS; 33 — есть выдача.
Где сильнее падает число, там смотреть соседние причины.
Полезные сверки при корректных уникальных ключах и согласованном срезе:
  08 = 10 + 11 + 12 + 13;
  13 = 14 + 15 + 16 + 17 + 18;
  18 = 19 + 26; 19 = 20 + 21 + 22 + 23 + 24 + 25;
  26 = 31 + 32 + 33.

Со стороны заявок:
  38 = 40 + 41; 41 = сумма 42..49; 38 = 54, 53 = 0.
Классификация считает анкету/пару один раз по ПЕРВОМУ недостигнутому этапу,
учитывая ВСЕ её возможные пути. Нельзя считать потерей неудачный путь,
если для той же сущности нашёлся другой успешный путь.
Сверки выявляют и несогласованность промежуточных таблиц; они не заменяют
проверку уникальности TQS/TAS. Значения 06/23/36 — отбор по периоду;
31/32 — результат прохождения воронки, а не доказанная ошибка JOIN.
Флаг верификации не фильтрует базу анкет и не является обязательным условием выдачи.
Проверки 45..47 читают RAW и могут быть тяжелее простых счётчиков готовых таблиц.
*/

-- 01. 1.1 verification: уникальные анкеты в истории TQS для продукта
select '01' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &p_db_cdmr.tech_questionnaire_status q
where q.level25_product_bp_nm = &p_product
  and q.questionnaire_rk is not null and q.questionnaire_rk <> -1;

-- 02. 1.1 verification: анкеты, попавшие в расчёт флага
select '02' as check_id, &p_product as product,
       count(distinct v.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_verification v
where v.level25_product_bp_nm = &p_product;

-- 03. 1.1 verification: анкеты истории без строки флага; ожидается 0
select '03' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &p_db_cdmr.tech_questionnaire_status q
where q.level25_product_bp_nm = &p_product
  and q.questionnaire_rk is not null and q.questionnaire_rk <> -1
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_verification v
    where v.questionnaire_rk = q.questionnaire_rk
      and v.level25_product_bp_nm = q.level25_product_bp_nm
);

-- 04. 1.2 questionnaire: текущие строки TQS без реального RK; единица — строки
select '04' as check_id, &p_product as product,
       count(*) as source_rows
from &p_db_cdmr.tech_questionnaire_status q
where q.level25_product_bp_nm = &p_product
  and q.effective_to_dttm = cast(&p_max_date as timestamp)
  and (q.questionnaire_rk is null or q.questionnaire_rk = -1);

-- 05. 1.2 questionnaire: все текущие анкеты продукта до отбора периода
select '05' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &p_db_cdmr.tech_questionnaire_status q
where q.level25_product_bp_nm = &p_product
  and q.effective_to_dttm = cast(&p_max_date as timestamp)
  and q.questionnaire_rk is not null and q.questionnaire_rk <> -1;

-- 06. 1.2 questionnaire: текущие анкеты ДО начала периода; плановое исключение
select '06' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &p_db_cdmr.tech_questionnaire_status q
where q.level25_product_bp_nm = &p_product
  and q.effective_to_dttm = cast(&p_max_date as timestamp)
  and q.questionnaire_rk is not null and q.questionnaire_rk <> -1
  and q.questionnaire_dttm < cast(&P_BEGIN_DATE as timestamp);

-- 07. 1.2 questionnaire: текущие анкеты в периоде, включая NULL-даты
select '07' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &p_db_cdmr.tech_questionnaire_status q
where q.level25_product_bp_nm = &p_product
  and q.effective_to_dttm = cast(&p_max_date as timestamp)
  and q.questionnaire_rk is not null and q.questionnaire_rk <> -1
  and (q.questionnaire_dttm >= cast(&P_BEGIN_DATE as timestamp) or q.questionnaire_dttm is null);

-- 08. 1.2 questionnaire: подготовленная база анкет
select '08' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product;

-- 09. 1.2 questionnaire: подходящие анкеты TQS отсутствуют в базе; ожидается 0
select '09' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &p_db_cdmr.tech_questionnaire_status q
where q.level25_product_bp_nm = &p_product
  and q.effective_to_dttm = cast(&p_max_date as timestamp)
  and q.questionnaire_rk is not null and q.questionnaire_rk <> -1
  and (q.questionnaire_dttm >= cast(&P_BEGIN_DATE as timestamp) or q.questionnaire_dttm is null)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_questionnaire b
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
);

-- 10. 1.3 questionnaire_numbers: нет ни одной строки intention по ID анкеты
select '10' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and not exists (
    select 1 from &p_db_rawd.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention r
    where r.questionnaire_id = q.questionnaire_id
);

-- 11. 1.3 questionnaire_numbers: intention есть, но все application_num NULL
select '11' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &p_db_rawd.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention r
    where r.questionnaire_id = q.questionnaire_id
)
  and not exists (
    select 1 from &p_db_rawd.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention r
    where r.questionnaire_id = q.questionnaire_id and r.application_num is not null
);

-- 12. 1.3 questionnaire_numbers: непустой номер в RAW есть, в мосте нет; ожидается 0
select '12' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &p_db_rawd.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention r
    where r.questionnaire_id = q.questionnaire_id and r.application_num is not null
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_questionnaire_numbers n
    where n.questionnaire_id = q.questionnaire_id and n.application_num is not null
);

-- 13. 1.3 questionnaire_numbers: анкеты с выбранным непустым номером
select '13' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_questionnaire_numbers n
    where n.questionnaire_id = q.questionnaire_id and n.application_num is not null
);

-- 14. 1.4 kn_kk_bdm: номер выбран, но отсутствует в BDM во всех версиях
select '14' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_questionnaire_numbers n
    where n.questionnaire_id = q.questionnaire_id and n.application_num is not null
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_questionnaire_numbers n
    inner join &p_db_bdm.application app on app.application_num = n.application_num
    where n.questionnaire_id = q.questionnaire_id
      and n.application_num is not null
);

-- 15. 1.4 kn_kk_bdm: номер есть только в исторических версиях BDM
select '15' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_questionnaire_numbers n
    inner join &p_db_bdm.application app on app.application_num = n.application_num
    where n.questionnaire_id = q.questionnaire_id
      and n.application_num is not null
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_questionnaire_numbers n
    inner join &p_db_bdm.application app on app.application_num = n.application_num
    where n.questionnaire_id = q.questionnaire_id
      and n.application_num is not null
      and app.effective_to_date = cast(&p_max_date as date)
);

-- 16. 1.4 kn_kk_bdm: текущие совпадения BDM есть, но у всех RK NULL/-1
select '16' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_questionnaire_numbers n
    inner join &p_db_bdm.application app on app.application_num = n.application_num
    where n.questionnaire_id = q.questionnaire_id
      and n.application_num is not null
      and app.effective_to_date = cast(&p_max_date as date)
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_questionnaire_numbers n
    inner join &p_db_bdm.application app on app.application_num = n.application_num
    where n.questionnaire_id = q.questionnaire_id
      and n.application_num is not null
      and app.effective_to_date = cast(&p_max_date as date)
      and app.application_rk is not null and app.application_rk <> -1
);

-- 17. 1.4 kn_kk_bdm: BDM подходит, но в подготовленной таблице связи нет; ожидается 0
select '17' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_questionnaire_numbers n
    inner join &p_db_bdm.application app on app.application_num = n.application_num
    where n.questionnaire_id = q.questionnaire_id
      and n.application_num is not null
      and app.effective_to_date = cast(&p_max_date as date)
      and app.application_rk is not null and app.application_rk <> -1
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
);

-- 18. 1.4 kn_kk_bdm: анкеты с подготовленной связью BDM
select '18' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
);

-- 19. 2.1 matches: есть BDM, но нет найденной связи с TAS
select '19' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.questionnaire_rk = q.questionnaire_rk
      and m.level25_product_bp_nm = q.level25_product_bp_nm
);

-- 20. 2.1 matches: ни один ключ BDM не найден как родитель в исходной TAS
select '20' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.questionnaire_rk = q.questionnaire_rk
      and m.level25_product_bp_nm = q.level25_product_bp_nm
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    inner join &p_db_cdmr.tech_application_status t on t.parent_application_rk = b.bdm_application_rk
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
);

-- 21. 2.1 matches: родитель найден, но нет совпадения parent_src_cd
select '21' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.questionnaire_rk = q.questionnaire_rk
      and m.level25_product_bp_nm = q.level25_product_bp_nm
)
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    inner join &p_db_cdmr.tech_application_status t on t.parent_application_rk = b.bdm_application_rk
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    inner join &p_db_cdmr.tech_application_status t on t.parent_application_rk = b.bdm_application_rk
      and t.parent_src_cd = b.bdm_src_cd
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
);

-- 22. 2.1 matches: родитель/источник найдены, но все продукты TAS вне КН/КК/NULL
select '22' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.questionnaire_rk = q.questionnaire_rk
      and m.level25_product_bp_nm = q.level25_product_bp_nm
)
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    inner join &p_db_cdmr.tech_application_status t on t.parent_application_rk = b.bdm_application_rk
      and t.parent_src_cd = b.bdm_src_cd
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    inner join &p_db_cdmr.tech_application_status t on t.parent_application_rk = b.bdm_application_rk
      and t.parent_src_cd = b.bdm_src_cd
      and (t.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты') or t.level25_product_bp_nm is null)
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
);

-- 23. 1.5 tas: подходящие связи есть только ДО начала периода TAS
select '23' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.questionnaire_rk = q.questionnaire_rk
      and m.level25_product_bp_nm = q.level25_product_bp_nm
)
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    inner join &p_db_cdmr.tech_application_status t on t.parent_application_rk = b.bdm_application_rk
      and t.parent_src_cd = b.bdm_src_cd
      and (t.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты') or t.level25_product_bp_nm is null)
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    inner join &p_db_cdmr.tech_application_status t on t.parent_application_rk = b.bdm_application_rk
      and t.parent_src_cd = b.bdm_src_cd
      and (t.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты') or t.level25_product_bp_nm is null)
      and (coalesce(t.application_dt, t.parent_application_dt) >= cast(&P_BEGIN_DATE as date)
           or coalesce(t.application_dt, t.parent_application_dt) is null)
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
);

-- 24. 1.5 tas: подходящая исходная TAS есть, в подготовленной TAS нет; ожидается 0
select '24' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.questionnaire_rk = q.questionnaire_rk
      and m.level25_product_bp_nm = q.level25_product_bp_nm
)
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    inner join &p_db_cdmr.tech_application_status t on t.parent_application_rk = b.bdm_application_rk
      and t.parent_src_cd = b.bdm_src_cd
      and (t.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты') or t.level25_product_bp_nm is null)
      and (coalesce(t.application_dt, t.parent_application_dt) >= cast(&P_BEGIN_DATE as date)
           or coalesce(t.application_dt, t.parent_application_dt) is null)
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    inner join &db_sbx.man_prt_tif_v5_tas t on t.parent_application_rk = b.bdm_application_rk
      and t.parent_src_cd = b.bdm_src_cd
      and (t.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты') or t.level25_product_bp_nm is null)
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
);

-- 25. 2.1 matches: подготовленные BDM и TAS соединяются, но matches пуст; ожидается 0
select '25' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.questionnaire_rk = q.questionnaire_rk
      and m.level25_product_bp_nm = q.level25_product_bp_nm
)
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    inner join &db_sbx.man_prt_tif_v5_tas t on t.parent_application_rk = b.bdm_application_rk
      and t.parent_src_cd = b.bdm_src_cd
      and (t.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты') or t.level25_product_bp_nm is null)
    where b.questionnaire_rk = q.questionnaire_rk
      and b.level25_product_bp_nm = q.level25_product_bp_nm
);

-- 26. 2.1 matches: анкеты с хотя бы одной найденной связью
select '26' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.questionnaire_rk = q.questionnaire_rk
      and m.level25_product_bp_nm = q.level25_product_bp_nm
);

-- 27. 2.2 questionnaire_funnel: анкеты базы, потерянные после LEFT JOIN; ожидается 0
select '27' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_questionnaire_funnel f
    where f.questionnaire_rk = q.questionnaire_rk
);

-- 28. 2.2 questionnaire_funnel: найденные связи не перенесены в анкетную часть; ожидается 0
select '28' as check_id, &p_product as product,
       count(distinct row(m.questionnaire_rk, m.parent_application_rk, m.application_rk)) as links
from &db_sbx.man_prt_tif_v5_matches m
where m.level25_product_bp_nm = &p_product
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_questionnaire_funnel f
    where f.questionnaire_rk = m.questionnaire_rk
      and f.parent_application_rk = m.parent_application_rk
      and f.application_rk = m.application_rk
);

-- 29. 2.4 tech_internet_funnel: анкеты базы отсутствуют в финале; ожидается 0
select '29' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_tech_internet_funnel f
    where f.questionnaire_rk = q.questionnaire_rk
);

-- 30. 2.4 tech_internet_funnel: найденные связи отсутствуют в финале; ожидается 0
select '30' as check_id, &p_product as product,
       count(distinct row(m.questionnaire_rk, m.parent_application_rk, m.application_rk)) as links
from &db_sbx.man_prt_tif_v5_matches m
where m.level25_product_bp_nm = &p_product
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_tech_internet_funnel f
    where f.questionnaire_rk = m.questionnaire_rk
      and f.parent_application_rk = m.parent_application_rk
      and f.application_rk = m.application_rk
);

-- 31. Результат связи: найден только родитель, дочерней заявки нет
select '31' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.questionnaire_rk = q.questionnaire_rk
      and m.level25_product_bp_nm = q.level25_product_bp_nm
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.questionnaire_rk = q.questionnaire_rk
      and m.level25_product_bp_nm = q.level25_product_bp_nm
      and m.application_rk is not null and m.application_rk <> -1
);

-- 32. Результат связи: дочерняя заявка есть, но ни у одной нет даты выдачи
select '32' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.questionnaire_rk = q.questionnaire_rk
      and m.level25_product_bp_nm = q.level25_product_bp_nm
      and m.application_rk is not null and m.application_rk <> -1
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.questionnaire_rk = q.questionnaire_rk
      and m.level25_product_bp_nm = q.level25_product_bp_nm
      and m.application_rk is not null and m.application_rk <> -1
      and m.deal_issue_date is not null
);

-- 33. Результат связи: анкеты, по которым есть хотя бы одна выдача
select '33' as check_id, &p_product as product,
       count(distinct q.questionnaire_rk) as questionnaires
from &db_sbx.man_prt_tif_v5_questionnaire q
where q.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.questionnaire_rk = q.questionnaire_rk
      and m.level25_product_bp_nm = q.level25_product_bp_nm
      and m.application_rk is not null and m.application_rk <> -1
      and m.deal_issue_date is not null
);

-- 34. 1.5 tas: строки исходной TAS без обоих ключей; единица — строки
select '34' as check_id, &p_product as product,
       count(*) as source_rows
from &p_db_cdmr.tech_application_status t
where t.level25_product_bp_nm = &p_product
  and not (coalesce(t.parent_application_rk, -1) <> -1 or coalesce(t.application_rk, -1) <> -1);

-- 35. 1.5 tas: все реальные пары исходной TAS до отбора периода
select '35' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &p_db_cdmr.tech_application_status t
where t.level25_product_bp_nm = &p_product
  and (coalesce(t.parent_application_rk, -1) <> -1 or coalesce(t.application_rk, -1) <> -1);

-- 36. 1.5 tas: реальные пары TAS ДО начала периода; плановое исключение
select '36' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &p_db_cdmr.tech_application_status t
where t.level25_product_bp_nm = &p_product
  and (coalesce(t.parent_application_rk, -1) <> -1 or coalesce(t.application_rk, -1) <> -1)
  and coalesce(t.application_dt, t.parent_application_dt) < cast(&P_BEGIN_DATE as date);

-- 37. 1.5 tas: реальные пары исходной TAS в периоде
select '37' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &p_db_cdmr.tech_application_status t
where t.level25_product_bp_nm = &p_product
  and (coalesce(t.parent_application_rk, -1) <> -1 or coalesce(t.application_rk, -1) <> -1)
  and (coalesce(t.application_dt, t.parent_application_dt) >= cast(&P_BEGIN_DATE as date)
       or coalesce(t.application_dt, t.parent_application_dt) is null);

-- 38. 1.5 tas: подготовленная база пар TAS
select '38' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &db_sbx.man_prt_tif_v5_tas t
where t.level25_product_bp_nm = &p_product;

-- 39. 1.5 tas: подходящие исходные пары не попали в подготовленную TAS; ожидается 0
select '39' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &p_db_cdmr.tech_application_status t
where t.level25_product_bp_nm = &p_product
  and (coalesce(t.parent_application_rk, -1) <> -1 or coalesce(t.application_rk, -1) <> -1)
  and (coalesce(t.application_dt, t.parent_application_dt) >= cast(&P_BEGIN_DATE as date)
       or coalesce(t.application_dt, t.parent_application_dt) is null)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_tas f
    where f.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and f.application_rk = coalesce(t.application_rk, -1)
);

-- 40. 2.1 matches: пары TAS с найденной анкетой КН/КК
select '40' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &db_sbx.man_prt_tif_v5_tas t
where t.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and m.application_rk = coalesce(t.application_rk, -1)
      and m.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
);

-- 41. 2.1 matches: пары TAS без найденной анкеты КН/КК
select '41' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &db_sbx.man_prt_tif_v5_tas t
where t.level25_product_bp_nm = &p_product
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and m.application_rk = coalesce(t.application_rk, -1)
      and m.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
);

-- 42. Заявки без анкеты: отсутствует родительский RK
select '42' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &db_sbx.man_prt_tif_v5_tas t
where t.level25_product_bp_nm = &p_product
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and m.application_rk = coalesce(t.application_rk, -1)
      and m.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
)
  and not (t.parent_application_rk is not null and t.parent_application_rk <> -1);

-- 43. Заявки без анкеты: родитель/источник отсутствуют в BDM во всех версиях
select '43' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &db_sbx.man_prt_tif_v5_tas t
where t.level25_product_bp_nm = &p_product
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and m.application_rk = coalesce(t.application_rk, -1)
      and m.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
)
  and t.parent_application_rk is not null and t.parent_application_rk <> -1
  and not exists (
    select 1 from &p_db_bdm.application app
    where app.application_rk = t.parent_application_rk
      and app.src_cd = t.parent_src_cd
);

-- 44. Заявки без анкеты: родитель/источник есть только в истории BDM
select '44' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &db_sbx.man_prt_tif_v5_tas t
where t.level25_product_bp_nm = &p_product
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and m.application_rk = coalesce(t.application_rk, -1)
      and m.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
)
  and t.parent_application_rk is not null and t.parent_application_rk <> -1
  and exists (
    select 1 from &p_db_bdm.application app
    where app.application_rk = t.parent_application_rk
      and app.src_cd = t.parent_src_cd
)
  and not exists (
    select 1 from &p_db_bdm.application app
    where app.application_rk = t.parent_application_rk
      and app.src_cd = t.parent_src_cd
      and app.effective_to_date = cast(&p_max_date as date)
);

-- 45. Заявки без анкеты: ни один текущий номер родителя не найден в intention
select '45' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &db_sbx.man_prt_tif_v5_tas t
where t.level25_product_bp_nm = &p_product
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and m.application_rk = coalesce(t.application_rk, -1)
      and m.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
)
  and t.parent_application_rk is not null and t.parent_application_rk <> -1
  and exists (
    select 1 from &p_db_bdm.application app
    where app.application_rk = t.parent_application_rk
      and app.src_cd = t.parent_src_cd
      and app.effective_to_date = cast(&p_max_date as date)
)
  and not exists (
    select 1 from &p_db_bdm.application app
    inner join &p_db_rawd.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention r on r.application_num = app.application_num
    where app.application_rk = t.parent_application_rk
      and app.src_cd = t.parent_src_cd
      and app.effective_to_date = cast(&p_max_date as date)
);

-- 46. Заявки без анкеты: номер есть в intention, но ID не в отобранной базе TQS КН/КК
select '46' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &db_sbx.man_prt_tif_v5_tas t
where t.level25_product_bp_nm = &p_product
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and m.application_rk = coalesce(t.application_rk, -1)
      and m.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
)
  and t.parent_application_rk is not null and t.parent_application_rk <> -1
  and exists (
    select 1 from &p_db_bdm.application app
    inner join &p_db_rawd.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention r on r.application_num = app.application_num
    where app.application_rk = t.parent_application_rk
      and app.src_cd = t.parent_src_cd
      and app.effective_to_date = cast(&p_max_date as date)
)
  and not exists (
    select 1 from &p_db_bdm.application app
    inner join &p_db_rawd.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention r on r.application_num = app.application_num
    inner join &db_sbx.man_prt_tif_v5_questionnaire q on q.questionnaire_id = r.questionnaire_id
    where app.application_rk = t.parent_application_rk
      and app.src_cd = t.parent_src_cd
      and app.effective_to_date = cast(&p_max_date as date)
      and q.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
);

-- 47. Заявки без анкеты: RAW связан с базой TQS, но номер не выбран в мосте
select '47' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &db_sbx.man_prt_tif_v5_tas t
where t.level25_product_bp_nm = &p_product
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and m.application_rk = coalesce(t.application_rk, -1)
      and m.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
)
  and t.parent_application_rk is not null and t.parent_application_rk <> -1
  and exists (
    select 1 from &p_db_bdm.application app
    inner join &p_db_rawd.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention r on r.application_num = app.application_num
    inner join &db_sbx.man_prt_tif_v5_questionnaire q on q.questionnaire_id = r.questionnaire_id
    where app.application_rk = t.parent_application_rk
      and app.src_cd = t.parent_src_cd
      and app.effective_to_date = cast(&p_max_date as date)
      and q.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
)
  and not exists (
    select 1 from &p_db_bdm.application app
    inner join &db_sbx.man_prt_tif_v5_questionnaire_numbers n on n.application_num = app.application_num
    inner join &db_sbx.man_prt_tif_v5_questionnaire q on q.questionnaire_id = n.questionnaire_id
    where app.application_rk = t.parent_application_rk
      and app.src_cd = t.parent_src_cd
      and app.effective_to_date = cast(&p_max_date as date)
      and q.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
);

-- 48. Заявки без анкеты: выбранный номер соединяется с BDM, но связь не подготовлена; ожидается 0
select '48' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &db_sbx.man_prt_tif_v5_tas t
where t.level25_product_bp_nm = &p_product
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and m.application_rk = coalesce(t.application_rk, -1)
      and m.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
)
  and t.parent_application_rk is not null and t.parent_application_rk <> -1
  and exists (
    select 1 from &p_db_bdm.application app
    inner join &db_sbx.man_prt_tif_v5_questionnaire_numbers n on n.application_num = app.application_num
    inner join &db_sbx.man_prt_tif_v5_questionnaire q on q.questionnaire_id = n.questionnaire_id
    where app.application_rk = t.parent_application_rk
      and app.src_cd = t.parent_src_cd
      and app.effective_to_date = cast(&p_max_date as date)
      and q.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    where b.bdm_application_rk = t.parent_application_rk
      and b.bdm_src_cd = t.parent_src_cd
      and b.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
);

-- 49. Заявки без анкеты: подготовленная BDM соединяется с TAS, но matches нет; ожидается 0
select '49' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &db_sbx.man_prt_tif_v5_tas t
where t.level25_product_bp_nm = &p_product
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and m.application_rk = coalesce(t.application_rk, -1)
      and m.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
)
  and t.parent_application_rk is not null and t.parent_application_rk <> -1
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_kn_kk_bdm b
    where b.bdm_application_rk = t.parent_application_rk
      and b.bdm_src_cd = t.parent_src_cd
      and b.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
);

-- 50. 2.3 remaining_tas: несвязанные пары отсутствуют в остатке; ожидается 0
select '50' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &db_sbx.man_prt_tif_v5_tas t
where t.level25_product_bp_nm = &p_product
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and m.application_rk = coalesce(t.application_rk, -1)
      and m.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
)
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_remaining_tas f
    where f.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and f.application_rk = coalesce(t.application_rk, -1)
);

-- 51. 2.3 remaining_tas: уже связанные пары ошибочно добавлены в остаток; ожидается 0
select '51' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &db_sbx.man_prt_tif_v5_tas t
where t.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_matches m
    where m.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and m.application_rk = coalesce(t.application_rk, -1)
      and m.level25_product_bp_nm in ('Потребкредит', 'Кредитные карты')
)
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_remaining_tas f
    where f.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and f.application_rk = coalesce(t.application_rk, -1)
);

-- 52. 2.3 remaining_tas: число пар в остатке
select '52' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &db_sbx.man_prt_tif_v5_remaining_tas t
where t.level25_product_bp_nm = &p_product;

-- 53. 2.4 tech_internet_funnel: пары подготовленной TAS отсутствуют в финале; ожидается 0
select '53' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &db_sbx.man_prt_tif_v5_tas t
where t.level25_product_bp_nm = &p_product
  and not exists (
    select 1 from &db_sbx.man_prt_tif_v5_tech_internet_funnel f
    where f.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and f.application_rk = coalesce(t.application_rk, -1)
);

-- 54. 2.4 tech_internet_funnel: пары подготовленной TAS сохранены в финале
select '54' as check_id, &p_product as product,
       count(distinct row(coalesce(t.parent_application_rk, -1), coalesce(t.application_rk, -1))) as application_pairs
from &db_sbx.man_prt_tif_v5_tas t
where t.level25_product_bp_nm = &p_product
  and exists (
    select 1 from &db_sbx.man_prt_tif_v5_tech_internet_funnel f
    where f.parent_application_rk = coalesce(t.parent_application_rk, -1)
      and f.application_rk = coalesce(t.application_rk, -1)
);
