"""Read-only join checks: exact duplicates, real multiplicity and RK filter impact."""
from pathlib import Path
from pglast import parse_sql
from pglast.stream import RawStream
from funnel_fixtures import S, make_db, add_bdm

SCRIPT=Path(__file__).resolve().parents[1]/'sql/proverka_bdm.sql'


def test_checks():
    db=make_db()
    db.execute(f'''create table {S}.man_prt_tif_questionnaire (
        questionnaire_id text, questionnaire_rk bigint, level25_product_bp_nm text);
        create table {S}.man_prt_tif_questionnaire_numbers (
        questionnaire_id text, application_num text);''')
    for rk in range(1,6):
        db.execute(f'insert into {S}.man_prt_tif_questionnaire values (?,?,?)',
                   [f'Q{rk}',rk,'Потребкредит'])
        db.execute(f'insert into {S}.man_prt_tif_questionnaire_numbers values (?,?)',
                   [f'Q{rk}',f'N{rk}'])
    db.execute(f"insert into {S}.man_prt_tif_questionnaire values ('Q4',4,'Потребкредит')")
    db.execute(f"insert into {S}.man_prt_tif_questionnaire_numbers values ('Q5','N5')")
    add_bdm(db,401,'N1'); add_bdm(db,401,'N1')
    add_bdm(db,401,'N1',end='2024-12-31')  # Historical version must not count.
    add_bdm(db,402,'N2'); add_bdm(db,403,'N2',src='MSCL')
    add_bdm(db,None,'N3'); add_bdm(db,-1,'N3')
    add_bdm(db,404,'N4'); add_bdm(db,405,'N5')
    add_bdm(db,None,'OUTSIDE')
    statements=parse_sql(SCRIPT.read_text())
    assert len(statements)==5
    result=[db.execute(RawStream()(s.stmt)).fetchall() for s in statements]
    assert result==[
        [(1,'Потребкредит',401,'MSSA',2),(4,'Потребкредит',404,'MSSA',2),
         (5,'Потребкредит',405,'MSSA',2)],
        [('N1',2,1),('N2',2,2)],[(8,1,1)],[('Q4',2)],[('Q5',2)]
    ],result
    print('PASS: exact output repeats, distinct BDM links, NULL/sentinel impact, historical exclusion and both input cardinalities.')


if __name__=='__main__':
    test_checks()
    print('Synthetic DuckDB checks and PostgreSQL parsing only; no bank execution.')
