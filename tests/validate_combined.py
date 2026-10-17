"""Offline checks for the single Greenplum script; only synthetic data.

Dependencies: duckdb, pglast. Run: python tests/validate_combined.py
The test engine expands the ETL macros with fixed test values, removes
Greenplum storage/distribution options and implements one-argument btrim
through trim. Expanded production SQL is parsed separately by pglast
before these execution adaptations.
"""

from pathlib import Path
import re

import duckdb
from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'sql/build_questionnaire_application_status.sql'
S = 'sbx_pre_orb_fd'
FINAL = f'{S}.prt_tech_questionnaire_application_status'
TEST_MACROS = {
    'db_sbx': S,
    'p_db_bdm': 'bdm',
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
    db.execute(f'create schema {S}; create schema bdm')
    db.execute('create macro btrim(value) as trim(value)')
    schema_sql = f'''
        create table {S}.tech_questionnaire_status (
            questionnaire_rk bigint, questionnaire_id text, src_cd text,
            questionnaire_dttm timestamp, effective_from_dttm timestamp,
            effective_to_dttm timestamp, product_type_cd text, program_type text,
            level25_product_bp_nm text, status_cd text, status_name text
        );
        create table {S}.man_prt_tqs_questionnaire (
            questionnaire_id text, application_num text, src_cd text
        );
        create table bdm.application (
            application_rk bigint, application_num text, src_cd text,
            effective_to_date date, application_begin_date date
        );
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
    '''
    if integer_flags:
        schema_sql = schema_sql.replace(' boolean', ' integer')
    db.execute(schema_sql)
    return db


def add_q(db, rk, qid, src, product, status='DRAFT', historical=None,
          effective_from='2025-02-01', effective_to='2999-12-31', created='2025-01-01'):
    data = [(rk, qid, src, created, effective_from, effective_to,
             'TEST', 'TEST', product, status, status)]
    if historical:
        data.append((rk, qid, src, created, '2025-01-01', effective_from,
                     'TEST', 'TEST', product, historical, historical))
    db.executemany(f'insert into {S}.tech_questionnaire_status values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', data)


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
    add_q(db, 101, 'Q1', '1376.2.e', 'Потребкредит', historical='CHECK_LIST_ANTIFRAUD_OR_PRODUCT')
    add_q(db, 101, 'Q1', '1376.2.e', 'Потребкредит')  # Duplicate current status.
    add_q(db, 102, 'Q2', '1376.2.n', 'Потребкредит', historical='0')
    add_q(db, 103, 'Q3', '1376.2.n', 'Потребкредит', status='SCORING')
    add_q(db, 104, 'Q4', '1376.2.i', 'Потребкредит', historical='10.0')
    add_q(db, 105, 'Q1', '1376.2.n', 'Потребкредит')  # Same text ID, other source.
    add_q(db, 106, 'BAD_PRODUCT', '1376.2.e', 'Кредитные карты')
    add_q(db, 107, 'CONFLICT_A', '1376.2.e', 'Потребкредит')
    add_q(db, 107, 'CONFLICT_B', '1376.2.e', 'Потребкредит')
    add_q(db, None, 'INVALID_RK_1', '1376.2.e', 'Потребкредит')
    add_q(db, None, 'INVALID_RK_2', '1376.2.e', 'Потребкредит')
    add_q(db, 108, 'BAD_PARENT', '1376.2.e', 'Потребкредит')
    add_q(db, 109, 'Q5', '1376.2.e', 'Потребкредит')
    add_q(db, 301, 'C1', '1383.1.n', 'Кредитные карты', historical='COURIER')
    add_q(db, 302, 'C2', '1383.1.n', 'Кредитные карты', status='DONE')
    add_q(db, 303, 'C3', '1383.1.n', 'Кредитные карты', status='SCORING')
    add_q(db, 304, 'AUTO1', '1383.1.n', 'Кредитные карты')
    add_q(db, 501, 'AUTO1', '1388.1.n', 'Автокредит', historical='PRE_APPROVED')
    add_q(db, 502, 'AUTO_MISSING', '1388.1.n', 'Автокредит')
    add_q(db, 503, None, '1388.1.n', 'Автокредит', status='VERIFICATION')
    add_q(db, 999, 'HISTORICAL', '1376.2.e', 'Потребкредит', status='одобрено',
          effective_from='2024-01-01', effective_to='2024-02-01', created='2024-01-01')
    add_q(db, 1000, 'FUTURE', '1388.1.n', 'Автокредит', status='DEAL_VER', effective_from='2080-01-01')
    add_q(db, 1001, 'OLD_COHORT', '1376.2.e', 'Потребкредит', created='2024-01-01')
    nums = [('Q1', 'N1', '1376.2.e'), ('Q1', 'N1', '1376.2.e'),
            ('Q1', 'NO_MATCH', '1376.2.n'), ('Q2', 'N2', '1376.2.n'),
            ('Q4', 'N2', '1376.2.i'), ('Q4', 'N4', '1376.2.i'),
            ('C1', 'C1', '1383.1.n'), ('C2', 'C2', '1383.1.n'), ('C3', '', '1383.1.n'),
            ('BAD_PRODUCT', 'N1', '1376.2.e'), ('BAD_PARENT', 'BAD', '1376.2.e'),
            ('Q5', 'N5', '1376.2.e'), (None, 'N1', '1376.2.e')]
    db.executemany(f'insert into {S}.man_prt_tqs_questionnaire values (?, ?, ?)', nums)
    bdm = [(201, 'N1', 'MSCL'), (201, 'N1', 'MSCL'), (901, 'N1', 'MSSA'),
           (902, 'N2', 'MSSA'), (903, 'N4', 'MSSA'), (904, 'N5', 'MSSA'),
           (204, 'N4', 'MSCL'), (205, 'N4', 'MSCL'), (401, 'C1', 'CCPP_CRCA'),
           (402, 'C2', 'CCPP_BATR'), (941, 'C1', 'MSSA'), (942, 'C2', 'MSSA'),
           (999, 'N2', 'CCPP_BATR'), (-1, 'BAD', 'MSSA'), (None, 'N1', 'MSSA')]
    db.executemany("insert into bdm.application values (?, ?, ?, '2999-12-31', '2025-01-01')", bdm)
    db.execute("""insert into bdm.application values
        (888, 'NO_MATCH', 'MSCL', '2024-12-31', '2025-01-01'),
        (778, 'N2', 'MSCL', '2999-12-31', '2024-01-01')""")
    add_tas(db, 201, 'T1', 'MSCL', 901)
    add_tas(db, 201, 'T1', 'MSCL', 901)
    add_tas(db, 204, 'T4', 'MSCL', 902)
    add_tas(db, 205, 'T5', 'MSCL', 902)
    add_tas(db, 206, 'T6', 'MSCL', 903)
    add_tas(db, 207, 'UNMATCHED', 'MSCL')
    add_tas(db, 208, 'WRONG_PARENT_SOURCE', 'MSCL', 901, 'OTHER')
    add_tas(db, 350, 'AUTO1', 'MSCL')
    add_tas(db, 209, 'F1', 'MSCL', 906)
    add_tas(db, 209, 'F2', 'MSCL', 906, at_work_flg=True)
    add_tas(db, 401, 'C1', 'CCPP_CRCA', 941)
    add_tas(db, 402, 'C2', 'CCPP_BATR')
    add_tas(db, 404, 'C4', 'CCPP_BATR', 942)
    add_tas(db, 501, 'WRONG_PRODUCT', 'CCPP_CRCA', 901)
    add_tas(db, 201, 'WRONG_SOURCE', 'CCPP_CRCA')
    add_tas(db, -1, None, None, 904)
    add_tas(db, -1, None, None, 905)
    for rk in (901, 902, 903):
        add_tas(db, rk, f'UZ{rk}', 'MSSA')
    add_tas(db, 601, 'AUTO1', 'ALPP')
    add_tas(db, 601, 'AUTO1', 'ALPP')
    add_tas(db, 602, 'AUTO2', 'ALPP')
    add_tas(db, 603, None, 'ALPP')
    add_tas(db, -1, None, 'ALPP')
    add_tas(db, -1, None, 'ALPP')


def rows(db, query):
    return db.execute(query).fetchall()


def assert_fixture(db):
    assert rows(db, f'select check_name, error_count from {S}.prt_qas_checks where error_count <> 0') == []
    assert rows(db, f'select count(*) from {S}.prt_qas_questionnaire') == [(18,)]
    assert rows(db, f'select count(*) from {S}.prt_qas_kn_kk_tas') == [(18,)]
    assert rows(db, f'select count(*) from {S}.prt_qas_auto_tas') == [(5,)]
    assert rows(db, f'''select record_type, count(*) from {FINAL}
                        group by record_type order by record_type''') == [
        ('APPLICATION_ONLY', 11), ('MATCHED', 15), ('QUESTIONNAIRE_ONLY', 11)]
    assert rows(db, f'''select q_total, q_matched, app_total, app_matched,
                               q_coverage_pct, app_coverage_pct, entity_coverage_pct
                        from {S}.prt_qas_coverage where product_branch = 'ALL' ''') == [
        (18, 7, 23, 12, 38.89, 52.17, 46.34)]
    assert rows(db, f'''select link_route, q_matched, pair_count, many_to_many_pairs
                        from {S}.prt_qas_kn_kk_link_quality where product_branch = 'KN'
                        order by link_route''') == [
        ('DIRECT_PRODUCT', 2, 3, 0), ('UZ_ONLY', 1, 1, 0),
        ('UZ_PARENT', 3, 6, 4), ('UZ_SELF', 3, 4, 1)]
    assert rows(db, f'''select link_routes from {FINAL}
                        where q_questionnaire_rk = 101 and tas_application_rk = 201''') == [
        ('DIRECT_PRODUCT,UZ_PARENT',)]
    assert rows(db, f'''select record_type, tas_application_rk, tas_src_cd
                        from {FINAL} where tas_entity_type = 'UZ_ONLY'
                        order by tas_parent_application_rk''') == [
        ('MATCHED', None, None), ('APPLICATION_ONLY', None, None)]
    assert rows(db, f'''select count(*) from {FINAL}
                        where q_questionnaire_rk = 108 and record_type <> 'QUESTIONNAIRE_ONLY' ''') == [(0,)]
    assert rows(db, f'''select count(*) from {FINAL}
                        where record_type = 'MATCHED' and q_questionnaire_id is null''') == [(0,)]
    assert rows(db, f'''select verification_flg, current_row_count
                        from {S}.prt_qas_questionnaire where questionnaire_rk = 101''') == [(True, 2)]
    assert rows(db, f'''select count(*) from {S}.prt_qas_questionnaire
                        where questionnaire_rk is null and verification_flg is null''') == [(2,)]
    assert rows(db, f'''select application_id, at_work_flg, payload_variant_count
                        from {S}.prt_qas_kn_kk_tas where application_rk = 209''') == [(None, None, 2)]
    assert rows(db, f'''select verification_flg from {S}.prt_qas_verification_flags
                        where questionnaire_rk = 999''') == [(True,)]
    assert rows(db, f'''select count(*) from {S}.prt_qas_verification_flags
                        where questionnaire_rk = 1000''') == [(0,)]


def check_fixture():
    db = make_db()
    populate(db)
    before = rows(db, f'select count(*) from {S}.tech_questionnaire_status')
    db.execute(execution_sql())
    assert_fixture(db)
    # Repeating all DROP/CREATE operations must retain all source data/results.
    db.execute(execution_sql())
    assert_fixture(db)
    assert rows(db, f'select count(*) from {S}.tech_questionnaire_status') == before
    print('PASS: full branches; exact coverage; direct/UZ overlap; N:M; source/product isolation.')
    print('PASS: NULL/sentinel keys and UZ without child preserved; no NULL or -1 joins.')
    print('PASS: history flag; conflicting attributes; unique pairs; repeatability; inputs unchanged.')
    # Test the supported route switch without changing source data or common flags.
    db.execute(execution_sql({'p_kn_kk_link_mode': "'DIRECT'"}))
    assert rows(db, f'select sum(error_count) from {S}.prt_qas_checks') == [(0,)]
    assert rows(db, f'select count(*) from {S}.prt_qas_kn_kk_links') == [(5,)]
    print('PASS: switching to DIRECT retains every input entity.')
    db.execute(execution_sql({'p_kn_kk_link_mode': "'UZ'"}))
    assert rows(db, f'select sum(error_count) from {S}.prt_qas_checks') == [(0,)]
    assert rows(db, f'select count(*) from {S}.prt_qas_kn_kk_links') == [(13,)]
    print('PASS: switching to UZ retains every input entity.')


def check_all_marked_statuses():
    # Explicit expected business list, independent from the SQL seed.
    cases = [
        ('1376.1', 'Потребкредит', ['0', '10.0', 'одобрено', 'CHECK_LIST_EMPTY', 'CHECK_LIST_ANTIFRAUD_OR_PRODUCT']),
        ('1383.1', 'Кредитные карты', ['DONE', 'COURIER']),
        ('1388.1', 'Автокредит', ['APPROVE_RKK', 'APPROVED', 'PRE_APPROVED', 'APPROVE_CALL2',
            'APPROVE_CALL3', 'ORDER_CREATED', 'VERIFICATION', 'DRIVER_CARD_ISSUE',
            'DRIVER_CARD_ISSUE_UPLOADED', 'DOSSIER_UPLOADED', 'DEAL_VER', 'CREDIT_ISSUED', 'PRODUCT_BASKET_SIGNED']),
    ]
    db = make_db()
    rk = 3000
    for src, product, statuses in cases:
        for status in statuses:
            add_q(db, rk, f'H{rk}', src, product, historical=status,
                  effective_to='2999-12-31 23:59:59')
            rk += 1
    add_q(db, 4000, 'NEG_AUTO', '1388.1', 'Автокредит', status='APPROVE_CALL0')
    add_q(db, 4001, 'NEG_KN', '1376.1', 'Потребкредит', status='DONE')
    add_q(db, 4002, 'NEG_KK', '1383.1', 'Кредитные карты', status='SCORING')
    db.execute(execution_sql())
    assert rows(db, "select count(*) from information_schema.tables where table_name = 'prt_qas_verification_status'") == [(0,)]
    assert rows(db, f'''select count(*) from {S}.prt_qas_questionnaire
                        where questionnaire_rk between 3000 and 3019 and verification_flg''') == [(20,)]
    assert rows(db, f'''select count(*) from {S}.prt_qas_questionnaire
                        where questionnaire_rk >= 4000 and not verification_flg''') == [(3,)]
    assert rows(db, f'select sum(error_count) from {S}.prt_qas_checks') == [(0,)]
    print('PASS: every one of the 20 green/yellow statuses sets the business flag from history.')


def check_empty():
    db = make_db()
    db.execute(execution_sql())
    assert rows(db, f'select count(*) from {FINAL}') == [(0,)]
    assert rows(db, f'select sum(error_count) from {S}.prt_qas_checks') == [(0,)]
    assert rows(db, f'''select q_total, q_coverage_pct, app_total, app_coverage_pct
                        from {S}.prt_qas_coverage where product_branch = 'ALL' ''') == [(0, None, 0, None)]
    print('PASS: empty inputs and zero-denominator coverage.')


def check_integer_tas_flags():
    # Prototype screenshots compute 0/1, while the target DDL uses boolean.
    # Both supported input representations must yield the same final result.
    db = make_db(integer_flags=True)
    populate(db)
    db.execute(execution_sql())
    assert_fixture(db)
    print('PASS: TAS flags can be boolean or prototype integer 0/1.')


def check_macro_parameters():
    assert 'prt_qas_params' not in SCRIPT.read_text()
    assert 'prt_qas_verification_status' not in SCRIPT.read_text()
    assert set(re.findall(r'&([A-Za-z_][A-Za-z0-9_]*)', SCRIPT.read_text())) == set(TEST_MACROS)
    db = make_db()
    populate(db)
    db.execute(execution_sql({
        'p_report_timestamp': "'2026-10-16 08:30:00'",
        'p_min_coverage_pct': '12.5',
        'p_bdm_limit_by_begin_date': 'false',
    }))
    assert rows(db, f'select sum(error_count) from {S}.prt_qas_checks') == [(0,)]
    assert rows(db, f'select distinct reference_coverage_pct from {S}.prt_qas_coverage') == [(12.5,)]
    assert rows(db, f"select count(distinct report_dttm) from {FINAL}") == [(1,)]
    assert rows(db, f"select count(*) from {FINAL} where report_dttm <> timestamp '2026-10-16 08:30:00'") == [(0,)]
    assert rows(db, f'select count(*) from {S}.prt_qas_kn_kk_bdm_application where application_rk = 778') == [(1,)]
    db.execute(execution_sql({'P_BEGIN_DATE': "'2026-01-01'"}))
    assert rows(db, f'select count(*) from {FINAL}') == [(0,)]
    db.execute(execution_sql({'p_kn_kk_link_mode': 'NULL'}))
    assert rows(db, f"select error_count from {S}.prt_qas_checks where check_name = 'INVALID_LINK_MODE'") == [(1,)]
    print('PASS: macro overrides, one report timestamp, date switch and NULL mode validation.')


def check_product_status_macros():
    db = make_db()
    products = [('1376.1', 'KN_CUSTOM_PRODUCT', 'KN_CUSTOM', 'CHECK_LIST_EMPTY'),
                ('1383.1', 'KK_CUSTOM_PRODUCT', 'KK_CUSTOM', 'DONE'),
                ('1388.1', 'AUTO_CUSTOM_PRODUCT', 'AUTO_CUSTOM', 'VERIFICATION')]
    expected = []
    for index, (src, product, custom_status, old_status) in enumerate(products):
        rk = 5000 + index * 10
        add_q(db, rk, f'CUSTOM{rk}', src, product, historical=custom_status)
        add_q(db, rk + 1, f'OLD{rk}', src, product, status=old_status)
        add_q(db, rk + 2, f'WRONG_LIST{rk}', src, product,
              status=products[(index + 1) % 3][2])
        add_q(db, rk + 3, f'MISSING_STATUS{rk}', src, product, status=None)
        expected.extend([(rk, True, 1), (rk + 1, False, 1),
                         (rk + 2, False, 1), (rk + 3, False, 1)])
    add_q(db, 5100, 'WRONG_PRODUCT', '1376.1', 'Потребкредит', status='KN_CUSTOM')
    expected.append((5100, False, 0))
    db.execute(execution_sql({
        'p_prod_kn_name': "'KN_CUSTOM_PRODUCT'",
        'p_prod_kk_name': "'KK_CUSTOM_PRODUCT'",
        'p_prod_auto_name': "'AUTO_CUSTOM_PRODUCT'",
        'p_kn_verification_status': "'KN_CUSTOM', 'KN_CUSTOM'",
        'p_kk_verification_status': "'KK_CUSTOM', 'KK_OTHER'",
        'p_auto_verification_status': "'AUTO_CUSTOM'",
    }))
    assert rows(db, f'''select questionnaire_rk, verification_flg, product_match_flg
                        from {S}.prt_qas_questionnaire order by questionnaire_rk''') == expected
    assert rows(db, f'select sum(error_count) from {S}.prt_qas_checks') == [(0,)]
    # Duplicate values in an IN list must not multiply historical records.
    assert rows(db, f'''select history_row_count from {S}.prt_qas_verification_flags
                        where questionnaire_rk = 5000''') == [(2,)]
    print('PASS: all product names/lists are configurable; history, product isolation, NULL and duplicate list values.')


if __name__ == '__main__':
    print('PARSED PostgreSQL statements:', len(parse_sql(postgres_sql())))
    check_fixture()
    check_all_marked_statuses()
    check_empty()
    check_integer_tas_flags()
    check_macro_parameters()
    check_product_status_macros()
    print('Local validation only: bank data, ETL completeness and Greenplum plans remain unverified.')
