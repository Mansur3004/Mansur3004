"""Ready-TQS funnel tests; no bank connection or reconstruction of the TQS ETL."""
from datetime import datetime
from pathlib import Path
import re
from pglast import parse_sql
from pglast.stream import RawStream
from funnel_fixtures import S, CDMR, RAW, MACROS, make_db, add_tqs, add_intention, add_bdm, add_tas

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'sql/build_internet_funnel_v4.sql'
CHECKS = ROOT / 'sql/check_internet_funnel.sql'
FINAL = f'{S}.man_prt_tif_tech_internet_funnel'
FIRST = f'{S}.man_prt_tif_questionnaire_funnel'
REMAINING = f'{S}.man_prt_tif_remaining_tas'
FINAL_FIELDS = ('questionnaire_rk questionnaire_dttm quest_verification_flg '
    'parent_application_rk parent_application_dt parent_open_flg parent_prescoring_flg '
    'parent_at_work_flg parent_approved_flg application_rk application_dt deal_issue_date '
    'create_flg at_work_flg final_approved_flg agr_signed_flg level25_product_bp_nm '
    'level35_product_bp_nm processed_dttm').split()


def pg_sql(source=None, overrides=None):
    values = MACROS | (overrides or {})
    sql = re.sub(r'&([A-Za-z_][A-Za-z0-9_]*)', lambda m: values[m[1]],
                 SCRIPT.read_text() if source is None else source)
    return re.sub(r'\bdistributed\s+(?:randomly|by\s*\([^)]+\))\s*;', ';', sql, flags=re.I)


def execution_sql(source=None, overrides=None):
    return re.sub(r'with\s*\(APPENDONLY\s*=\s*true,\s*ORIENTATION\s*=\s*column,\s*'
                  r'COMPRESSTYPE\s*=\s*zstd,\s*COMPRESSLEVEL\s*=\s*5\)', '',
                  pg_sql(source, overrides), flags=re.I)


def rows(db, sql):
    return db.execute(sql).fetchall()


def build(db, overrides=None):
    db.execute(execution_sql(overrides=overrides))


def reports(db):
    return [db.execute(RawStream()(stmt.stmt)).fetchall() for stmt in parse_sql(CHECKS.read_text())]


def test_ready_tqs_and_number_bridge():
    db = make_db()
    add_tqs(db, 'OLD_DIRECT_PATH', 101)
    add_intention(db, 'OLD_DIRECT_PATH', 'DIRECT')
    add_bdm(db, 301, 'DIRECT', 'MSCL')
    add_tas(db, 301, 'DIRECT_ID', parent=401)
    add_tqs(db, 'PARENT_KK', 102, product='Кредитные карты')
    for number in ['ROOT', 'ROOT', 'ROOT_OLD']:
        add_intention(db, 'PARENT_KK', number)
    add_bdm(db, 402, 'ROOT')
    add_bdm(db, 402, 'ROOT_OLD')
    add_tas(db, 302, 'KK_CHILD', 'CCPP_BATR', 402, level25_product_bp_nm='Кредитные карты')
    add_tas(db, 303, 'KN_CHILD', parent=402)
    add_tas(db, 304, 'WRONG_PARENT_SOURCE', parent=402, parent_src='OTHER')
    add_tqs(db, 'PARENT_ONLY', 103)
    add_intention(db, 'PARENT_ONLY', 'ONLY')
    add_bdm(db, 403, 'ONLY')
    add_tas(db, -1, None, None, 403)
    add_tqs(db, 'OLD_SELF_PATH', 104)
    add_intention(db, 'OLD_SELF_PATH', 'SELF')
    add_bdm(db, 405, 'SELF')
    add_tas(db, 405, 'SELF_ID', 'MSSA')
    add_tqs(db, 'Q_TRUE', 105, '0')
    add_tqs(db, 'Q_FALSE', 106, product='Кредитные карты')
    add_intention(db, 'Q_FALSE', None)
    add_tqs(db, 'OLD_PARENT', 107)
    add_intention(db, 'OLD_PARENT', 'OLD_PARENT_NUM')
    add_bdm(db, 406, 'OLD_PARENT_NUM', begin='2024-01-01')
    add_tas(db, 307, 'NEW_CHILD', parent=406)
    # Ready TQS is authoritative even when there is no row at all in intention.
    add_tqs(db, 'TQS_ONLY', 108, '0', end='2025-02-01')
    add_tqs(db, 'TQS_ONLY', 108, start='2025-02-01', qdate='2025-04-10')
    add_intention(db, 'NO_TQS', 'ROOT')
    add_tqs(db, 'INVALID_RK', -1)
    add_tqs(db, 'AUTO_LINKED', 201, product='Автокредит')
    add_tqs(db, 'AUTO_TRUE', 202, 'APPROVED', product='Автокредит', end='2025-02-01')
    add_tqs(db, 'AUTO_TRUE', 202, product='Автокредит', start='2025-02-01')
    add_tqs(db, 'AUTO_FALSE', 203, product='Автокредит')
    add_tqs(db, 'OLD_AUTO_ID', 204, 'APPROVED', product='Автокредит', end='2025-02-01')
    add_tqs(db, 'CURRENT_AUTO_ID', 204, product='Автокредит', start='2025-02-01')
    add_tas(db, 501, 'AUTO_LINKED', 'ALPP', level25_product_bp_nm='Автокредит')
    add_tas(db, 502, 'AUTO_ONLY', 'ALPP', level25_product_bp_nm='Автокредит')
    add_tas(db, 504, 'CURRENT_AUTO_ID', 'ALPP', level25_product_bp_nm='Автокредит')
    add_tas(db, 505, 'OLD_AUTO_ID', 'ALPP', level25_product_bp_nm='Автокредит')
    add_tas(db, -1, 'INVALID_TAS', 'ALPP', level25_product_bp_nm='Автокредит')
    add_tas(db, 503, 'NOT_A_CREDIT', level25_product_bp_nm='Депозиты')
    expected = {
        (-1,401,301,None), (-1,402,304,None), (-1,-1,405,None),
        (-1,-1,502,None), (-1,-1,505,None),
        (101,-1,-1,False), (102,402,302,True), (102,402,303,True),
        (103,403,-1,True), (104,-1,-1,False), (105,-1,-1,True),
        (106,-1,-1,False), (107,406,307,True), (108,-1,-1,True),
        (201,-1,501,True), (202,-1,-1,True), (203,-1,-1,False), (204,-1,504,True)}
    source_counts = rows(db, f'select count(*) from {RAW}')
    for _ in range(2):
        build(db)
        actual = rows(db, f'select questionnaire_rk,parent_application_rk,application_rk,quest_verification_flg from {FINAL}')
        assert set(actual) == expected and len(actual) == len(expected), actual
        assert rows(db, f'select questionnaire_dttm from {FINAL} where questionnaire_rk=108') == [(datetime(2025,4,10),)]
        assert rows(db, f'select count(*) from {S}.man_prt_tif_questionnaire_numbers') == [(6,)]
        assert rows(db, f'select count(*) from {S}.man_prt_tif_kn_kk_bdm where questionnaire_rk=102') == [(1,)]
        assert rows(db, f'select count(*) from {RAW}') == source_counts
        result = reports(db)
        assert result[0] == [] and result[1] == [] and result[2] == []
        assert all(report == [(0,)] for report in result[3:7])
        assert dict(result[7]) == {'Потребкредит':6,'Кредитные карты':2,'Автокредит':4}
        assert dict(result[8]) == {'Потребкредит':2,'Кредитные карты':1,'Автокредит':2}
        assert dict(result[9]) == {'Потребкредит':6,'Кредитные карты':1,'Автокредит':4}
        assert dict(result[10]) == {'Потребкредит':3,'Кредитные карты':1,'Автокредит':2}
        assert result[11] == []
    description = rows(db, f'describe {FINAL}')
    assert [r[0] for r in description] == FINAL_FIELDS
    assert [r[1] for r in description] == ['BIGINT','TIMESTAMP','BOOLEAN','BIGINT','DATE',
        'BOOLEAN','BOOLEAN','BOOLEAN','BOOLEAN','BIGINT','DATE','DATE','BOOLEAN','BOOLEAN',
        'BOOLEAN','BOOLEAN','VARCHAR','VARCHAR','TIMESTAMP_S']
    print('PASS: TQS population/attributes, intention-only number bridge, all surviving numbers, '
          'parent/source mapping, current auto ID, verification, residual TAS, per-product counts and rerun.')


def test_verification_comes_only_from_tqs():
    db = make_db()
    status_sets = [
        ('Потребкредит',['0','10.0','одобрено','CHECK_LIST_EMPTY','CHECK_LIST_ANTIFRAUD_OR_PRODUCT']),
        ('Кредитные карты',['DONE','COURIER']),
        ('Автокредит',['APPROVE_RKK','APPROVED','PRE_APPROVED','APPROVE_CALL2','APPROVE_CALL3',
            'ORDER_CREATED','VERIFICATION','DRIVER_CARD_ISSUE','DRIVER_CARD_ISSUE_UPLOADED',
            'DOSSIER_UPLOADED','DEAL_VER','CREDIT_ISSUED','PRODUCT_BASKET_SIGNED'])]
    for pi, (product, statuses) in enumerate(status_sets):
        for si, status in enumerate(statuses):
            rk = 2000 + pi*100 + si
            qid = f'PRODUCT_{pi}_STATUS_{si}'
            add_tqs(db,qid,rk,status,product,end='2025-02-01',start='2020-01-01',qdate='2020-01-01')
            add_tqs(db,qid,rk,'DRAFT',product,start='2025-02-01')
    for rk, product, status in [(3001,'Потребкредит','DONE'),(3002,'Кредитные карты','0'),(3003,'Автокредит','COURIER')]:
        add_tqs(db,str(rk),rk,status,product)
    build(db)
    assert rows(db, f'select count(*) from {FINAL} where quest_verification_flg') == [(20,)]
    assert rows(db, f'select count(*) from {FINAL} where not quest_verification_flg') == [(3,)]
    assert rows(db, f'select count(*) from {S}.man_prt_tif_questionnaire_numbers') == [(0,)]
    print('PASS: all 20 historical TQS statuses, history before cohort, no intention rows required for flags.')


def test_native_products_and_duplicates():
    db = make_db()
    add_tqs(db,'KN',101)
    add_intention(db,'KN','ROOT')
    add_bdm(db,401,'ROOT')
    add_tas(db,301,'KN_CHILD',parent=401,level25_product_bp_nm=None,level35_product_bp_nm='NATIVE_KN_35')
    add_tqs(db,'AUTO',201,product='Автокредит')
    add_tas(db,501,'AUTO','ALPP',level25_product_bp_nm=None,level35_product_bp_nm='NATIVE_AUTO_35')
    add_tas(db,502,'AUTO_ONLY','ALPP',level25_product_bp_nm='Автокредит',level35_product_bp_nm=None)
    add_tqs(db,'NO_APP',102)
    add_tas(db,999,'UNKNOWN','OTHER',level25_product_bp_nm=None)
    build(db)
    assert rows(db,f'''select questionnaire_rk,application_rk,level25_product_bp_nm,level35_product_bp_nm
                      from {FINAL} order by questionnaire_rk,application_rk''') == [
        (-1,502,'Автокредит',None),(101,301,'Потребкредит','NATIVE_KN_35'),
        (102,-1,'Потребкредит',None),(201,501,'Автокредит','NATIVE_AUTO_35')]
    # A conflicting TAS payload must not be hidden by the key-only match grouping.
    add_tas(db,301,'KN_CHILD',parent=401,level25_product_bp_nm=None,
            level35_product_bp_nm='CONFLICTING_35',create_flg=False)
    build(db)
    assert rows(db,f'select count(*) from {FINAL} where questionnaire_rk=101') == [(2,)]
    assert reports(db)[2] == [(101,401,301,2)]
    print('PASS: separate native level35, missing TAS product fallback and visible conflicting TAS rows.')


def test_cohort_and_source_scope():
    db = make_db()
    add_tqs(db,'OLD',101,qdate='2025-01-01')
    add_tqs(db,'RECENT',102,qdate='2026-08-01')
    add_intention(db,'RECENT','OLD_ROOT')
    add_bdm(db,402,'OLD_ROOT',begin='2024-01-01')
    add_tas(db,302,'RECENT_CHILD',parent=402,application_dt='2026-08-01')
    add_tas(db,303,'OLD_APP',application_dt='2026-06-30')
    add_tqs(db,'DEPOSIT',103,'0','Депозиты')
    add_intention(db,'DEPOSIT','OLD_ROOT')
    build(db)
    assert rows(db,f'select count(*) from {FINAL}') == [(3,)]
    build(db,{'P_BEGIN_DATE':"'2026-07-01'"})
    assert rows(db,f'select questionnaire_rk,application_rk from {FINAL}') == [(102,302)]
    print('PASS: TQS-based cohort/product scope and an older BDM parent for a recent child.')


def test_minimal_contract_and_empty_input():
    source = SCRIPT.read_text()
    parse_sql(pg_sql())
    assert len(re.findall(r'^create table ', source, re.M)) == 9
    assert set(re.findall(r'\br\.(\w+)', source)) == {'questionnaire_id','application_num'}
    assert not re.search(r'\b(?:row_number|lead|lag|date_trunc)\s*\(', re.sub(r'/\*.*?\*/','',source,flags=re.S), re.I)
    assert not re.search(r'select\s+(?:\w+\.)?\*', source, re.I)
    assert 'min(q.questionnaire_dttm)' not in source
    assert 'tech_questionnaire_x_customer' not in source
    db = make_db()
    assert [r[0] for r in rows(db, f'describe {RAW}')] == ['questionnaire_id','application_num']
    build(db)
    assert rows(db, f'select count(*) from {FINAL}') == [(0,)]
    print('PASS: intention has only two columns; no copied TQS ETL, version reconstruction or additional RK source.')


if __name__ == '__main__':
    test_ready_tqs_and_number_bridge()
    test_verification_comes_only_from_tqs()
    test_native_products_and_duplicates()
    test_cohort_and_source_scope()
    test_minimal_contract_and_empty_input()
    print('Offline synthetic tests only; no bank/Greenplum execution.')
