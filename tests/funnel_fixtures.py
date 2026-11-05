"""Synthetic contracts: ready TQS/TAS and a two-column intention source."""
import duckdb

S = 'sbx_pre_orb_fd'
CDMR = 'dm_pik_fd_cdmr'
RAW = 'rd_raw_orb.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention'
MACROS = {
    'db_sbx': S, 'p_db_bdm': 'bdm', 'p_db_rawd': 'rd_raw_orb', 'p_db_cdmr': CDMR,
    'P_BEGIN_DATE': "'2025-01-01'", 'p_max_date': "'2999-12-31'",
    'p_report_timestamp': "'2026-11-05 00:00:00'",
    'p_quest_25lvl_product_kn_list': "'Потребкредит'",
    'p_quest_25lvl_product_kk_list': "'Кредитные карты'",
    'p_quest_25lvl_product_auto_list': "'Автокредит'",
    'p_kn_verification_status': "'0', '10.0', 'одобрено', 'CHECK_LIST_EMPTY', 'CHECK_LIST_ANTIFRAUD_OR_PRODUCT'",
    'p_kk_verification_status': "'DONE', 'COURIER'",
    'p_auto_verification_status': "'APPROVE_RKK', 'APPROVED', 'PRE_APPROVED', 'APPROVE_CALL2', 'APPROVE_CALL3', 'ORDER_CREATED', 'VERIFICATION', 'DRIVER_CARD_ISSUE', 'DRIVER_CARD_ISSUE_UPLOADED', 'DOSSIER_UPLOADED', 'DEAL_VER', 'CREDIT_ISSUED', 'PRODUCT_BASKET_SIGNED'",
}


def make_db():
    db = duckdb.connect()
    db.execute(f'''create schema {S}; create schema rd_raw_orb;
        create schema bdm; create schema {CDMR};
        create table {RAW} (questionnaire_id text, application_num text);
        create table bdm.application (
            application_rk bigint, application_num text, src_cd text,
            effective_to_date date, application_begin_date date);
        create table {CDMR}.tech_questionnaire_status (
            questionnaire_id text, questionnaire_rk bigint, questionnaire_dttm timestamp,
            status_cd text, level25_product_bp_nm text,
            effective_from_dttm timestamp, effective_to_dttm timestamp);
        create table {CDMR}.tech_application_status (
            parent_application_rk bigint, parent_src_cd text,
            application_rk bigint, src_cd text,
            parent_application_id text, parent_application_dt date, parent_approved_dttm timestamp,
            application_id text, application_dt date, application_type_cd text, deal_issue_date date,
            level25_product_bp_nm text, level35_product_bp_nm text,
            parent_open_flg boolean, parent_prescoring_flg boolean, parent_at_work_flg boolean,
            parent_approved_flg boolean, create_flg boolean, at_work_flg boolean,
            final_approved_flg boolean, agr_signed_flg boolean, processed_dttm timestamp);
    ''')
    return db


def add_tqs(db, qid, rk, status='DRAFT', product='Потребкредит',
            start='2025-01-01', end='2999-12-31', qdate='2025-01-01'):
    db.execute(f'insert into {CDMR}.tech_questionnaire_status values (?,?,?,?,?,?,?)',
               [qid, rk, qdate, status, product, start, end])


def add_intention(db, qid, number):
    db.execute(f'insert into {RAW} values (?,?)', [qid, number])


def add_bdm(db, rk, number, src='MSSA', begin='2025-01-01', end='2999-12-31'):
    db.execute('insert into bdm.application values (?,?,?,?,?)', [rk, number, src, end, begin])


def add_tas(db, rk, app_id, src='MSCL', parent=-1, parent_src='MSSA', **overrides):
    record = dict(
        parent_application_rk=parent, parent_src_cd=parent_src, application_rk=rk, src_cd=src,
        parent_application_id=f'P{parent}', parent_application_dt='2025-01-01', parent_approved_dttm=None,
        application_id=app_id, application_dt=None if rk == -1 else '2025-02-01',
        application_type_cd='TEST', deal_issue_date=None,
        level25_product_bp_nm='Потребкредит', level35_product_bp_nm='SOURCE_LEVEL35',
        parent_open_flg=True, parent_prescoring_flg=True, parent_at_work_flg=True,
        parent_approved_flg=True, create_flg=True, at_work_flg=False,
        final_approved_flg=False, agr_signed_flg=False, processed_dttm='2026-11-05')
    record.update(overrides)
    db.execute(f"insert into {CDMR}.tech_application_status ({', '.join(record)}) "
               f"values ({', '.join('?' for _ in record)})", list(record.values()))
