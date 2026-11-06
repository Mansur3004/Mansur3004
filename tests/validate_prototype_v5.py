"""Synthetic V5 checks: source ranking, cardinality and residuals; no bank access."""
from pathlib import Path
import re
import subprocess
from pglast import parse_sql
from pglast.stream import RawStream
from funnel_fixtures import S, RAW, MACROS, make_db, add_intention, add_tqs, add_bdm, add_tas
from validate_prototype_v4 import FINAL_FIELDS, execution_sql

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'sql/build_internet_funnel_v5.sql'
CHECKS = ROOT / 'sql/check_internet_funnel_v5.sql'
PREFIX = f'{S}.man_prt_tif_v5_'
FINAL = PREFIX + 'tech_internet_funnel'
VALUES = MACROS | {'p_min_dttm': "'1900-01-01 00:00:00'"}
RAW_COLUMNS = {
    'createtime_dttm':'text', 'sessionintention_id':'text', 'processed_dttm':'text',
    'business_dt':'text', 'utmcn':'text', 'utmcct':'text', 'utmcmd':'text',
    'globalclient_id':'text', 'person_id':'text', 'last_nm':'text', 'first_nm':'text',
    'middle_nm':'text', 'tax_payer_num':'text', 'email':'text', 'client_type':'text',
    'company_nm':'text', 'phone_num':'text', 'credit_amt':'numeric',
    'zero_visits_flg':'integer', 'product_type_code':'text', 'questionnaire_dt':'text',
    'program_type':'text', 'scoring_dt':'text', 'prescoring_dt':'text',
    'scoring_status_nm':'text', 'prescoring_status_nm':'text', 'spec_program':'text',
    'src_cd_src':'text', 'salary_card_flg':'integer', 'status':'text',
}


def db_with_raw():
    db = make_db()
    # Match PostgreSQL defaults in the original TQS ORDER BY.
    db.execute("set default_null_order='Postgres'")
    for name, kind in RAW_COLUMNS.items():
        db.execute(f'alter table {RAW} add column {name} {kind}')
    return db


def intention(db, qid, number, **kwargs):
    values = {'questionnaire_id':qid, 'application_num':number} | kwargs
    db.execute(f"insert into {RAW} ({', '.join(values)}) values ({', '.join('?' for _ in values)})",
               list(values.values()))


def build(db):
    db.execute(execution_sql(SCRIPT.read_text(), VALUES))


def query(db, text):
    return db.execute(text).fetchall()


def test_original_priority_and_one_number():
    db = db_with_raw()
    for rk, qid in enumerate(['SAME_NUMBER', 'NEWEST', 'SESSION', 'PROCESSED', 'NUMBER', 'NO_NUMBER'], 1):
        add_tqs(db, qid, rk)
    # Repeated status/history records with the same number: one bridge row.
    intention(db,'SAME_NUMBER','N1',status='0',createtime_dttm='2025-01-01')
    intention(db,'SAME_NUMBER','N1',status='DONE',createtime_dttm='2025-02-01')
    intention(db,'SAME_NUMBER','N1',status='DONE',createtime_dttm='2025-02-01')
    # More than one number is deliberately tested, though not observed in the bank slice.
    intention(db,'NEWEST','OLD',createtime_dttm='2025-01-01')
    intention(db,'NEWEST','NEW',createtime_dttm='2025-02-01')
    intention(db,'NEWEST',None,createtime_dttm='2026-01-01')
    # sessionintention_id ASC precedes processed_dttm DESC, just as in source TQS.
    intention(db,'SESSION','FIRST_SESSION',sessionintention_id='A',processed_dttm='2025-01-01')
    intention(db,'SESSION','LATER_PROCESSED',sessionintention_id='B',processed_dttm='2026-01-01')
    intention(db,'PROCESSED','OLD',processed_dttm='2025-01-01')
    intention(db,'PROCESSED','NEW',processed_dttm='2025-03-01')
    intention(db,'NUMBER','A')
    intention(db,'NUMBER','B')
    intention(db,'NO_NUMBER',None)
    intention(db,'NOT_IN_TQS','OUTSIDE')
    build(db)
    assert query(db,f'select * from {PREFIX}questionnaire_numbers order by questionnaire_id') == [
        ('NEWEST','NEW'),('NUMBER','B'),('PROCESSED','NEW'),('SAME_NUMBER','N1'),('SESSION','FIRST_SESSION')]
    assert query(db,f'select count(*) from {FINAL}') == [(6,)]
    # No GROUP BY or DISTINCT is used to deduplicate any relation after the bridge.
    assert len(re.findall(r'\bgroup by\b', re.sub(r'/\*.*?\*/|--[^\n]*','',SCRIPT.read_text(),flags=re.S), re.I)) == 1
    print('PASS: one nonempty number per ID, duplicate histories, unchanged full TQS priorities and null numbers.')


def test_links_and_no_path_multiplication():
    db = db_with_raw()
    add_tqs(db,'KN',1)
    add_tqs(db,'KK',2,product='Кредитные карты')
    add_tqs(db,'AUTO',3,product='Автокредит')
    add_tqs(db,'NO_NUMBER',4,status='0')
    intention(db,'KN','ROOT')
    intention(db,'KN','ROOT')
    intention(db,'KK','ROOT_KK')
    add_bdm(db,401,'ROOT')
    add_bdm(db,402,'ROOT_KK')
    add_tas(db,501,'CHILD1',parent=401)
    add_tas(db,502,'CHILD2',parent=401)
    add_tas(db,-1,None,parent=402,level25_product_bp_nm='Кредитные карты')
    add_tas(db,601,'AUTO','ALPP',level25_product_bp_nm='Автокредит')
    add_tas(db,602,'REMAINING_AUTO','ALPP',level25_product_bp_nm='Автокредит')
    add_tas(db,503,'REMAINING_KN',parent=403)
    # Native level35 and the currently unused NULL-product fallback remain functional.
    add_tas(db,504,'NULL_PRODUCT',parent=401,level25_product_bp_nm=None,level35_product_bp_nm='NATIVE_35')
    add_tas(db,-1,None,parent=-1)
    # On the observed contract (one distinct number per ID), outputs match V4.
    # A V5 run must also preserve all V4 tables.
    db.execute(execution_sql())
    previous_rows=query(db,f'select * from {S}.man_prt_tif_tech_internet_funnel')
    for _ in range(2):
        build(db)
        result=query(db,f'''select questionnaire_rk,parent_application_rk,application_rk,
                                   quest_verification_flg from {FINAL}''')
        expected={(1,401,501,True),(1,401,502,True),(1,401,504,True),
                  (2,402,-1,True),(3,-1,601,True),(4,-1,-1,True),
                  (-1,-1,602,None),(-1,403,503,None)}
        assert set(result)==expected and len(result)==len(expected),result
        assert query(db,f'select * from {S}.man_prt_tif_tech_internet_funnel')==previous_rows
        assert sorted(query(db,f'select * from {FINAL}'),key=repr)==sorted(previous_rows,key=repr)
        reports=[db.execute(RawStream()(x.stmt)).fetchall() for x in parse_sql(CHECKS.read_text())]
        assert reports[0:3]==[[],[],[]]
        assert reports[3:7]==[[(0,)],[(0,)],[(0,)],[(0,)]]
        assert reports[11:14]==[[],[],[]]
        assert reports[14]==[]
        assert reports[15]==[]
    assert [r[0] for r in query(db,f'describe {FINAL}')]==FINAL_FIELDS
    assert query(db,f'select level35_product_bp_nm from {FINAL} where application_rk=504')==[('NATIVE_35',)]
    assert query(db,f'select level35_product_bp_nm from {FINAL} where questionnaire_rk=4')==[(None,)]
    # Do not invent a TAS winner: conflicting source payloads must remain diagnosable.
    add_tas(db,501,'CHILD1',parent=401,create_flg=False)
    build(db)
    assert query(db,f'select count(*) from {FINAL} where questionnaire_rk=1 and application_rk=501')==[(2,)]
    # A BDM contract violation is exposed, not silently corrected by an invented ordering.
    add_bdm(db,402,'ROOT_KK')
    build(db)
    assert query(db,f'select count(*) from {FINAL} where questionnaire_rk=2')==[(2,)]
    print('PASS: source dedup prevents path multiplication, real children/parent-only preserved, auto, residuals, source conflicts and V4 isolation.')


def test_source_priority_and_sql_contract():
    source=SCRIPT.read_text()
    parse_sql(re.sub(r'\bdistributed\s+randomly\s*;', ';',
                    re.sub(r'&([A-Za-z_][A-Za-z0-9_]*)',lambda m: VALUES[m[1]],source),flags=re.I))
    old=subprocess.check_output(['git','show','e5573dd:sql/build_internet_funnel_v3.sql'],cwd=ROOT,text=True)
    original=old[old.index('        order by\n'):old.index('    ) as rn,')]
    assert original in source
    assert len(re.findall(r'^create table ',source,re.M))==9
    db=db_with_raw(); build(db)
    assert query(db,f'select count(*) from {FINAL}')==[(0,)]
    print('PASS: PostgreSQL parsing, verbatim source ORDER BY, nine isolated V5 tables and empty inputs.')


if __name__=='__main__':
    test_original_priority_and_one_number()
    test_links_and_no_path_multiplication()
    test_source_priority_and_sql_contract()
    print('Synthetic DuckDB checks only; Greenplum runtime and execution plan not measured.')
