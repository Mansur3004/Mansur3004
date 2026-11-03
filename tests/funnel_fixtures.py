"""Synthetic source fixtures for the current funnel; no bank connection/data."""
import duckdb

S='sbx_pre_orb_fd'
CDMR='dm_pik_fd_cdmr'
RAW='rd_raw_orb.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention'
MACROS = {'db_sbx': 'sbx_pre_orb_fd',
 'p_db_bdm': 'bdm',
 'p_db_rawd': 'rd_raw_orb',
 'p_db_cdmr': 'dm_pik_fd_cdmr',
 'p_quest_src_cd_kn_list': "'1376%'",
 'p_quest_src_cd_kk_list': "'1383%'",
 'p_rds_report_dt_date': "'2025-01-01'",
 'p_min_dttm': "'1900-01-01 00:00:00'",
 'p_test_first_nm_like_text_list': "'%ТЕСТ%', '%ТКЕСТ%', '%ТКЕКСТ%', '%ТЕМСТ%', '%ЛИПОВЫЙ%', "
                                   "'%ЗАЯВК%', 'ПЕНСИОНН%', 'МУЛЬТИКАРТ%', 'АРХАНГЕЛЬСК%', "
                                   "'ЗВОНИТЬ%', 'AAA%'",
 'p_test_first_nm_in_text_list': "'ПЕНСЫ', 'ЛИД', 'НОВОКУЗНЕЦК', 'ТЕСТ', 'ЛЕХА', 'ДЯДЯ', 'ПРОЛД', "
                                 "'АРОПР', 'ООО'",
 'p_test_last_nm_in_text_list': "'ТЕСТ'",
 'p_test_middle_nm_like_text_list': "'ТЕСТОВНА'",
 'p_quest_product_kn_list': "'cm.LiabilityType.Loan', 'RF', 'KN'",
 'p_quest_product_kk_list': "'cm.LiabilityType.CreditCard', 'CreditCard', "
                            "'cm.LiabilityType.CreditCard cm.LiabilityType.Loan'",
 'p_quest_not_len_id_kk_list': '6',
 'P_BEGIN_DATE': "'2025-01-01'",
 'p_max_date': "'2999-12-31'",
 'p_report_timestamp': "'2026-11-03 00:00:00'",
 'p_kn_verification_status': "'0', '10.0', 'одобрено', 'CHECK_LIST_EMPTY', "
                             "'CHECK_LIST_ANTIFRAUD_OR_PRODUCT'",
 'p_kk_verification_status': "'DONE', 'COURIER'",
 'p_auto_verification_status': "'APPROVE_RKK', 'APPROVED', 'PRE_APPROVED', 'APPROVE_CALL2', "
                               "'APPROVE_CALL3', 'ORDER_CREATED', 'VERIFICATION', "
                               "'DRIVER_CARD_ISSUE', 'DRIVER_CARD_ISSUE_UPLOADED', "
                               "'DOSSIER_UPLOADED', 'DEAL_VER', 'CREDIT_ISSUED', "
                               "'PRODUCT_BASKET_SIGNED'",
 'p_quest_25lvl_product_kn_list': "'Потребкредит'",
 'p_quest_25lvl_product_kk_list': "'Кредитные карты'",
 'p_quest_25lvl_product_auto_list': "'Автокредит'"}

def make_db(integer_flags=False):
    db = duckdb.connect()
    db.execute(f'create schema {S}; create schema rd_raw_orb; create schema bdm; create schema dm_pik_fd_cdmr')
    db.execute('create macro btrim(value) as trim(value)')
    db.execute('''create table dm_pik_fd_cdmr.tech_questionnaire_x_customer (
        questionnaire_id text, questionnaire_rk bigint, effective_to_dttm timestamp)''')
    db.execute(f"""
        create table {RAW} (
            questionnaire_id text, application_num text, utmcn text, utmcmd text,
            utmcsr text, utmctr text, utmcct text, status text, scoring_status_nm text,
            prescoring_status_nm text, product_type_code text, program_type text,
            src_cd text, src_cd_src text, questionnaire_dt text, business_dt text,
            createtime_dttm text, prescoring_dt text, scoring_dt text, processed_dttm text,
            sessionintention_id text, globalclient_id text, person_id text,
            last_nm text, first_nm text, middle_nm text, tax_payer_num text, email text,
            client_type text, company_nm text, phone_num text, credit_amt numeric,
            zero_visits_flg smallint, spec_program text, salary_card_flg smallint
        );
        create table bdm.application (
            application_rk bigint, application_num text, src_cd text,
            effective_to_date date, application_begin_date date
        )
    """)
    schema_sql=f"""
        create table {S}.tech_application_status (
            parent_application_rk bigint, parent_src_cd text,
            application_rk bigint, src_cd text,
            parent_application_id text, parent_application_dt date, parent_approved_dttm timestamp,
            application_id text, application_dt date, application_type_cd text, deal_issue_date date,
            level25_product_bp_nm text, level35_product_bp_nm text,
            parent_open_flg boolean, parent_prescoring_flg boolean, parent_at_work_flg boolean,
            parent_approved_flg boolean, create_flg boolean, at_work_flg boolean,
            final_approved_flg boolean, agr_signed_flg boolean, processed_dttm timestamp
        )
    """
    if integer_flags:
        schema_sql=schema_sql.replace(' boolean',' integer')
    db.execute(schema_sql)
    return db

def add_raw(db, qid, code='KN', status='DRAFT', app_num=None, **overrides):
    data=dict(questionnaire_id=qid, application_num=app_num, utmcn='campaign',
              utmcmd='medium', utmcsr='source', utmctr='term', utmcct='content',
              status=status, scoring_status_nm='scoring', prescoring_status_nm='prescoring',
              product_type_code=code, program_type='TEST_PROGRAM', src_cd='SHARED_SOURCE',
              src_cd_src='NOT_A_PRODUCT', questionnaire_dt='2025-01-01 00:00:00',
              business_dt='2025-02-01 12:00:00', createtime_dttm='2025-02-01 12:00:00',
              prescoring_dt='2025-02-01 12:00:00', scoring_dt='2025-02-01 12:00:00',
              processed_dttm='2025-02-01 12:00:00', sessionintention_id='SESSION',
              globalclient_id='GLOBAL', person_id='PERSON', last_nm='CLIENT_LAST',
              first_nm='CLIENT_NAME', middle_nm='CLIENT_MIDDLE', tax_payer_num='SYNTHETIC',
              email='synthetic@example.invalid', client_type='CLIENT', company_nm='COMPANY',
              phone_num='SYNTHETIC_PHONE', credit_amt=100, zero_visits_flg=0,
              spec_program='PROGRAM', salary_card_flg=0)
    data.update(overrides)
    db.execute(f"insert into {RAW} ({', '.join(data)}) values ({', '.join('?' for _ in data)})", list(data.values()))

def add_tas(db,rk,app_id,src,parent=-1,parent_src='MSSA',**overrides):
    record=dict(parent_application_rk=parent,parent_src_cd=parent_src,application_rk=rk,src_cd=src,
        parent_application_id=f'P{parent}',parent_application_dt='2025-01-01',parent_approved_dttm=None,
        application_id=app_id,application_dt=None if rk==-1 else '2025-02-01',
        application_type_cd='TEST',deal_issue_date=None,level25_product_bp_nm='TEST',level35_product_bp_nm='TEST',
        parent_open_flg=True,parent_prescoring_flg=True,parent_at_work_flg=True,parent_approved_flg=True,
        create_flg=True,at_work_flg=False,final_approved_flg=False,agr_signed_flg=False,processed_dttm='2025-02-02')
    record.update(overrides)
    db.execute(f"insert into {CDMR}.tech_application_status ({', '.join(record)}) values ({', '.join('?' for _ in record)})",list(record.values()))
