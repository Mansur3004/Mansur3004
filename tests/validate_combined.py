"""Synthetic tests for RAW cleaning -> product -> verification -> BDM/TAS.

No technical TQS or prebuilt questionnaire table exists in the test database.
Production SQL is parsed after macro expansion. DuckDB execution removes
only Greenplum storage/distribution options and implements btrim via trim.
Run with duckdb and pglast: python tests/validate_combined.py
"""
from pathlib import Path
from datetime import date, datetime
import re
import duckdb
from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'sql/build_questionnaire_application_status.sql'
S = 'sbx_pre_orb_fd'
RAW = 'rd_raw_orb.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention'
DETAIL = f'{S}.prt_qas_funnel_detail'
FINAL = f'{S}.prt_tech_internet_funnel'
TEST_MACROS = {
    'db_sbx': S,
    'p_db_bdm': 'bdm',
    'p_db_rawd': 'rd_raw_orb',
    'p_db_cdmr': 'dm_pik_fd_cdmr',
    'p_quest_src_cd_kn_list': "'1376%'",
    'p_quest_src_cd_kk_list': "'1383%'",
    'p_quest_src_cd_ak_list': "'1388%'",
    'p_rds_report_dt_date': "'2024-10-01'",
    'p_min_dttm': "'1900-01-01 00:00:00'",
    'p_test_first_nm_like_text_list': "'%ТЕСТ%', '%ТКЕСТ%', '%ТКЕКСТ%', '%ТЕМСТ%', '%ЛИПОВЫЙ%', '%ЗАЯВК%', 'ПЕНСИОНН%', 'МУЛЬТИКАРТ%', 'АРХАНГЕЛЬСК%', 'ЗВОНИТЬ%', 'AAA%'",
    'p_test_first_nm_in_text_list': "'ПЕНСЫ', 'ЛИД', 'НОВОКУЗНЕЦК', 'ТЕСТ', 'ЛЕХА', 'ДЯДЯ', 'ПРОЛД', 'АРОПР', 'ООО'",
    'p_test_last_nm_in_text_list': "'ТЕСТ'",
    'p_test_middle_nm_like_text_list': "'ТЕСТОВНА'",
    'p_quest_product_kn_list': "'cm.LiabilityType.Loan', 'RF', 'KN'",
    'p_quest_product_kk_list': "'cm.LiabilityType.CreditCard', 'CreditCard', 'cm.LiabilityType.CreditCard cm.LiabilityType.Loan'",
    'p_quest_product_ak_list': "'AutoCredit', 'AutoCreditR', 'AutoLoan', 'cm.LoanApplicationTy', 'cm.LoanApplicationType.Standar', 'cm.LoanApplicationType.Standard'",
    'p_quest_not_len_id_kk_list': '6',
    'P_BEGIN_DATE': "'2025-01-01'",
    'p_max_date': "'2999-12-31'",
    'p_report_timestamp': "'2026-10-15 12:00:00'",
    'p_min_coverage_pct': '10.0',
    'p_kn_kk_link_mode': "'ALL'",
    'p_bdm_limit_by_begin_date': 'true',
    'p_prod_kn_name': "'Потребкредит'",
    'p_prod_kk_name': "'Кредитные карты'",
    'p_prod_auto_name': "'Автокредит'",
    'p_kn_verification_status': "'0', '10.0', 'одобрено', 'CHECK_LIST_EMPTY', 'CHECK_LIST_ANTIFRAUD_OR_PRODUCT'",
    'p_kk_verification_status': "'DONE', 'COURIER'",
    'p_auto_verification_status': "'APPROVE_RKK', 'APPROVED', 'PRE_APPROVED', 'APPROVE_CALL2', 'APPROVE_CALL3', 'ORDER_CREATED', 'VERIFICATION', 'DRIVER_CARD_ISSUE', 'DRIVER_CARD_ISSUE_UPLOADED', 'DOSSIER_UPLOADED', 'DEAL_VER', 'CREDIT_ISSUED', 'PRODUCT_BASKET_SIGNED'",
}


def expand_macros(source, overrides=None):
    values = TEST_MACROS | (overrides or {})
    return re.sub(r'&([A-Za-z_][A-Za-z0-9_]*)',
                  lambda match: values[match.group(1)], source)


def postgres_sql(overrides=None):
    return re.sub(r'\bdistributed\s+randomly\s*;', ';',
                  expand_macros(SCRIPT.read_text(), overrides), flags=re.I)


def execution_sql(overrides=None):
    sql = re.sub(
        r'with\s*\(appendonly\s*=\s*true,\s*orientation\s*=\s*column,\s*'
        r'compresstype\s*=\s*zstd,\s*compresslevel\s*=\s*5\)',
        '', postgres_sql(overrides), flags=re.I,
    )
    return sql


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


def add_history(db, qid, code, status, app_num=None, **overrides):
    add_raw(db,qid,code,status,app_num,
            createtime_dttm='2025-01-15 10:00:00', business_dt='2025-01-15 10:00:00',
            processed_dttm='2025-01-15 10:00:00', **overrides)


def rows(db, query):
    return db.execute(query).fetchall()


def add_tas(db, rk, app_id, src, parent=-1, parent_src='MSSA', **overrides):
    columns = ['parent_application_rk', 'parent_src_cd', 'application_rk', 'src_cd',
               'parent_application_id', 'parent_application_dt', 'parent_approved_dttm',
               'application_id', 'application_dt', 'application_type_cd', 'deal_issue_date',
               'level25_product_bp_nm', 'level35_product_bp_nm', 'parent_open_flg',
               'parent_prescoring_flg', 'parent_at_work_flg', 'parent_approved_flg',
               'create_flg', 'at_work_flg', 'final_approved_flg', 'agr_signed_flg', 'processed_dttm']
    values = [parent, parent_src, rk, src, f'P{parent}', '2025-01-01', None, app_id,
              None if rk == -1 else '2025-02-01', 'TEST', None, 'TEST', 'TEST',
              True, True, True, True, True, False, False, False, '2025-02-02']
    record = dict(zip(columns, values))
    record.update(overrides)
    db.execute(f"insert into {S}.tech_application_status values ({', '.join('?' for _ in columns)})",
               [record[c] for c in columns])


def populate(db):
    add_history(db, 'Q1', 'KN', 'CHECK_LIST_ANTIFRAUD_OR_PRODUCT', 'N1', src_cd='OLD_SOURCE')
    add_raw(db, 'Q1', app_num='N1')
    add_raw(db, 'Q1', app_num='N1')
    add_raw(db, 'Q1', app_num='N_BAD', createtime_dttm='2025-01-20 10:00:00')
    add_history(db, 'Q2', 'KN', '0', 'N2')
    add_raw(db, 'Q2', app_num='N2')
    add_raw(db, 'Q3', status='SCORING')
    add_history(db, 'Q4', 'KN', '10.0', 'N4')
    add_raw(db, 'Q4', app_num='N2')
    add_raw(db, 'Q_OTHER', app_num='NO_MATCH')
    add_raw(db, 'Q5', app_num='N5')
    add_raw(db, 'BAD_PARENT', app_num='BAD')
    add_raw(db, None)
    add_raw(db, None, utmcn='SECOND_MISSING_ID')
    add_history(db, 'CC1', 'CreditCard', 'COURIER', 'C1')
    add_raw(db, 'CC1', 'CreditCard', app_num='C1')
    add_raw(db, 'CC2', 'CreditCard', 'DONE', 'C2')
    add_raw(db, 'CC3', 'CreditCard', 'SCORING')
    add_raw(db, 'AUTO1', 'CreditCard', 'SCORING')  # Same source and ID, other product.
    add_history(db, 'AUTO1', 'AutoLoan', 'PRE_APPROVED')
    add_raw(db, 'AUTO1', 'AutoLoan')
    add_raw(db, 'AUTO_MISSING', 'AutoLoan')
    add_raw(db, None, 'AutoLoan', 'VERIFICATION')
    add_raw(db, 'FUTURE', 'AutoLoan', 'DEAL_VER', createtime_dttm='2080-01-01 00:00:00')
    add_raw(db, 'UNKNOWN_PRODUCT', 'UNKNOWN')
    add_raw(db, '123456', 'CreditCard', 'DONE')  # Original partner-length exclusion.

    bdm = [(201, 'N1', 'MSCL'), (201, 'N1', 'MSCL'), (901, 'N1', 'MSSA'),
           (902, 'N2', 'MSSA'), (903, 'N4', 'MSSA'), (904, 'N5', 'MSSA'),
           (204, 'N4', 'MSCL'), (205, 'N4', 'MSCL'), (401, 'C1', 'CCPP_CRCA'),
           (402, 'C2', 'CCPP_BATR'), (941, 'C1', 'MSSA'), (942, 'C2', 'MSSA'),
           (999, 'N2', 'CCPP_BATR'), (-1, 'BAD', 'MSSA'), (None, 'N1', 'MSSA')]
    db.executemany("insert into bdm.application values (?, ?, ?, '2999-12-31', '2025-01-01')", bdm)
    db.execute("""insert into bdm.application values
        (888, 'NO_MATCH', 'MSCL', '2024-12-31', '2025-01-01'),
        (778, 'N2', 'MSCL', '2999-12-31', '2024-01-01')""")
    for key, app, src, parent in [(201,'T1','MSCL',901),(201,'T1','MSCL',901),
            (204,'T4','MSCL',902),(205,'T5','MSCL',902),(206,'T6','MSCL',903),
            (207,'UNMATCHED','MSCL',-1),(350,'AUTO1','MSCL',-1),
            (401,'C1','CCPP_CRCA',941),(402,'C2','CCPP_BATR',-1),(404,'C4','CCPP_BATR',942),
            (501,'WRONG_PRODUCT','CCPP_CRCA',901),(201,'WRONG_SOURCE','CCPP_CRCA',-1),
            (-1,None,None,904),(-1,None,None,905),
            (901,'UZ1','MSSA',-1),(902,'UZ2','MSSA',-1),(903,'UZ3','MSSA',-1),
            (601,'AUTO1','ALPP',-1),(601,'AUTO1','ALPP',-1),(602,'AUTO2','ALPP',-1),
            (603,None,'ALPP',-1),(-1,None,'ALPP',-1),(-1,None,'ALPP',-1)]:
        add_tas(db,key,app,src,parent)
    add_tas(db,208,'WRONG_PARENT_SOURCE','MSCL',901,'OTHER')
    add_tas(db,209,'F1','MSCL',906)
    add_tas(db,209,'F2','MSCL',906,at_work_flg=True)


def assert_fixture(db):
    assert rows(db, f'select check_name,error_count from {S}.prt_qas_checks where error_count <> 0') == []
    assert rows(db, f'select count(*) from {S}.prt_qas_questionnaire') == [(16,)]
    assert rows(db, f'select count(*) from {S}.prt_qas_kn_kk_tas') == [(18,)]
    assert rows(db, f'select count(*) from {S}.prt_qas_auto_tas') == [(5,)]
    assert rows(db, f'''select record_type,count(*) from {DETAIL}
                        group by record_type order by record_type''') == [
        ('APPLICATION_ONLY',11),('MATCHED',15),('QUESTIONNAIRE_ONLY',9)]
    assert rows(db, f'''select q_total,q_matched,app_total,app_matched,
                               q_coverage_pct,app_coverage_pct,entity_coverage_pct
                        from {S}.prt_qas_coverage where product_branch='ALL' ''') == [
        (16,7,23,12,43.75,52.17,48.72)]
    assert rows(db, f'''select link_route,q_matched,pair_count,many_to_many_pairs
                        from {S}.prt_qas_kn_kk_link_quality where product_branch='KN'
                        order by link_route''') == [
        ('DIRECT_PRODUCT',2,3,0),('UZ_ONLY',1,1,0),('UZ_PARENT',3,6,4),('UZ_SELF',3,4,1)]
    assert rows(db, f'''select link_routes from {DETAIL}
                        where q_questionnaire_id='Q1' and tas_application_rk=201''') == [('DIRECT_PRODUCT,UZ_PARENT',)]
    assert rows(db, f'''select record_type,tas_application_rk,tas_src_cd from {DETAIL}
                        where tas_entity_type='UZ_ONLY' order by tas_parent_application_rk''') == [
        ('MATCHED',None,None),('APPLICATION_ONLY',None,None)]
    assert rows(db, f'''select count(*) from {DETAIL} where q_questionnaire_id='BAD_PARENT'
                        and record_type<>'QUESTIONNAIRE_ONLY' ''') == [(0,)]
    assert rows(db, f'''select verification_flg,history_row_count from {S}.prt_qas_questionnaire
                        where questionnaire_id='Q1' ''') == [(True,2)]
    assert rows(db, f'''select application_num from {S}.prt_tqs_questionnaire
                        where questionnaire_id='Q1' and status='DRAFT' ''') == [('N1',)]
    assert rows(db, f'''select application_num from {S}.prt_qas_questionnaire
                        where questionnaire_id='Q4' ''') == [('N2',)]
    assert rows(db, f'''select application_rk from {S}.prt_qas_kn_kk_questionnaire_bdm b
                        join {S}.prt_qas_questionnaire q on q.q_entity_id=b.q_entity_id
                        where q.questionnaire_id='Q4' and b.src_cd='MSCL'
                        order by application_rk''') == [(204,),(205,)]
    assert rows(db, f'''select count(*) from {S}.prt_qas_questionnaire
                        where questionnaire_id is null and verification_flg is null''') == [(3,)]
    assert rows(db, f'''select application_id,at_work_flg,payload_variant_count
                        from {S}.prt_qas_kn_kk_tas where application_rk=209''') == [(None,None,2)]
    assert rows(db, f'''select product_branch,verification_flg from {S}.prt_qas_questionnaire
                        where questionnaire_id='AUTO1' order by product_branch''') == [('AUTO',True),('KK',False)]


def check_pipeline():
    db=make_db();populate(db)
    raw_count=rows(db,f'select count(*) from {RAW}')
    for _ in range(2):
        db.execute(execution_sql());assert_fixture(db)
    assert rows(db,f'select count(*) from {RAW}')==raw_count
    for mode,total in [('DIRECT',5),('UZ',13)]:
        db.execute(execution_sql({'p_kn_kk_link_mode':repr(mode)}))
        assert rows(db,f'select sum(error_count) from {S}.prt_qas_checks')==[(0,)]
        assert rows(db,f'select count(*) from {S}.prt_qas_kn_kk_links')==[(total,)]
    print('PASS: RAW-only pipeline, exact coverage, two branches, UZ-only, N:M and all link modes.')
    print('PASS: deduplication, all application numbers retained, NULL IDs, source changes and repeatability.')


def check_all_statuses():
    db=make_db()
    cases=[('KN',['0','10.0','одобрено','CHECK_LIST_EMPTY','CHECK_LIST_ANTIFRAUD_OR_PRODUCT']),
           ('CreditCard',['DONE','COURIER']),
           ('AutoLoan',['APPROVE_RKK','APPROVED','PRE_APPROVED','APPROVE_CALL2','APPROVE_CALL3',
                        'ORDER_CREATED','VERIFICATION','DRIVER_CARD_ISSUE','DRIVER_CARD_ISSUE_UPLOADED',
                        'DOSSIER_UPLOADED','DEAL_VER','CREDIT_ISSUED','PRODUCT_BASKET_SIGNED'])]
    index=0
    for code,statuses in cases:
        for status in statuses:
            qid=f'HIGHLIGHT_{index}'
            add_history(db,qid,code,status,src_cd='OLD_UNRELATED_SOURCE',src_cd_src='SAME_FOR_ALL_PRODUCTS')
            add_raw(db,qid,code,src_cd='NEW_UNRELATED_SOURCE',src_cd_src='SAME_FOR_ALL_PRODUCTS')
            index+=1
    add_raw(db,'NEG_KN','KN','DONE')
    add_raw(db,'NEG_KK_LONG','CreditCard','SCORING')
    add_raw(db,'NEG_AUTO','AutoLoan','APPROVE_CALL0')
    db.execute(execution_sql())
    assert rows(db,f"select count(*) from {S}.prt_qas_questionnaire where questionnaire_id like 'HIGHLIGHT_%' and verification_flg")==[(20,)]
    assert rows(db,f"select count(*) from {S}.prt_qas_questionnaire where questionnaire_id like 'NEG_%' and not verification_flg")==[(3,)]
    print('PASS: every marked status sets verification from history, regardless of source.')


def check_cleaning():
    db=make_db()
    add_raw(db,'BAD_DAY',questionnaire_dt='2025-02-29 00:00:00')
    add_raw(db,'BAD_MONTH',questionnaire_dt='2025-13-01 00:00:00')
    add_raw(db,'YEAR_ZERO',questionnaire_dt='0000-01-01 00:00:00')
    add_raw(db,'MASKED',questionnaire_dt='2025-01-01 00:%0:00')
    add_raw(db,'EMPTY_PRIMARY',questionnaire_dt='')
    add_raw(db,'NULL_PRIMARY',questionnaire_dt=None)
    add_raw(db,'LEAP_VALID',questionnaire_dt='2024-02-29 00:00:00')
    add_raw(db,'BAD_OPTIONAL',processed_dttm='garbage')
    add_raw(db,'ISO_TIME',questionnaire_dt='2025-01-01T00:00:00.123456Z')
    add_raw(db,'TEST_LIKE',first_nm='ФИО_ТЕСТ_ФИО')
    add_raw(db,'TEST_FIRST',first_nm='лид')
    add_raw(db,'TEST_LAST',last_nm='тест')
    add_raw(db,'TEST_MIDDLE',middle_nm='тестовна')
    add_raw(db,'123456','CreditCard','DONE')
    add_raw(db,'1234567','CreditCard','DONE')
    add_raw(db,'UNKNOWN_CODE','UNMAPPED')
    db.execute(execution_sql())
    actual=dict(rows(db,f'select questionnaire_id,source_filter_reason from {S}.prt_tqs_questionnaire_checked'))
    assert actual|{} == {
        'BAD_DAY':'INVALID_PRIMARY_DATE','BAD_MONTH':'INVALID_PRIMARY_DATE','YEAR_ZERO':'INVALID_PRIMARY_DATE',
        'MASKED':'MASKED_PRIMARY_DATE','EMPTY_PRIMARY':'INVALID_PRIMARY_DATE','NULL_PRIMARY':'OK',
        'LEAP_VALID':'BEFORE_RAW_BEGIN_DATE','BAD_OPTIONAL':'OK','ISO_TIME':'OK',
        'TEST_LIKE':'TEST_FIRST_NAME_PATTERN','TEST_FIRST':'TEST_FIRST_NAME',
        'TEST_LAST':'TEST_LAST_NAME','TEST_MIDDLE':'TEST_MIDDLE_NAME',
        '123456':'OK','1234567':'OK','UNKNOWN_CODE':'OK'}
    assert rows(db,f"select invalid_date_field_count from {S}.prt_tqs_questionnaire_checked where questionnaire_id='BAD_OPTIONAL'")==[(1,)]
    assert rows(db,f"select count(*) from {S}.prt_qas_questionnaire where questionnaire_id='123456'")==[(0,)]
    assert rows(db,f"select count(*) from {S}.prt_qas_questionnaire where questionnaire_id='1234567'")==[(1,)]
    assert rows(db,f"select is_kn,is_kk,is_auto from {S}.prt_tqs_questionnaire_routing where questionnaire_id='UNKNOWN_CODE'")==[(0,0,0)]
    print('PASS: test names, malformed dates, leap years, masks, safe optional dates, ISO timestamps and KK IDs.')


def check_original_priorities():
    db=make_db()
    add_raw(db,'PRIORITY_NEW',app_num='OLD',createtime_dttm='2025-01-20 00:00:00')
    add_raw(db,'PRIORITY_NEW',app_num='NEW')
    add_raw(db,'PRIORITY_SESSION',app_num='SESSION_A',sessionintention_id='A')
    add_raw(db,'PRIORITY_SESSION',app_num='SESSION_B',sessionintention_id='B',processed_dttm='2025-03-01 00:00:00')
    add_raw(db,'PRIORITY_PROCESSED',app_num='P5',processed_dttm='2025-02-05 00:00:00')
    add_raw(db,'PRIORITY_PROCESSED',app_num='P6',processed_dttm='2025-02-06 00:00:00')
    add_raw(db,'PRIORITY_UTM',app_num='UTM_A',utmcn='A')
    add_raw(db,'PRIORITY_UTM',app_num='UTM_Z',utmcn='Z')
    add_raw(db,'PRIORITY_SRC',app_num='SAME',src_cd_src='A',utmcsr='A')
    add_raw(db,'PRIORITY_SRC',app_num='SAME',src_cd_src='Z',utmcsr='Z')
    db.execute(execution_sql())
    assert rows(db,f'''select questionnaire_id,application_num from {S}.prt_tqs_questionnaire
                       order by questionnaire_id''')==[
        ('PRIORITY_NEW','NEW'),('PRIORITY_PROCESSED','P6'),('PRIORITY_SESSION','SESSION_A'),
        ('PRIORITY_SRC','SAME'),('PRIORITY_UTM','UTM_Z')]
    assert rows(db,f"select utmcsr from {S}.prt_tqs_questionnaire where questionnaire_id='PRIORITY_SRC'")==[('Z',)]
    print('PASS: source priority order: creation, session ASC, processed time, UTM, final source-code tie-break.')


def check_original_date_chain():
    db=make_db()
    # MIN is computed before the losing duplicate is removed.
    add_raw(db,'DATE_KN',app_num='LOSING_NUM',questionnaire_dt='2025-01-05 00:00:00',
            createtime_dttm='2025-01-15 00:00:00')
    add_raw(db,'DATE_KN',app_num='WINNING_NUM',questionnaire_dt='2025-01-10 00:00:00',
            business_dt='2025-02-03 00:00:00')
    add_history(db,'DATE_KN','KN','0','HISTORY_NUM',questionnaire_dt='2025-01-07 00:00:00')
    add_raw(db,'DATE_KK_LONG','CreditCard',questionnaire_dt='2025-01-10 00:00:00',
            business_dt='2025-02-03 00:00:00')
    add_history(db,'DATE_KK_LONG','CreditCard','COURIER',questionnaire_dt='2025-01-07 00:00:00')
    db.execute(execution_sql())
    assert rows(db,f'''select cast(questionnaire_dttm as text),
                              cast(original_effective_from_dttm_auto_kn as text),
                              cast(original_effective_from_dttm_kk_dk as text)
                       from {S}.prt_tqs_questionnaire
                       where questionnaire_id='DATE_KN' and status='DRAFT' ''')==[
        ('2025-01-05 00:00:00','2025-01-10 00:00:00','2025-02-03 00:00:00')]
    assert rows(db,f'''select questionnaire_id,cast(effective_from_dttm as text),verification_flg
                       from {S}.prt_qas_questionnaire order by questionnaire_id''')==[
        ('DATE_KK_LONG','2025-02-03 00:00:00',True),('DATE_KN','2025-01-10 00:00:00',True)]
    assert set(rows(db,f'''select n.application_num from {S}.prt_qas_questionnaire q,
                          unnest(q.application_nums) n(application_num)
                          where q.questionnaire_id='DATE_KN' '''))=={('HISTORY_NUM',),('WINNING_NUM',)}
    print('PASS: original MIN before deduplication, branch date precedence and numbers from surviving statuses.')


def check_macros_and_empty():
    assert set(re.findall(r'&([A-Za-z_][A-Za-z0-9_]*)',SCRIPT.read_text()))==set(TEST_MACROS)
    assert not re.search(r'select\s+(?:\w+\.)?\*',SCRIPT.read_text(),re.I)
    db=make_db();db.execute(execution_sql())
    assert rows(db,f'select count(*) from {DETAIL}')==[(0,)]
    assert rows(db,f'select sum(error_count) from {S}.prt_qas_checks')==[(0,)]
    db=make_db()
    add_history(db,'CUSTOM_KN','CUSTOM_CODE','PASSED')
    add_raw(db,'CUSTOM_KN','CUSTOM_CODE')
    db.execute(execution_sql({'p_prod_kn_name':"'CUSTOM_PRODUCT'",'p_quest_product_kn_list':"'CUSTOM_CODE'",
                             'p_kn_verification_status':"'PASSED', 'PASSED'",'p_min_coverage_pct':'12.5'}))
    assert rows(db,f'select level25_product_bp_nm,verification_flg,history_row_count from {S}.prt_qas_questionnaire')==[('CUSTOM_PRODUCT',True,2)]
    assert rows(db,f'select distinct reference_coverage_pct from {S}.prt_qas_coverage')==[(12.5,)]
    db=make_db(integer_flags=True);populate(db);db.execute(execution_sql());assert_fixture(db)
    print('PASS: macro names/codes/lists, no lookup tables or SELECT *, empty inputs and 0/1 TAS flags.')


def check_rk_and_target_contract():
    db=make_db();populate(db)
    db.execute('''insert into dm_pik_fd_cdmr.tech_questionnaire_x_customer values
        ('Q1',1001,'2999-12-31'),('Q1',1001,'2999-12-31'),('Q1',9001,'2025-01-16'),
        ('Q4',1004,'2999-12-31'),('Q4',1005,'2999-12-31'),('Q4',1004,'2999-12-31'),
        ('AUTO_MISSING',1602,'2999-12-31'),('AUTO1',1601,'2999-12-31'),
        ('BAD_PARENT',-1,'2999-12-31'),('CC1',NULL,'2999-12-31'),
        ('SHARED_RK_OLD',1700,'2999-12-31'),('SHARED_RK_NEW',1700,'2999-12-31')''')
    add_raw(db,'AUTO_RK_LINKED','AutoLoan','VERIFICATION')
    add_tas(db,661,'AUTO_RK_LINKED','ALPP')
    db.execute("insert into dm_pik_fd_cdmr.tech_questionnaire_x_customer values ('AUTO_RK_LINKED',1661,'2999-12-31')")
    add_raw(db,'SHARED_RK_OLD','KN','0','OLD_RK_NUMBER')
    add_raw(db,'SHARED_RK_NEW','KN','SCORING','NEW_RK_NUMBER',questionnaire_dt='2025-01-02 00:00:00')
    db.execute(execution_sql())
    assert rows(db,f'select check_name from {S}.prt_qas_checks where error_count<>0')==[]
    assert rows(db,f"select questionnaire_rk,rk_mapping_count,history_row_count from {S}.prt_qas_questionnaire where questionnaire_id='Q1'")==[(1001,1,2)]
    assert rows(db,f"select questionnaire_rk,rk_mapping_count from {S}.prt_qas_questionnaire where questionnaire_id='Q4' order by questionnaire_rk")==[(1004,2),(1005,2)]
    assert rows(db,f"select count(*) from {S}.prt_tqs_questionnaire_rk where questionnaire_rk in (-1,9001)")==[(0,)]
    assert rows(db,f'''select questionnaire_id,questionnaire_rk,verification_flg,history_row_count
                       from {S}.prt_qas_questionnaire where questionnaire_rk=1700''')==[('SHARED_RK_NEW',1700,True,2)]
    assert set(rows(db,f'''select n.application_num from {S}.prt_qas_questionnaire q,
                           unnest(q.application_nums) n(application_num) where q.questionnaire_rk=1700'''))=={
        ('OLD_RK_NUMBER',),('NEW_RK_NUMBER',)}
    expected_names=['questionnaire_rk','questionnaire_dttm','quest_verification_flg',
        'parent_application_rk','parent_application_dt','parent_open_flg','parent_prescoring_flg',
        'parent_at_work_flg','parent_approved_flg','application_rk','application_dt','deal_issue_date',
        'create_flg','at_work_flg','final_approved_flg','agr_signed_flg',
        'level25_product_bp_nm','level35_product_bp_nm','processed_dttm']
    target_schema=rows(db,f'describe {FINAL}')
    assert [r[0] for r in target_schema]==expected_names
    assert [r[1] for r in target_schema]==['BIGINT','TIMESTAMP','BOOLEAN','BIGINT','DATE',
        'BOOLEAN','BOOLEAN','BOOLEAN','BOOLEAN','BIGINT','DATE','DATE','BOOLEAN','BOOLEAN',
        'BOOLEAN','BOOLEAN','VARCHAR','VARCHAR','TIMESTAMP_S']
    assert rows(db,f'select {", ".join(expected_names)} from {FINAL} where questionnaire_rk=1001 and application_rk=201')==[
        (1001,datetime(2025,1,1),True,901,date(2025,1,1),True,True,True,True,
         201,date(2025,2,1),None,True,False,False,False,'TEST','TEST',datetime(2026,10,15,12))]
    assert rows(db,f'''select level25_product_bp_nm,level35_product_bp_nm,quest_verification_flg
                       from {FINAL} where questionnaire_rk=1602''')==[('Автокредит',None,False)]
    assert rows(db,f'''select questionnaire_rk,application_rk,quest_verification_flg
                       from {FINAL} where questionnaire_rk=1661''')==[(1661,661,True)]
    assert rows(db,f'select count(*) from {FINAL}')==rows(db,f'select count(*) from {DETAIL}')
    assert rows(db,f'''select count(*) from {DETAIL} where record_type='QUESTIONNAIRE_ONLY'
                       and q_questionnaire_id='Q3' and q_questionnaire_rk is null''')==[(1,)]
    # The reconstructed history includes every original technical TQS attribute.
    tqs_fields={'questionnaire_id','questionnaire_rk','questionnaire_dttm','utmcn_info',
        'utmcmd_info','utmcsr_info','utmctr_info','utmcct_info','status_cd','scoring_status_nm',
        'prescoring_status_nm','product_type_cd','status_name','program_type','src_cd',
        'level25_product_bp_nm','effective_from_dttm','effective_to_dttm','processed_dttm'}
    assert tqs_fields|{'application_num'} <= {r[0] for r in rows(db,f'describe {S}.prt_qas_tech_questionnaire_status')}
    print('PASS: real RK mapping, duplicate customer pairs, multiple RK, unmapped preservation and shared-RK history.')
    print('PASS: all 19 target fields, exact types/values, all original TQS attributes and projection row preservation.')


def check_original_branch_routing():
    db=make_db()
    add_raw(db,'PREFIX_KN','UNLISTED',src_cd_src='1376_TEST')
    add_raw(db,'PREFIX_KK_LONG','UNLISTED',src_cd_src='1383_TEST')
    add_raw(db,'PREFIX_AUTO','UNLISTED',src_cd_src='1388_TEST')
    add_raw(db,'CODE_ONLY','KN',src_cd_src='UNRELATED')
    add_raw(db,'KN_EXCLUDED','KN',src_cd_src='1383_TEST')
    add_raw(db,'KN_NULL_SOURCE','KN',src_cd_src=None)
    add_raw(db,'RAW_SOURCE_IGNORED','UNLISTED',src_cd='1388_TEST',src_cd_src='UNRELATED')
    db.execute(execution_sql())
    assert rows(db,f'''select questionnaire_id,level25_product_bp_nm from {S}.prt_qas_questionnaire
                       order by questionnaire_id''')==[
        ('CODE_ONLY','Потребкредит'),('KN_EXCLUDED','Кредитные карты'),('PREFIX_AUTO','Автокредит'),
        ('PREFIX_KK_LONG','Кредитные карты'),('PREFIX_KN','Потребкредит')]
    assert rows(db,f'''select raw_src_cd,src_cd from {S}.prt_qas_tech_questionnaire_status
                       where questionnaire_id='PREFIX_AUTO' ''')==[('SHARED_SOURCE','1388_TEST')]
    print('PASS: original source-or-code branch routing, KN exclusion, NULL semantics and canonical src_cd.')


def check_original_status_timeline():
    db=make_db()
    # Source observation order is deliberately different from business status priority.
    for status in ['APPROVED','DRAFT','DEAL_VER','APPROVE_RKK']:
        add_raw(db,'TIMELINE_AUTO','AutoLoan',status,app_num='NUM_'+status,
                createtime_dttm='2025-01-01 00:00:00',processed_dttm='2025-01-01 00:00:00')
    db.execute("insert into dm_pik_fd_cdmr.tech_questionnaire_x_customer values ('TIMELINE_AUTO',2001,'2999-12-31')")
    for status in ['SCORING','0','10.0','одобрено','CLIENT_DECLINE']:
        add_raw(db,'TIMELINE_KN','KN',status,app_num='NUM_'+status)
    db.execute(execution_sql())
    assert rows(db,f'''select status_cd,status_priority,cast(effective_from_dttm as text),
                              cast(effective_to_dttm as text)
                       from {S}.prt_qas_tech_questionnaire_status where questionnaire_rk=2001
                       order by effective_from_dttm''')==[
        ('DEAL_VER',5,'2025-01-01 00:00:00','2025-01-01 00:00:01'),
        ('APPROVE_RKK',10,'2025-01-01 00:00:01','2025-01-01 00:00:02'),
        ('DRAFT',47,'2025-01-01 00:00:02','2025-01-01 00:00:03'),
        ('APPROVED',147,'2025-01-01 00:00:03','2999-12-31 00:00:00')]
    assert rows(db,f'''select status_cd,status_priority from {S}.prt_tqs_kn_questionnaire
                       where questionnaire_id='TIMELINE_KN' order by status_priority''')==[
        ('одобрено',15),('10.0',18),('0',23),('SCORING',30),('CLIENT_DECLINE',47)]
    assert rows(db,f'''select status_cd,verification_flg,history_row_count from {S}.prt_qas_questionnaire
                       where questionnaire_rk=2001''')==[('APPROVED',True,4)]
    db.execute(execution_sql({'p_report_timestamp':"'2025-01-01 00:00:01'"}))
    assert rows(db,f'''select status_cd,verification_flg from {S}.prt_qas_questionnaire
                       where questionnaire_rk=2001''')==[('APPROVE_RKK',True)]
    print('PASS: original KN/auto priorities, second offsets, LEAD end dates and current version selection.')


def check_attribute_catalog():
    catalog=(ROOT/'docs/attributes_catalog.txt').read_text()
    db=make_db();db.execute(execution_sql())
    tables=re.findall(r'^create table &db_sbx\.(\w+)$',SCRIPT.read_text(),re.M)
    documented={}
    for name,body in re.findall(r'^TABLE &db_sbx\.(\w+)\n(.*?)(?=^TABLE |\Z)',catalog,re.M|re.S):
        documented[name]=re.findall(r'^  \d+\. (\w+) \|',body,re.M)
    assert set(documented)==set(tables)
    for name in tables:
        assert documented[name]==[c[0] for c in rows(db,f'describe {S}.{name}')],name
    print(f'PASS: TXT catalog lists every output attribute, in order, for all {len(tables)} created tables.')


if __name__=='__main__':
    print('PARSED PostgreSQL statements:',len(parse_sql(postgres_sql())))
    check_pipeline()
    check_all_statuses()
    check_cleaning()
    check_original_priorities()
    check_original_date_chain()
    check_macros_and_empty()
    check_rk_and_target_contract()
    check_original_branch_routing()
    check_original_status_timeline()
    check_attribute_catalog()
    print('Offline synthetic tests only; bank data and Greenplum execution remain unverified.')
