"""Final FT changes: TQS mapping, real-key presence and verification after joining.

Run with the same DuckDB/PostgreSQL syntax adapters as the preserved V2 tests.
All records are synthetic. No bank connection or Greenplum execution occurs.
"""
from pathlib import Path
from datetime import datetime
import re
from pglast import parse_sql
from pglast.stream import RawStream
import validate_prototype_v2 as previous

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'sql/build_internet_funnel_v3.sql'
CHECKS = ROOT / 'sql/check_internet_funnel_coverage_v3.sql'
S = previous.S
CDMR = previous.CDMR
FINAL = f'{S}.man_prt_tif_tech_internet_funnel'
MACROS = {'p_rds_report_dt_date': "'2025-01-01'"}


def execute(db):
    db.execute(previous.execution_sql(MACROS, source=SCRIPT.read_text()))


def new_db():
    db = previous.db_new()
    # A reference to the old mapping source must cause a binder failure.
    db.execute(f'drop table {CDMR}.tech_questionnaire_x_customer')
    return db


def raw_questionnaire(db, qid, rk, code='KN', status='DRAFT', num=None, **overrides):
    previous.old.add_raw(db, qid, code, status, num, **overrides)
    product = 'Кредитные карты' if code == 'CreditCard' else 'Потребкредит'
    previous.auto_status(db, qid, rk, 'UNRELATED_TQS_STATUS', product=product)


def add_bdm(db, rk, number, src):
    db.execute("insert into bdm.application values (?, ?, ?, '2999-12-31', '2025-01-01')",
               [rk, number, src])


def query(db, sql):
    return db.execute(sql).fetchall()


def test_links_flags_and_keys():
    db = new_db()
    # Every linked questionnaire starts with a status-based false flag.
    raw_questionnaire(db, 'KN_DIRECT', 101, num='DIRECT')
    previous.auto_status(db, 'KN_DIRECT', 101, 'DUPLICATE_CURRENT', product='Потребкредит')
    previous.auto_status(db, 'KN_DIRECT', 999, 'CLOSED_OTHER_RK', product='Потребкредит', end='2025-02-01')
    raw_questionnaire(db, 'KK_PARENT', 102, 'CreditCard', num='PARENT')
    raw_questionnaire(db, 'KN_PARENT_ONLY', 103, num='PARENT_ONLY')
    raw_questionnaire(db, 'KN_UZ_OWN_ROW', 104, num='UZ_OWN')
    raw_questionnaire(db, 'KN_BDM_ONLY', 105, num='BDM_ONLY')
    raw_questionnaire(db, 'KN_Q_TRUE', 106, status='0')
    raw_questionnaire(db, 'KK_Q_FALSE', 107, 'CreditCard')
    raw_questionnaire(db, 'NO_TQS_MAPPING', 108)
    db.execute(f"delete from {CDMR}.tech_questionnaire_status where questionnaire_id='NO_TQS_MAPPING'")
    raw_questionnaire(db, 'BAD_TQS_MAPPING', -1)
    raw_questionnaire(db, 'KN_BAD_BDM', 109, num='BAD_BDM')
    for rk, number, src in [(301, 'DIRECT', 'MSCL'), (402, 'PARENT', 'MSSA'),
                            (403, 'PARENT_ONLY', 'MSSA'), (404, 'UZ_OWN', 'MSSA'),
                            (399, 'BDM_ONLY', 'MSCL'), (-1, 'BAD_BDM', 'MSCL')]:
        add_bdm(db, rk, number, src)
    previous.add_tas(db, 301, 'KN_APP', 'MSCL', parent=None,
                     level25_product_bp_nm='Потребкредит', level35_product_bp_nm='OTHER')
    previous.add_tas(db, 302, 'KK_APP', 'CCPP_BATR', 402, level25_product_bp_nm='Кредитные карты')
    # Multiple numbers/routes leading to the exact same pair must not duplicate it.
    add_bdm(db, 302, 'PARENT', 'CCPP_BATR')
    previous.add_tas(db, -1, None, None, 403, level25_product_bp_nm='Потребкредит')
    previous.add_tas(db, 404, 'UZ_OWN_ID', 'MSSA', level25_product_bp_nm='Потребкредит')
    previous.add_tas(db, 305, 'KN_APP_ONLY', 'MSCL', level25_product_bp_nm='Потребкредит')
    previous.add_tas(db, -1, 'INVALID_KN', 'MSCL', level25_product_bp_nm='Потребкредит')

    previous.auto_status(db, 'AUTO_LINKED', 201, 'DRAFT')
    previous.auto_status(db, 'AUTO_Q_TRUE', 202, 'APPROVED', end='2025-02-01')
    previous.auto_status(db, 'AUTO_Q_TRUE', 202, 'DRAFT', effective_from_dttm='2025-02-01')
    previous.auto_status(db, 'AUTO_Q_FALSE', 203, 'DRAFT')
    previous.auto_status(db, 'AUTO_BAD_TAS', 204, 'DRAFT')
    previous.auto_status(db, 'AUTO_BAD_Q_RK', -1, 'APPROVED')
    previous.add_tas(db, 501, 'AUTO_LINKED', 'ALPP', level25_product_bp_nm=None)
    previous.add_tas(db, 502, 'AUTO_APP_ONLY', 'ALPP', parent=None,
                     level25_product_bp_nm='Автокредит')
    previous.add_tas(db, None, 'AUTO_BAD_TAS', 'ALPP', parent=None,
                     level25_product_bp_nm='Автокредит')
    previous.old.add_raw(db, 'AUTO_RAW_ONLY', 'AutoLoan', 'APPROVED')
    # Protect the previous prototype's output through both executions.
    db.execute(f'create table {S}.prt_if2_tech_internet_funnel (sentinel integer)')
    db.execute(f'insert into {S}.prt_if2_tech_internet_funnel values (777)')

    expected = [(-1, -1, 305, None), (-1, -1, 502, None),
                (101, -1, 301, True), (102, 402, 302, True),
                (103, 403, -1, True), (104, -1, 404, True),
                (105, -1, -1, False), (106, -1, -1, True),
                (107, -1, -1, False), (109, -1, -1, False),
                (201, -1, 501, True), (202, -1, -1, True),
                (203, -1, -1, False), (204, -1, -1, False)]
    for _ in range(2):
        execute(db)
        assert query(db, f'''select questionnaire_rk,parent_application_rk,application_rk,quest_verification_flg
                            from {FINAL} order by 1,2,3''') == expected
        assert query(db, f'''select quest_verification_flg from {S}.man_prt_tif_kn_kk_verification
                            where questionnaire_rk=101''') == [(False,)]
        assert query(db, f'''select quest_verification_flg from {S}.man_prt_tif_auto_verification
                            where questionnaire_rk=201''') == [(False,)]
        assert query(db, f'''select count(*) from {S}.man_prt_tif_kn_kk_matches
                            where q_questionnaire_rk=102''') == [(1,)]
        assert query(db, f'''select count(*) from {FINAL}
                            where level25_product_bp_nm is distinct from level35_product_bp_nm''') == [(0,)]
        assert query(db, f'''select level25_product_bp_nm from {FINAL}
                            where questionnaire_rk=201''') == [('Автокредит',)]
        assert query(db, f'''select questionnaire_dttm,quest_verification_flg from {FINAL}
                            where questionnaire_rk=-1''') == [(None, None), (None, None)]
        assert query(db, f'''select application_dt,parent_application_dt,create_flg from {FINAL}
                            where questionnaire_rk=107''') == [(None, None, None)]
        assert query(db, f'select sentinel from {S}.prt_if2_tech_internet_funnel') == [(777,)]
        for index, statement in enumerate(parse_sql(CHECKS.read_text())):
            result = db.execute(RawStream()(statement.stmt)).fetchone()[0]
            assert result == [12, 5, 7, 5, 0, 0, 0][index], (index, result)
    description = query(db, f'describe {FINAL}')
    assert [r[0] for r in description] == previous.FINAL_FIELDS
    assert [r[1] for r in description] == ['BIGINT','TIMESTAMP','BOOLEAN','BIGINT','DATE',
        'BOOLEAN','BOOLEAN','BOOLEAN','BOOLEAN','BIGINT','DATE','DATE','BOOLEAN','BOOLEAN',
        'BOOLEAN','BOOLEAN','VARCHAR','VARCHAR','TIMESTAMP_S']
    print('PASS: TQS mapping without TQXC, current-pair deduplication, direct/UZ/parent-only links, '
          'linked-status override, unmatched flags, -1/NULL handling, 19 fields, coverage and rerun isolation.')


def test_history_and_original_preparation():
    db = new_db()
    for i, (code, product, statuses) in enumerate([
        ('KN', 'Потребкредит', ['0', '10.0', 'одобрено', 'CHECK_LIST_EMPTY', 'CHECK_LIST_ANTIFRAUD_OR_PRODUCT']),
        ('CreditCard', 'Кредитные карты', ['DONE', 'COURIER']),
        ('AutoLoan', 'Автокредит', ['APPROVE_RKK','APPROVED','PRE_APPROVED','APPROVE_CALL2',
            'APPROVE_CALL3','ORDER_CREATED','VERIFICATION','DRIVER_CARD_ISSUE',
            'DRIVER_CARD_ISSUE_UPLOADED','DOSSIER_UPLOADED','DEAL_VER','CREDIT_ISSUED','PRODUCT_BASKET_SIGNED'])]):
        for n, status in enumerate(statuses):
            qid = f'PRODUCT_{i}_STATUS_{n}'
            rk = 1000 + 100*i + n
            if code == 'AutoLoan':
                previous.auto_status(db, qid, rk, status, end='2025-02-01')
                previous.auto_status(db, qid, rk, 'DRAFT', effective_from_dttm='2025-02-01')
            else:
                raw_questionnaire(db, qid, rk, code, status)
                previous.old.add_raw(db, qid, code, 'DRAFT')
    # MIN must see the source records before product branching, as on the screenshots.
    raw_questionnaire(db, 'ORIGINAL_MIN', 2001, questionnaire_dt='2025-01-10 00:00:00')
    previous.old.add_raw(db, 'ORIGINAL_MIN', 'UNKNOWN', 'DRAFT',
        questionnaire_dt='2025-01-01 00:00:00', createtime_dttm='2025-01-01 00:00:00')
    raw_questionnaire(db, 'HISTORICAL_NUMBER', 2002, num='NEW_NUMBER')
    previous.old.add_raw(db, 'HISTORICAL_NUMBER', 'KN', '0', 'OLD_NUMBER',
                         createtime_dttm='2025-01-05 00:00:00')
    add_bdm(db, 3001, 'OLD_NUMBER', 'MSCL')
    previous.add_tas(db, 3001, 'OLD_NUM_APP', 'MSCL', level25_product_bp_nm='Потребкредит')
    raw_questionnaire(db, 'PARTNER_ID_TOO_SHORT', 2003, 'CreditCard')
    db.execute(f"update {previous.old.RAW} set questionnaire_id='123456' where questionnaire_id='PARTNER_ID_TOO_SHORT'")
    raw_questionnaire(db, 'OLD_COHORT', 2004, questionnaire_dt='2024-12-31 00:00:00')
    raw_questionnaire(db, 'TEST_CLIENT', 2005, first_nm='ЛИД')
    execute(db)
    assert query(db, f'select count(*) from {FINAL} where quest_verification_flg') == [(21,)]
    assert query(db, f'select questionnaire_dttm from {FINAL} where questionnaire_rk=2001') == [(datetime(2025,1,1),)]
    assert query(db, f'select application_rk from {FINAL} where questionnaire_rk=2002') == [(3001,)]
    assert query(db, f'select count(*) from {FINAL} where questionnaire_rk in (2003,2004,2005)') == [(0,)]
    print('PASS: all 20 historical product statuses, original MIN/dedup order, historical application_num, '
          'date cohort, partner IDs and test-client exclusions.')


def test_structure_and_empty_input():
    source = SCRIPT.read_text()
    statements = parse_sql(previous.pg_sql(MACROS, source=source))
    assert len(statements) == 30
    assert 'tech_questionnaire_x_customer' not in source
    assert '&p_kn_kk_link_mode' not in source
    assert 'cast(null as bigint)' not in source
    assert not re.search(r'select\s+(?:\w+\.)?\*', source, re.I)
    targets = re.findall(r'^create table &db_sbx\.(\w+)$', source, re.M)
    assert len(targets) == 15 and len(set(targets)) == 15
    assert all(t.startswith('man_prt_tif_') for t in targets)
    assert not re.search(r'\bq\.level35_product_bp_nm\b', source)
    checks = CHECKS.read_text()
    assert len(parse_sql(checks)) == 7 and '&' not in checks
    assert not re.search(r'\b(?:create|drop)\s+table\b', checks, re.I)
    for statement in parse_sql(checks):
        assert len(re.findall(r'count\s*\(\s*distinct', RawStream()(statement.stmt), re.I)) <= 1
    db = new_db()
    execute(db)
    assert query(db, f'select count(*) from {FINAL}') == [(0,)]
    for statement in parse_sql(checks):
        assert db.execute(RawStream()(statement.stmt)).fetchall() == [(0,)]
    print('PASS: PostgreSQL parsing, full-chain binding, explicit attributes, coherent table names and empty input.')


if __name__ == '__main__':
    test_links_flags_and_keys()
    test_history_and_original_preparation()
    test_structure_and_empty_input()
    print('Offline synthetic tests only; Greenplum and bank data remain unverified.')
