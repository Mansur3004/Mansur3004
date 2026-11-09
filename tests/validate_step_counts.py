"""Exercise every diagnosis, including intentionally broken intermediate steps."""
from pathlib import Path
import re
from pglast import parse_sql
from pglast.stream import RawStream
from funnel_fixtures import S, CDMR, add_tqs, add_bdm, add_tas
from validate_prototype_v4 import execution_sql
from validate_prototype_v5 import db_with_raw, intention, SCRIPT as V5, VALUES

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'sql/proverka_steps_kn_kk.sql'
KN='Потребкредит'; KK='Кредитные карты'


def fixture(corrupt=True):
    db=db_with_raw()
    for i in range(1,21):
        add_tqs(db,f'Q{i}',i)
    add_tqs(db,'OLD',21,qdate='2024-01-01')
    add_tqs(db,'INVALID',-1)
    add_tqs(db,'KK_ISSUED',101,product=KK)
    add_tqs(db,'KK_NO_RAW',102,product=KK)
    intention(db,'Q2',None)
    for i in range(3,21):
        intention(db,f'Q{i}',f'N{i}',createtime_dttm='2025-02-01')
    intention(db,'Q12','OLD_CHOICE',createtime_dttm='2025-01-01')
    intention(db,'KK_ISSUED','KK_NUM')
    add_bdm(db,404,'N4',end='2024-12-31')
    add_bdm(db,-1,'N5')
    for i in range(6,21):
        add_bdm(db,400+i,f'N{i}')
    add_tas(db,406,'OWN_KEY_ONLY',parent=900)
    add_tas(db,507,'WRONG_SOURCE',parent=407,parent_src='OTHER')
    add_tas(db,508,'WRONG_PRODUCT',parent=408,level25_product_bp_nm='Автокредит')
    add_tas(db,509,'OLD_TAS',parent=409,application_dt='2024-01-01',parent_application_dt='2024-01-01')
    add_tas(db,-1,None,parent=410)
    add_tas(db,511,'NO_ISSUE',parent=411)
    for i in range(12,20):
        add_tas(db,500+i,f'APP{i}',parent=400+i,deal_issue_date='2025-03-01')
    add_tas(db,1512,'NULL_PRODUCT',parent=412,level25_product_bp_nm=None,deal_issue_date='2025-03-01')
    add_tas(db,2512,'DIFFERENT_PRODUCT',parent=412,level25_product_bp_nm=KK,deal_issue_date='2025-03-01')
    add_bdm(db,1101,'KK_NUM')
    add_tas(db,1201,'KK_APP',parent=1101,level25_product_bp_nm=KK,deal_issue_date='2025-03-01')
    add_tas(db,601,'NO_PARENT',parent=-1)
    add_bdm(db,1603,'NO_RAW_NUMBER')
    add_tas(db,603,'NO_RAW',parent=1603)
    add_bdm(db,1604,'OUTSIDE_NUM')
    intention(db,'NOT_IN_TQS','OUTSIDE_NUM')
    add_tas(db,604,'NO_SELECTED_Q',parent=1604)
    add_bdm(db,1605,'OLD_CHOICE')
    add_tas(db,605,'NUMBER_NOT_CHOSEN',parent=1605)
    add_bdm(db,1607,'HISTORICAL_PARENT',end='2024-12-31')
    add_tas(db,607,'OLD_PARENT',parent=1607)
    add_tas(db,-1,'INVALID_TAS',parent=-1)
    # Corrupt selected stages before downstream steps run, to prove gap detection.
    hooks={
      'verification':"delete from {s}verification where questionnaire_rk=20",
      'questionnaire_numbers':"delete from {s}questionnaire_numbers where questionnaire_id='Q13'",
      'kn_kk_bdm':"delete from {s}kn_kk_bdm where questionnaire_rk=14",
      'tas':"delete from {s}tas where parent_application_rk=415",
      'matches':"delete from {s}matches where questionnaire_rk=16",
      'questionnaire_funnel':"delete from {s}questionnaire_funnel where questionnaire_rk=17",
      'remaining_tas':"delete from {s}remaining_tas where parent_application_rk=1603",
      'tech_internet_funnel':"delete from {s}tech_internet_funnel where questionnaire_rk=18",
    }
    stmts=parse_sql(execution_sql(V5.read_text(),VALUES))
    for statement in stmts:
        sql=RawStream()(statement.stmt)
        db.execute(sql)
        for suffix,hook in hooks.items():
            if corrupt and sql.startswith('CREATE TABLE '+S+'.man_prt_tif_v5_'+suffix+' '):
                db.execute(hook.format(s=S+'.man_prt_tif_v5_'))
    return db


def reports(db,product):
    sql=re.sub(r'&([A-Za-z_][A-Za-z0-9_]*)',lambda m:(VALUES|{'p_product':"'"+product+"'"})[m[1]],SCRIPT.read_text())
    stmts=parse_sql(sql)
    assert len(stmts)==54
    assert all(x.stmt.__class__.__name__=='SelectStmt' for x in stmts)
    out={}
    for statement in stmts:
        result=db.execute(RawStream()(statement.stmt)).fetchall()
        assert len(result)==1 and len(result[0])==3,result
        key,prod,value=result[0]
        assert prod==product
        out[int(key)]=value
    return out


def test_classification_and_stage_gaps():
    db=fixture()
    k=reports(db,KN)
    expected={1:21,2:20,3:1,4:1,5:21,6:1,7:20,8:19,9:1,
              10:1,11:1,12:1,13:16,14:1,15:1,16:1,17:1,18:12,
              19:6,20:1,21:1,22:1,23:1,24:1,25:1,26:6,
              27:1,28:1,29:2,30:2,31:1,32:1,33:4,
              34:1,36:1,39:1,42:1,44:1,45:1,46:1,47:2,48:1,49:1,
              50:1,51:1,53:2}
    for key,wanted in expected.items():
        assert k[key]==wanted,(key,k[key],wanted)
    assert k[8]==sum(k[i] for i in [10,11,12,13])
    assert k[13]==sum(k[i] for i in [14,15,16,17,18])
    assert k[18]==k[19]+k[26]
    assert k[19]==sum(k[i] for i in range(20,26))
    assert k[26]==k[31]+k[32]+k[33]
    assert k[38]==k[40]+k[41]
    assert k[41]==sum(k[i] for i in range(42,50))
    assert k[38]==k[53]+k[54]
    cc=reports(db,KK)
    assert cc[8]==2 and cc[10]==1
    assert cc[13]==cc[18]==cc[26]==cc[33]==1
    assert cc[27]==cc[28]==cc[29]==cc[30]==cc[39]==cc[50]==cc[51]==cc[53]==0
    # A KN questionnaire linked to a KK TAS row does not disappear in either dimension.
    assert cc[40]==2
    print('PASS: all 54 SELECTs; every questionnaire cause, reverse TAS path partition, period/invalid-key filters, corrupted stages, final loss and source-product consistency.')


def test_healthy_pipeline_and_empty_product():
    db=fixture(corrupt=False)
    result=reports(db,KN)
    for check in [3,9,12,17,24,25,27,28,29,30,39,48,49,50,51,53]:
        assert result[check]==0,(check,result[check])
    assert [result[x] for x in [8,13,18,26,33]]==[20,18,15,10,8]
    assert all(value==0 for value in reports(db,'НЕСУЩЕСТВУЮЩИЙ ПРОДУКТ').values())
    print('PASS: healthy V5 keeps all entities/links; missing-product queries return explicit zero counts.')


if __name__=='__main__':
    test_classification_and_stage_gaps()
    test_healthy_pipeline_and_empty_product()
    print('Synthetic DuckDB + PostgreSQL parsing only; no bank/Greenplum results.')
