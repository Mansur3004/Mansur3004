"""FT 03.11.2026: parent-key mapping, explicit key bridges and residual TAS.

No bank connection. PostgreSQL parsing and DuckDB synthetic execution;
Greenplum storage/distribution clauses are removed only by the test adapter.
"""
from pathlib import Path
import re
from pglast import parse_sql
from pglast.stream import RawStream
from funnel_fixtures import S, CDMR, RAW, MACROS, make_db, add_raw, add_tas

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
    sql = re.sub(r'with\s*\(APPENDONLY\s*=\s*true,\s*ORIENTATION\s*=\s*column,\s*'
                 r'COMPRESSTYPE\s*=\s*zstd,\s*COMPRESSLEVEL\s*=\s*5\)', '',
                 pg_sql(source, overrides), flags=re.I)
    sql = re.sub(r"coalesce\(upper\(r.first_nm\), '#'\) not like any \(array\[(.*?)\]\)",
        r"exists (select 1 from unnest(array[\1]) patterns(pattern) where coalesce(upper(r.first_nm), '#') not like pattern)",
        sql, flags=re.S)
    return re.sub(r"similar to '([^']*)'", lambda m: "~ '"+m[1].replace('%','.*')+"'", sql)


def db_new():
    db = make_db()
    db.execute(f'create table {CDMR}.tech_application_status as select * from {S}.tech_application_status')
    db.execute(f'drop table {S}.tech_application_status')
    db.execute(f'drop table {CDMR}.tech_questionnaire_x_customer')
    db.execute(f'''create table {CDMR}.tech_questionnaire_status (
        questionnaire_id text, questionnaire_rk bigint, questionnaire_dttm timestamp,
        status_cd text, level25_product_bp_nm text,
        effective_from_dttm timestamp, effective_to_dttm timestamp)''')
    return db


def tqs(db, qid, rk, status='DRAFT', product='Автокредит', end='2999-12-31', start='2025-01-01'):
    db.execute(f'insert into {CDMR}.tech_questionnaire_status values (?,?,\'2025-01-01\',?,?,?,?)',
               [qid, rk, status, product, start, end])


def questionnaire(db, qid, rk, code='KN', status='DRAFT', num=None, **overrides):
    add_raw(db, qid, code, status, num, **overrides)
    tqs(db, qid, rk, product='Кредитные карты' if code=='CreditCard' else 'Потребкредит')


def bdm(db, rk, num, src='MSSA', begin='2025-01-01', end='2999-12-31'):
    db.execute('insert into bdm.application values (?,?,?,?,?)', [rk,num,src,end,begin])


def rows(db, sql):
    return db.execute(sql).fetchall()


def build(db, overrides=None):
    db.execute(execution_sql(overrides=overrides))


def test_parent_mapping_and_residuals():
    db=db_new()
    questionnaire(db, 'OLD_DIRECT_PATH', 101, num='DIRECT')
    bdm(db, 301, 'DIRECT', 'MSCL')
    add_tas(db, 301, 'DIRECT_ID', 'MSCL', 401, level25_product_bp_nm='Потребкредит')
    questionnaire(db, 'PARENT_KK', 102, 'CreditCard', num='ROOT')
    bdm(db, 402, 'ROOT')
    # A second historical number leads to the same parent. It must not duplicate the pairs.
    add_raw(db, 'PARENT_KK', 'CreditCard', 'SCORING', 'ROOT_OLD')
    bdm(db, 402, 'ROOT_OLD')
    add_tas(db, 302, 'KK_CHILD', 'CCPP_BATR', 402, level25_product_bp_nm='Кредитные карты')
    add_tas(db, 303, 'KN_CHILD', 'MSCL', 402, level25_product_bp_nm='Потребкредит')
    add_tas(db, 304, 'WRONG_PARENT_SOURCE', 'MSCL', 402, parent_src='OTHER', level25_product_bp_nm='Потребкредит')
    questionnaire(db, 'PARENT_ONLY', 103, num='ONLY')
    bdm(db, 403, 'ONLY')
    add_tas(db, -1, None, None, 403, level25_product_bp_nm='Потребкредит')
    questionnaire(db, 'OLD_SELF_PATH', 104, num='SELF')
    bdm(db, 405, 'SELF')
    add_tas(db, 405, 'SELF_ID', 'MSSA', level25_product_bp_nm='Потребкредит')
    questionnaire(db, 'Q_TRUE', 105, status='0')
    questionnaire(db, 'Q_FALSE', 106, 'CreditCard')
    # Parent lookup must not be excluded just because the parent predates its child.
    questionnaire(db, 'OLD_PARENT', 107, num='OLD_PARENT_NUM')
    bdm(db, 406, 'OLD_PARENT_NUM', begin='2024-01-01')
    add_tas(db, 307, 'NEW_CHILD', 'MSCL', 406, level25_product_bp_nm='Потребкредит')
    questionnaire(db, 'NO_TQS', 108)
    db.execute(f"delete from {CDMR}.tech_questionnaire_status where questionnaire_id='NO_TQS'")
    questionnaire(db, 'BAD_MAPPING', -1)
    tqs(db, 'AUTO_LINKED', 201)
    tqs(db, 'AUTO_TRUE', 202, 'APPROVED', end='2025-02-01')
    tqs(db, 'AUTO_TRUE', 202, start='2025-02-01')
    tqs(db, 'AUTO_FALSE', 203)
    add_tas(db, 501, 'AUTO_LINKED', 'ALPP', level25_product_bp_nm='Автокредит')
    add_tas(db, 502, 'AUTO_ONLY', 'ALPP', level25_product_bp_nm='Автокредит')
    add_tas(db, -1, 'INVALID_TAS', 'ALPP', level25_product_bp_nm='Автокредит')
    # Product selection is by level25, not a one-source/one-product assumption.
    add_tas(db, 503, 'NOT_A_CREDIT', 'MSCL', level25_product_bp_nm='Депозиты')
    expected=[(-1,401,301,None),(-1,402,304,None),(-1,-1,405,None),(-1,-1,502,None),
              (101,-1,-1,False),(102,402,302,True),(102,402,303,True),
              (103,403,-1,True),(104,-1,-1,False),(105,-1,-1,True),(106,-1,-1,False),
              (107,406,307,True),(201,-1,501,True),(202,-1,-1,True),(203,-1,-1,False)]
    for _ in range(2):
        build(db)
        actual=rows(db,f'''select questionnaire_rk,parent_application_rk,application_rk,quest_verification_flg
                          from {FINAL}''')
        assert set(actual)==set(expected), actual
        assert len(actual)==len(expected)
        assert rows(db,f'''select count(*) from {FIRST} f join {REMAINING} t
                          on f.parent_application_rk=t.parent_application_rk
                         and f.application_rk=t.application_rk''')==[(0,)]
        assert rows(db,f'''select count(*) from {FINAL}
                          where questionnaire_rk is null or parent_application_rk is null or application_rk is null''')==[(0,)]
        # Execute each independent production check after building the same cohort.
        reports=[db.execute(RawStream()(stmt.stmt)).fetchall() for stmt in parse_sql(CHECKS.read_text())]
        assert reports[0]==[] and reports[1]==[] and reports[2]==[]
        assert all(report==[(0,)] for report in reports[3:7])
        assert dict(reports[7])=={'Потребкредит':5,'Кредитные карты':2,'Автокредит':3}
        assert dict(reports[8])=={'Потребкредит':2,'Кредитные карты':1,'Автокредит':1}
        assert dict(reports[9])=={'Потребкредит':6,'Кредитные карты':1,'Автокредит':2}
        assert dict(reports[10])=={'Потребкредит':3,'Кредитные карты':1,'Автокредит':1}
        assert reports[11]==[]
    assert [r[0] for r in rows(db,f'describe {FINAL}')]==FINAL_FIELDS
    assert rows(db,f'''select count(*) from {FINAL}
                      where parent_application_rk=-1 and application_rk=-1
                        and level35_product_bp_nm is not null''')==[(0,)]
    print('PASS: parent-only mapping/source equality, old routes excluded, historical numbers, '
          'product scope, true-on-link, both unmatched sides, one residual per TAS key and rerun.')


def test_tas_duplicates_are_not_masked():
    db=db_new()
    add_tas(db,301,'DUPLICATE','MSCL',401,level25_product_bp_nm='Потребкредит',create_flg=True)
    add_tas(db,301,'DUPLICATE','MSCL',401,level25_product_bp_nm='Потребкредит',create_flg=False)
    build(db)
    assert rows(db,f'select count(*) from {S}.man_prt_tif_kn_kk_tas')==[(2,)]
    assert rows(db,f'select count(*) from {FINAL}')==[(2,)]
    assert rows(db,f'''select parent_application_rk,application_rk,count(*)
                      from {FINAL} group by 1,2 having count(*)>1''')==[(401,301,2)]
    checks=parse_sql(CHECKS.read_text())
    assert db.execute(RawStream()(checks[1].stmt)).fetchall()==[(401,301,2)]
    assert db.execute(RawStream()(checks[2].stmt)).fetchall()==[(-1,401,301,2)]
    print('PASS: conflicting TAS rows remain visible; no DISTINCT or arbitrary latest-processed rule hides them.')


def test_original_history_and_empty():
    db=db_new()
    questionnaire(db,'HISTORY_KN',1001,status='0')
    add_raw(db,'HISTORY_KN','KN','DRAFT')
    questionnaire(db,'HISTORY_KK',1002,'CreditCard','DONE')
    add_raw(db,'HISTORY_KK','CreditCard','DRAFT')
    tqs(db,'HISTORY_AUTO',1003,'VERIFICATION',end='2025-02-01')
    tqs(db,'HISTORY_AUTO',1003,start='2025-02-01')
    questionnaire(db,'TEST_CLIENT',1004,first_nm='ЛИД')
    build(db)
    assert rows(db,f'select count(*) from {FINAL} where quest_verification_flg')==[(3,)]
    assert rows(db,f'select count(*) from {FINAL} where questionnaire_rk=1004')==[(0,)]
    source=SCRIPT.read_text()
    assert len(re.findall(r'\bselect\s+distinct\b',source,re.I))==1
    assert not re.search(r'select\s+(?:\w+\.)?\*',source,re.I)
    assert 'q.bdm_application_rk = t.parent_application_rk' in source
    assert 'q.bdm_application_rk = t.application_rk' not in source
    assert 'tech_questionnaire_x_customer' not in source
    parse_sql(pg_sql())
    db=db_new();build(db)
    assert rows(db,f'select count(*) from {FINAL}')==[(0,)]
    print('PASS: original cleaning, historical flags, explicit attributes, PostgreSQL parse, empty source.')


def test_all_product_statuses():
    db=db_new()
    status_sets=[
        ('KN',['0','10.0','одобрено','CHECK_LIST_EMPTY','CHECK_LIST_ANTIFRAUD_OR_PRODUCT']),
        ('CreditCard',['DONE','COURIER']),
        ('AutoLoan',['APPROVE_RKK','APPROVED','PRE_APPROVED','APPROVE_CALL2','APPROVE_CALL3',
                    'ORDER_CREATED','VERIFICATION','DRIVER_CARD_ISSUE','DRIVER_CARD_ISSUE_UPLOADED',
                    'DOSSIER_UPLOADED','DEAL_VER','CREDIT_ISSUED','PRODUCT_BASKET_SIGNED'])]
    for product_index,(code,statuses) in enumerate(status_sets):
        for status_index,status in enumerate(statuses):
            rk=2000+product_index*100+status_index
            qid=f'PRODUCT_{product_index}_STATUS_{status_index}'
            if code=='AutoLoan':
                tqs(db,qid,rk,status,end='2025-02-01')
                tqs(db,qid,rk,start='2025-02-01')
            else:
                questionnaire(db,qid,rk,code,status)
                add_raw(db,qid,code,'DRAFT')
    questionnaire(db,'KN_WRONG_STATUS',3001,status='DONE')
    questionnaire(db,'KK_WRONG_STATUS',3002,'CreditCard','0')
    tqs(db,'AUTO_WRONG_STATUS',3003,'COURIER')
    build(db)
    assert rows(db,f'select count(*) from {FINAL} where quest_verification_flg')==[(20,)]
    assert rows(db,f'select count(*) from {FINAL} where not quest_verification_flg')==[(3,)]
    print('PASS: all 20 historical verification statuses and product-specific negative cases.')


def test_missing_tas_product_fallback():
    db=db_new()
    questionnaire(db,'KN_PRODUCT_FALLBACK',101,num='ROOT')
    bdm(db,401,'ROOT')
    add_tas(db,301,'KN_CHILD','MSCL',401,level25_product_bp_nm=None)
    tqs(db,'AUTO_PRODUCT_FALLBACK',201)
    add_tas(db,501,'AUTO_PRODUCT_FALLBACK','ALPP',level25_product_bp_nm=None)
    add_tas(db,999,'UNKNOWN_UNLINKED','OTHER',level25_product_bp_nm=None)
    build(db)
    assert rows(db,f'''select questionnaire_rk,level25_product_bp_nm,quest_verification_flg
                      from {FINAL} order by 1''')==[(101,'Потребкредит',True),(201,'Автокредит',True)]
    assert rows(db,f'select count(*) from {REMAINING}')==[(0,)]
    checks=parse_sql(CHECKS.read_text())
    assert db.execute(RawStream()(checks[9].stmt)).fetchall()==[(None,2)]
    assert db.execute(RawStream()(checks[10].stmt)).fetchall()==[(None,2)]
    print('PASS: NULL TAS product falls back to linked questionnaire; unidentified unlinked products stay out of scope.')


def test_recalculation_cohort():
    db=db_new()
    questionnaire(db,'OLD_COHORT',101)
    questionnaire(db,'CURRENT_COHORT',102,num='OLD_ROOT',questionnaire_dt='2026-08-01 00:00:00')
    bdm(db,402,'OLD_ROOT',begin='2025-01-01')
    add_tas(db,302,'CURRENT_CHILD','MSCL',402,application_dt='2026-08-01',level25_product_bp_nm='Потребкредит')
    add_tas(db,303,'BEFORE_QUARTER','MSCL',application_dt='2026-06-30',level25_product_bp_nm='Потребкредит')
    build(db)
    assert rows(db,f'select count(*) from {FINAL}')==[(3,)]
    build(db,{'P_BEGIN_DATE':"'2026-07-01'"})
    assert rows(db,f'select questionnaire_rk,application_rk from {FINAL}')==[(102,302)]
    # The ETL-calculated lower bound for November is the start of Q3.
    assert rows(db,"select greatest(date '2025-01-01', cast(date_trunc('quarter', timestamp '2026-11-03') as date) - interval '3 months')")[0][0].strftime('%Y-%m-%d')=='2026-07-01'
    print('PASS: initial and rolling-quarter calculation cohorts; old parent lookup remains available.')


def test_current_auto_id_and_historical_verification():
    db=db_new()
    tqs(db,'OLD_AUTO_ID',201,'APPROVED',end='2025-02-01')
    tqs(db,'CURRENT_AUTO_ID',201,'DRAFT',start='2025-02-01')
    add_tas(db,501,'CURRENT_AUTO_ID','ALPP',level25_product_bp_nm='Автокредит')
    add_tas(db,502,'OLD_AUTO_ID','ALPP',level25_product_bp_nm='Автокредит')
    build(db)
    assert rows(db,f'''select questionnaire_id,questionnaire_rk,quest_verification_flg
                      from {S}.man_prt_tif_auto_verification''')==[('CURRENT_AUTO_ID',201,True)]
    assert rows(db,f'''select questionnaire_rk,application_rk,quest_verification_flg
                      from {FINAL} order by questionnaire_rk''')==[(-1,502,None),(201,501,True)]
    print('PASS: current TQS ID joins latest TAS state; historical statuses still determine verification.')


def test_native_level35():
    db=db_new()
    questionnaire(db,'KN_NATIVE35',101,num='ROOT')
    bdm(db,401,'ROOT')
    add_tas(db,301,'KN_CHILD','MSCL',401,
            level25_product_bp_nm='Потребкредит',level35_product_bp_nm='SOURCE_KN_LEVEL35')
    questionnaire(db,'KN_WITHOUT_APP',102)
    tqs(db,'AUTO_NATIVE35',201)
    add_tas(db,501,'AUTO_NATIVE35','ALPP',
            level25_product_bp_nm='Автокредит',level35_product_bp_nm='SOURCE_AUTO_LEVEL35')
    add_tas(db,502,'AUTO_ONLY','ALPP',
            level25_product_bp_nm='Автокредит',level35_product_bp_nm='SOURCE_APP_ONLY_LEVEL35')
    tqs(db,'AUTO_NULL35',202)
    add_tas(db,503,'AUTO_NULL35','ALPP',level25_product_bp_nm='Автокредит',level35_product_bp_nm=None)
    build(db)
    assert rows(db,f'''select questionnaire_rk,application_rk,level35_product_bp_nm
                      from {FINAL} order by questionnaire_rk,application_rk''')==[
        (-1,502,'SOURCE_APP_ONLY_LEVEL35'),(101,301,'SOURCE_KN_LEVEL35'),
        (102,-1,None),(201,501,'SOURCE_AUTO_LEVEL35'),(202,503,None)]
    source=SCRIPT.read_text()
    lines=[line for line in source.splitlines() if ' as level35_product_bp_nm' in line]
    assert len(lines)==3 and all('t.level35_product_bp_nm' in line for line in lines)
    print('PASS: native TAS level35 in linked and residual branches; no copy/fallback from level25.')


if __name__=='__main__':
    test_parent_mapping_and_residuals()
    test_tas_duplicates_are_not_masked()
    test_original_history_and_empty()
    test_all_product_statuses()
    test_missing_tas_product_fallback()
    test_recalculation_cohort()
    test_current_auto_id_and_historical_verification()
    test_native_level35()
    print('Synthetic tests only; real Greenplum/source schemas remain unverified.')
