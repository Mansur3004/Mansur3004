"""Synthetic comparison only: bridge-version predicates are example contracts."""
from pathlib import Path
import re
from decimal import Decimal
import duckdb
from pglast import parse_sql
from pglast.stream import RawStream

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'sql/compare_kn_kk_counterparty.sql'
MACROS={
 'db_sbx':'sbx_pre_orb_fd','p_db_cdmr':'dm_pik_fd_cdmr','p_db_bdm':'bdm',
 'p_max_date':"'2999-12-31'",
 'p_qc_current_condition':"qc.effective_to_dttm = timestamp '2999-12-31'",
 'p_cc_current_condition':"cc.effective_to_dttm = timestamp '2999-12-31'",
}
KN='Потребкредит'; KK='Кредитные карты'; AUTO='Автокредит'


def statements():
    sql=re.sub(r'&([A-Za-z_][A-Za-z0-9_]*)',lambda m:MACROS[m[1]],SCRIPT.read_text())
    sql=re.sub(r'\bdistributed by\s*\([^)]+\)\s*;', ';',sql,flags=re.I)
    return parse_sql(sql)


def run(db):
    stmts=statements()
    assert len(stmts)==15
    for stmt in stmts[:9]:
        sql=RawStream()(stmt.stmt).replace('pg_temp.','temp.main.')
        sql=re.sub(r'\bon commit preserve rows\b','',sql,flags=re.I)
        db.execute(sql)
    return [db.execute(RawStream()(x.stmt).replace('pg_temp.','temp.main.')).fetchall()
            for x in stmts[9:]]


def fixture():
    db=duckdb.connect()
    db.execute('''create schema sbx_pre_orb_fd; create schema dm_pik_fd_cdmr; create schema bdm;
      create table sbx_pre_orb_fd.man_prt_tif_v5_questionnaire (
        questionnaire_id text,questionnaire_rk bigint,level25_product_bp_nm text);
      create table sbx_pre_orb_fd.man_prt_tif_v5_questionnaire_numbers (
        questionnaire_id text,application_num text);
      create table sbx_pre_orb_fd.man_prt_tif_v5_tas (
        parent_application_rk bigint,application_rk bigint,parent_src_cd text,
        level25_product_bp_nm text);
      create table dm_pik_fd_cdmr.tech_questionnaire_x_customer (
        questionnaire_rk bigint,customer_rk bigint,effective_to_dttm timestamp);
      create table dm_pik_fd_cdmr.tech_customer_x_counterparty (
        customer_rk bigint,counterparty_rk bigint,effective_to_dttm timestamp);
      create table bdm.application (
        application_rk bigint,src_cd text,application_num text,counterparty_rk bigint,
        effective_to_date date);''')
    db.executemany('insert into sbx_pre_orb_fd.man_prt_tif_v5_questionnaire values (?,?,?)',
                   [(f'Q{i}',i,KN if i<5 else KK if i<7 else AUTO) for i in range(1,8)])
    db.executemany('insert into sbx_pre_orb_fd.man_prt_tif_v5_questionnaire_numbers values (?,?)',
                   [('Q1','N1'),('Q3','N3'),('Q5','N5'),('Q7','AUTO')])
    qc=[(1,11,'2999-12-31'),(1,11,'2999-12-31'),(1,12,'2999-12-31'),
        (1,13,'2999-12-31'),(2,22,'2999-12-31'),(3,33,'2024-12-31'),
        (4,44,'2999-12-31'),(5,55,'2999-12-31'),(6,-1,'2999-12-31'),
        (6,66,'2999-12-31')]
    cc=[(11,201,'2999-12-31'),(11,201,'2999-12-31'),(12,201,'2999-12-31'),
        (13,202,'2999-12-31'),(22,202,'2999-12-31'),(33,204,'2999-12-31'),
        (44,204,'2999-12-31'),(55,206,'2999-12-31'),(55,205,'2024-12-31'),
        (-1,201,'2999-12-31'),(66,-1,'2999-12-31')]
    db.executemany('insert into dm_pik_fd_cdmr.tech_questionnaire_x_customer values (?,?,?)',qc)
    db.executemany('insert into dm_pik_fd_cdmr.tech_customer_x_counterparty values (?,?,?)',cc)
    apps=[(401,'MSSA','N1',201,'2999-12-31'),(402,'MSSA','N2',202,'2999-12-31'),
          (403,'MSSA','N3',203,'2999-12-31'),(404,'MSSA','N4',204,'2999-12-31'),
          (405,'MSSA','N5',205,'2999-12-31'),(406,'MSSA','N6',206,'2999-12-31'),
          (407,'MSSA','N7',201,'2999-12-31'),(408,'MSSA','N8',201,'2999-12-31'),
          (409,'MSSA','N9',201,'2999-12-31'),(410,'MSSA','N10',201,'2024-12-31')]
    tas=[(401,501,'MSSA',KN),(401,502,'MSSA',KN),(402,503,'MSSA',KN),
         (403,504,'MSSA',KN),(404,505,'MSSA',KN),(405,506,'MSSA',KK),
         (406,507,'MSSA',KK),(407,508,'MSSA',None),(408,509,'OTHER',KN),
         (409,510,'MSSA',AUTO),(410,511,'MSSA',KN)]
    db.executemany('insert into bdm.application values (?,?,?,?,?)',apps)
    db.executemany('insert into sbx_pre_orb_fd.man_prt_tif_v5_tas values (?,?,?,?)',tas)
    return db


def test_same_population_and_ambiguity():
    db=fixture()
    before=db.execute('select count(*) from sbx_pre_orb_fd.man_prt_tif_v5_tas').fetchone()
    result=run(db)
    q={(p,r):(total,linked,Decimal(str(pct))) for p,r,total,linked,pct in result[0]}
    assert q[(KN,'APPLICATION_NUM')]==(4,2,Decimal('50.00'))
    assert q[(KN,'COUNTERPARTY_RK')]==(4,3,Decimal('75.00'))
    assert q[(KK,'APPLICATION_NUM')]==q[(KK,'COUNTERPARTY_RK')]==(2,1,Decimal('50.00'))
    tas={(p,r):(total,linked,Decimal(str(pct))) for p,r,total,linked,pct in result[1]}
    assert tas[(KN,'APPLICATION_NUM')]==(7,3,Decimal('42.86'))
    assert tas[(KN,'COUNTERPARTY_RK')]==(7,4,Decimal('57.14'))
    assert tas[(KK,'APPLICATION_NUM')]==tas[(KK,'COUNTERPARTY_RK')]==(2,1,Decimal('50.00'))
    assert tas[(None,'APPLICATION_NUM')]==(1,0,Decimal('0.00'))
    assert tas[(None,'COUNTERPARTY_RK')]==(1,1,Decimal('100.00'))
    assert dict((r[0],r[1:]) for r in result[2])=={KN:(4,1,1,2,0),KK:(2,1,0,0,1)}
    ambiguity={(r,p):(n,multi,roots,pairs) for r,p,n,multi,roots,pairs in result[3]}
    assert ambiguity[('COUNTERPARTY_RK',KN)]==(3,1,3,4)
    assert ambiguity[('APPLICATION_NUM',KN)]==(2,0,1,2)
    assert result[4]==[(5,KK,406,507,KK),(1,KN,402,503,KN),
                       (1,KN,407,508,None),(2,KN,402,503,KN),(4,KN,404,505,KN)]
    paths={(r,p):(raw,edges) for r,p,raw,edges in result[5]}
    assert paths[('COUNTERPARTY_RK',KN)]==(18,6)
    assert paths[('APPLICATION_NUM',KN)]==(3,3)
    assert db.execute('select count(*) from sbx_pre_orb_fd.man_prt_tif_v5_tas').fetchone()==before
    assert run(db)==result
    print('PASS: common cohorts, both coverage directions by product, overlap, root ambiguity, repeated bridge paths, old-version exclusion, source matching, NULL products, auto exclusion and rerun.')


def test_empty_cohort():
    db=fixture()
    db.execute('delete from sbx_pre_orb_fd.man_prt_tif_v5_questionnaire')
    db.execute('delete from sbx_pre_orb_fd.man_prt_tif_v5_tas')
    result=run(db)
    assert len(result[0])==len(result[1])==4
    assert all(row[2:]==(0,0,None) for row in result[0]+result[1])
    assert result[2:]==[[],[],[],[]]
    print('PASS: zero cohorts retain both products/routes and undefined percentages.')


if __name__=='__main__':
    test_same_population_and_ambiguity()
    test_empty_cohort()
    print('Synthetic DuckDB + PostgreSQL parsing only. Source bridge schemas/current-version contracts and bank coverage are not measured here.')
