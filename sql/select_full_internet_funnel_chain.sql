/*
Полные цепочки «анкета -> заявка -> выдача» из готового TIF V5.
Выполнить после построения build_internet_funnel_v5.sql.
Ничего не создаёт и не изменяет; возвращает все 19 атрибутов выбранных строк.

Критерии отбора:
  - есть реальная анкета: questionnaire_rk IS NOT NULL и <> -1;
  - есть реальная заявка: application_rk IS NOT NULL и <> -1;
  - заполнена дата выдачи: deal_issue_date IS NOT NULL.

Родительский ключ не обязателен: Автокредит может соединяться без родителя.
Флаги этапов выводятся как в TAS; их обязательное равенство true не проверяется.
Полнота здесь означает наличие анкеты, связанной заявки и даты выдачи,
а не обязательное заполнение каждого промежуточного этапа.
Разные дочерние заявки сохраняются; DISTINCT / GROUP BY не используются.

Источник по умолчанию — результат V5 в sbx_pre_orb_fd.
Если рабочая таблица называется иначе, заменить только имя таблицы в FROM.
*/

select
    f.questionnaire_rk,
    f.questionnaire_dttm,
    f.quest_verification_flg,
    f.parent_application_rk,
    f.parent_application_dt,
    f.parent_open_flg,
    f.parent_prescoring_flg,
    f.parent_at_work_flg,
    f.parent_approved_flg,
    f.application_rk,
    f.application_dt,
    f.deal_issue_date,
    f.create_flg,
    f.at_work_flg,
    f.final_approved_flg,
    f.agr_signed_flg,
    f.level25_product_bp_nm,
    f.level35_product_bp_nm,
    f.processed_dttm
from sbx_pre_orb_fd.man_prt_tif_v5_tech_internet_funnel f
where f.questionnaire_rk is not null
  and f.questionnaire_rk <> -1
  and f.application_rk is not null
  and f.application_rk <> -1
  and f.deal_issue_date is not null;
