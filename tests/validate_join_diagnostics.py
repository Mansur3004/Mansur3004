"""Prove that read-only diagnostics distinguish duplicates, ambiguity and valid 1:N."""
from pathlib import Path
from pglast import parse_sql
from pglast.stream import RawStream
from funnel_fixtures import make_db, add_tqs, add_intention, add_bdm, add_tas
from validate_prototype_v4 import build

SQL = Path(__file__).resolve().parents[1] / 'sql/diagnose_join_multiplicity.sql'


def test_different_multiplicities():
    db=make_db()
    add_tqs(db,'Q1',1)
    add_tqs(db,'Q2',2)
    add_tqs(db,'Q2_OTHER_ID',2)
    add_tqs(db,'Q3',3,product='Автокредит')
    add_tqs(db,'Q4',4)
    add_tqs(db,'SHARED_ID',5)
    add_tqs(db,'SHARED_ID',6,product='Кредитные карты')
    for qid,number in [('Q1','N1'),('Q1','N1'),('Q1','N2'),('Q4','N3')]:
        add_intention(db,qid,number)
    add_bdm(db,401,'N1')
    add_bdm(db,402,'N2')
    add_bdm(db,403,'N3')
    add_bdm(db,403,'N3')
    add_bdm(db,404,'N3')
    add_tas(db,501,'A1',parent=401)
    add_tas(db,501,'A1',parent=401,create_flg=False)
    add_tas(db,502,'A2',parent=401)
    add_tas(db,503,'A3',parent=402)
    add_tas(db,504,'A4',parent=403)
    add_tas(db,505,'A5',parent=404)
    add_tas(db,601,'Q3','ALPP',level25_product_bp_nm=None)
    add_tas(db,-1,'INVALID')
    build(db)
    statements=parse_sql(SQL.read_text())
    assert len(statements)==11
    actual=[db.execute(RawStream()(stmt.stmt)).fetchall() for stmt in statements]
    expected=[
        [(1,)], [(1,)], [('Q1','N1',2)], [('Q1',2)],
        [(403,'MSSA',2)], [('N3','MSSA',2)],
        [(4,'Потребкредит',403,'MSSA',2)], [(401,'MSSA',2)],
        [(1,'Потребкредит',401,501,2)], [(2,'Потребкредит',2)], [('SHARED_ID',2)],
    ]
    for index,(got,wanted) in enumerate(zip(actual,expected),1):
        assert got==wanted,(index,got,wanted)
    print('PASS: exact RAW pair duplicates, multiple numbers, current BDM key violations, '
          'number ambiguity, hidden paths, valid child 1:N, repeated match and current TQS ambiguity.')


if __name__=='__main__':
    test_different_multiplicities()
    print('Synthetic diagnostics only; no bank results have been measured.')
