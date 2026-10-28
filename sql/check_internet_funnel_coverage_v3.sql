/*
Короткие проверки V3: каждый SELECT запускать ОТДЕЛЬНО.
Нет макропеременных и создаваемых таблиц. Источник — итог V3 в sbx_pre_orb_fd.
В одном запросе только один COUNT(DISTINCT); память на проде не измерялась.
RK = -1 обозначает отсутствие сущности и не входит в соответствующий счётчик.
Первый процент = результат 2 / результат 1 * 100.
Обратный процент = результат 4 / результат 3 * 100.
Это покрытие отобранных сущностей итоговой витрины, а не всех строк банка.
*/

-- 1. Все уникальные анкеты.
select count(distinct questionnaire_rk) as questionnaire_count
from sbx_pre_orb_fd.man_prt_tif_tech_internet_funnel
where questionnaire_rk <> -1;

-- 2. Уникальные анкеты, для которых найдена заявка TAS.
select count(distinct questionnaire_rk) as linked_questionnaire_count
from sbx_pre_orb_fd.man_prt_tif_tech_internet_funnel
where questionnaire_rk <> -1
  and (parent_application_rk <> -1 or application_rk <> -1);

-- 3. Все уникальные заявочные пары, включая родителя без дочерней заявки.
select count(distinct row(parent_application_rk, application_rk)) as application_count
from sbx_pre_orb_fd.man_prt_tif_tech_internet_funnel
where parent_application_rk <> -1 or application_rk <> -1;

-- 4. Уникальные заявочные пары, для которых найдена анкета.
select count(distinct row(parent_application_rk, application_rk)) as linked_application_count
from sbx_pre_orb_fd.man_prt_tif_tech_internet_funnel
where questionnaire_rk <> -1
  and (parent_application_rk <> -1 or application_rk <> -1);

-- 5. Ошибки заполнения ключей; ожидается 0.
select count(*) as invalid_key_count
from sbx_pre_orb_fd.man_prt_tif_tech_internet_funnel
where questionnaire_rk is null
   or parent_application_rk is null
   or application_rk is null
   or (questionnaire_rk = -1 and parent_application_rk = -1 and application_rk = -1);

-- 6. Связанные анкеты с флагом, отличным от true; ожидается 0.
select count(*) as invalid_linked_flag_count
from sbx_pre_orb_fd.man_prt_tif_tech_internet_funnel
where questionnaire_rk <> -1
  and (parent_application_rk <> -1 or application_rk <> -1)
  and quest_verification_flg is distinct from true;

-- 7. Заявки без анкеты с заполненным флагом анкеты; ожидается 0.
select count(*) as invalid_missing_questionnaire_flag_count
from sbx_pre_orb_fd.man_prt_tif_tech_internet_funnel
where questionnaire_rk = -1 and quest_verification_flg is not null;
