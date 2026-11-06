"""Validate the diagnostic with ties, source drift and full duplicates; no bank access."""
from pathlib import Path
import re
from pglast import parse_sql
from pglast.stream import RawStream
from validate_prototype_v5 import db_with_raw, intention, RAW

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'sql/proverka_intention.sql'
SOURCE=ROOT/'sql/build_internet_funnel_v5.sql'


def parse_gp(sql):
    return parse_sql(re.sub(r'\bdistributed by\s*\([^)]+\)\s*;', ';',sql,flags=re.I))


def for_duckdb(sql):
    sql=sql.replace('pg_temp.', 'temp.main.')
    sql=re.sub(r'\bon commit preserve rows\b', '',sql,flags=re.I)
    sql=re.sub(r'\bdistributed by\s*\([^)]+\)\s*;', ';',sql,flags=re.I)
    return sql


def field_report_duckdb(db):
    # DuckDB json_each is a table function; GP/PostgreSQL json_each is an SRF.
    # All other statements execute directly after TEMP/distribution syntax adaptation.
    return db.execute('''
        with sample_groups as (
            select questionnaire_id, priority_rank
            from temp.main.man_prt_check_intention_groups
            where priority_rank=1 and different_source_rows>1
            order by questionnaire_id limit 100
        ), field_values as (
            select v.questionnaire_id,v.priority_rank,
                   e.key as column_name,cast(e.value as text) as value_json
            from temp.main.man_prt_check_intention_variants v
            inner join sample_groups g on g.questionnaire_id=v.questionnaire_id
                                      and g.priority_rank=v.priority_rank,
                 json_each(v.source_row_json) e
        )
        select questionnaire_id,priority_rank,column_name,count(distinct value_json)
        from field_values group by questionnaire_id,priority_rank,column_name
        having count(distinct value_json)>1 order by questionnaire_id,column_name
    ''').fetchall()


def fixture():
    db=db_with_raw()
    db.execute(f'alter table {RAW} add column unseen_source_field text')
    db.execute('''create table sbx_pre_orb_fd.man_prt_tif_questionnaire (
                  questionnaire_id text, level25_product_bp_nm text)''')
    cases={
        'UNIQUE':[{}],
        'FULL':[{},{}],
        'PARTIAL':[{'status':'DRAFT'},{'status':'DONE'}],
        'MIXED':[{'status':'A'},{'status':'A'},{'status':'B'}],
        'LOWER':[{'createtime_dttm':'2026-01-01'},
                 {'createtime_dttm':'2025-01-01'},{'createtime_dttm':'2025-01-01'}],
        'NEW_COLUMN':[{'unseen_source_field':'X'},{'unseen_source_field':'Y'}],
        'NUMBERS':[{'number':'N1'},{'number':'N2'}],
        'NULL_NUMBER':[{'number':None},{'number':'N1'}],
        'COALESCE':[{'globalclient_id':None,'first_nm':None},
                    {'globalclient_id':'#','first_nm':'#'}],
        'NULL_STRING':[{'unseen_source_field':None},{'unseen_source_field':'null'}],
    }
    for qid, records in cases.items():
        db.execute('insert into sbx_pre_orb_fd.man_prt_tif_questionnaire values (?,?)',
                   [qid,'Потребкредит'])
        for record in records:
            record=dict(record)
            number=record.pop('number','N')
            intention(db,qid,number,**record)
    intention(db,'OUTSIDE','N')
    db.execute("insert into sbx_pre_orb_fd.man_prt_tif_questionnaire values ('AUTO','Автокредит')")
    intention(db,'AUTO','N')
    return db


def execute_report(db, source=None):
    source=SCRIPT.read_text() if source is None else source
    # Parse the actual file, including PostgreSQL SRF/composite-field syntax.
    ast=parse_gp(source)
    assert len(ast)==10
    for stmt in ast[:6]:
        db.execute(for_duckdb(RawStream()(stmt.stmt)))
    reports=[]
    for i,stmt in enumerate(ast[6:]):
        reports.append(field_report_duckdb(db) if i==2 else
                       db.execute(for_duckdb(RawStream()(stmt.stmt))).fetchall())
    return reports


def test_ties_and_source_drift():
    db=fixture()
    result=execute_report(db)
    assert result[0]==[
        ('ALL_PRIORITY_GROUPS',13,21,7,2,5,3,0,1),
        ('WINNERS',10,17,6,1,5,2,0,1)],result[0]
    assert {x[0]:x[-1] for x in result[1]}=={
        'FULL':'FULL_DUPLICATES','PARTIAL':'DIFFERENT_SOURCE_ROWS_WITH_EQUAL_ORDER',
        'MIXED':'DIFFERENT_SOURCE_ROWS_WITH_EQUAL_ORDER',
        'NEW_COLUMN':'DIFFERENT_SOURCE_ROWS_WITH_EQUAL_ORDER',
        'COALESCE':'DIFFERENT_SOURCE_ROWS_WITH_EQUAL_ORDER',
        'NULL_STRING':'DIFFERENT_SOURCE_ROWS_WITH_EQUAL_ORDER'}
    assert result[2]==[
        ('COALESCE',1,'first_nm',2),('COALESCE',1,'globalclient_id',2),
        ('MIXED',1,'status',2),('NEW_COLUMN',1,'unseen_source_field',2),
        ('NULL_STRING',1,'unseen_source_field',2),('PARTIAL',1,'status',2)],result[2]
    assert result[3]==[('FULL',1,2),('LOWER',2,2),('MIXED',1,2)],result[3]
    # Re-running is safe in the same session and produces identical diagnostics.
    assert execute_report(db)==result
    # Reports read the frozen diagnostic tables, not a source that may change mid-review.
    intention(db,'UNIQUE','NEW_NUMBER',createtime_dttm='2027-01-01')
    summary=parse_gp(SCRIPT.read_text())[6]
    assert db.execute(for_duckdb(RawStream()(summary.stmt))).fetchall()==result[0]
    print('PASS: full/partial/mixed ties, new source columns, COALESCE collisions, NULL/string null, lower priorities, number stability and frozen snapshot.')


def test_v5_scope_and_empty():
    db=fixture()
    result=execute_report(db,SCRIPT.read_text().replace('select false as only_nonnull_numbers',
                                                      'select true as only_nonnull_numbers'))
    assert result[0][0]==('ALL_PRIORITY_GROUPS',12,20,7,2,5,3,0,0),result[0]
    assert result[0][1]==('WINNERS',10,17,6,1,5,2,0,0),result[0]
    db.execute('delete from sbx_pre_orb_fd.man_prt_tif_questionnaire')
    result=execute_report(db)
    assert result[0]==[('ALL_PRIORITY_GROUPS',0,0,0,0,0,0,0,0),
                       ('WINNERS',0,0,0,0,0,0,0,0)],result[0]
    assert result[1:]==[[],[],[]]
    print('PASS: optional V5 nonempty-number filter and explicitly visible empty scope.')


def test_same_order_as_v5():
    def order(text, window_start, end):
        text=text[text.index(window_start):]
        text=text[text.index('order by'):text.index(end)]
        text=text.replace('cast(&p_min_dttm as timestamp)',"timestamp '1900-01-01 00:00:00'")
        return re.sub(r'\s+',' ',text).strip()
    original=order(SOURCE.read_text(),'with ranked as (',') as rn')
    diagnostic=order(SCRIPT.read_text(),'dense_rank() over (',') as priority_rank')
    assert original==diagnostic,(original,diagnostic)
    print('PASS: the actual diagnostic ORDER BY matches V5 exactly.')


if __name__=='__main__':
    test_ties_and_source_drift()
    test_v5_scope_and_empty()
    test_same_order_as_v5()
    print('PostgreSQL syntax parsed; DuckDB fixtures exercised. No bank/Greenplum execution.')
