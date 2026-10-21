"""Reverse diagnostics: classify unlinked TAS pairs, not forward questionnaire losses."""
from pathlib import Path
from collections import Counter
import re
from pglast import parse_sql
import validate_funnel_diagnostics as d
import validate_prototype_v2 as v

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'sql/diagnose_unlinked_kn_kk.sql'
S = v.S
VALUES = d.VALUES | {'p_kn_tas_table':f'{S}.prt_if2_kn_kk_tas', 'p_kn_fin_table':f'{S}.prt_if2_kn_kk_fin'}


def sql():
    return v.execution_sql(VALUES, source=SCRIPT.read_text())


def fixture():
    db = d.fixture()
    # Independent reverse cases: TAS exists, the forward side does not necessarily exist.
    cases = [
        (910,'NO_BDM'),(911,'OLD_VERSION'),(912,'OLD_BDM_DATE'),(913,'NULL_BDM_NUMBER'),
        (914,'BEFORE_RK'),(915,'RAW_ONLY'),(916,'NO_RAW'),(917,'WRONG_PRODUCT'),
        (918,'OLD_QUESTIONNAIRE'),(919,'NULL_QRK'),(920,'BRIDGE_MISSING'),
        (921,'MATCH_MISSING'),(922,'FINAL_LINK_MISSING'),(923,'FINAL_PAIR_MISSING'),
        (926,'PRE_RK_WRONG_PRODUCT'),
    ]
    for rk,name in cases:
        v.add_tas(db,rk,name,'MSCL',level25_product_bp_nm='Потребкредит')
    db.executemany('insert into bdm.application values (?,?,?,?,?)',[
        (911,'R_OLD_VER','MSCL','2025-01-01','2025-01-01'),
        (912,'R_OLD_DATE','MSCL','2999-12-31','2024-12-31'),
        (913,None,'MSCL','2999-12-31','2025-01-01'),
        (914,'N_NO_RK','MSCL','2999-12-31','2025-01-01'),
        (915,'R_RAW_ONLY','MSCL','2999-12-31','2025-01-01'),
        (916,'R_NO_RAW','MSCL','2999-12-31','2025-01-01'),
        (917,'R_WRONG_PRODUCT','MSCL','2999-12-31','2025-01-01'),
        (918,'R_OLD_Q','MSCL','2999-12-31','2025-01-01'),
        (919,'R_NULL_QRK','MSCL','2999-12-31','2025-01-01'),
        (920,'R_BRIDGE','MSCL','2999-12-31','2025-01-01'),
        (921,'R_MATCH','MSCL','2999-12-31','2025-01-01'),
        (922,'R_FINAL_LINK','MSCL','2999-12-31','2025-01-01'),
        (923,'R_FINAL_PAIR','MSCL','2999-12-31','2025-01-01'),
        (926,'R_PRE_OTHER','MSCL','2999-12-31','2025-01-01'),
    ])
    v.old.add_raw(db,'RAW_FILTERED','KN','0','R_RAW_ONLY',first_nm='ЛИД')
    v.old.add_raw(db,'PRE_RK_OTHER_PRODUCT','CreditCard','DONE','R_PRE_OTHER')
    v.mapped_raw(db,'WRONG_PRODUCT_Q',317,'CreditCard','DONE','R_WRONG_PRODUCT')
    v.mapped_raw(db,'OLD_REVERSE_Q',318,'KN','0','R_OLD_Q',questionnaire_dt='2024-11-01 00:00:00')
    for qid,rk,num in [('MISSING_BRIDGE',320,'R_BRIDGE'),('MISSING_MATCH',321,'R_MATCH'),
                       ('MISSING_FINAL_LINK',322,'R_FINAL_LINK'),('MISSING_FINAL_PAIR',323,'R_FINAL_PAIR')]:
        v.mapped_raw(db,qid,rk,'KN','0',num)
    # Broad MSSA selection includes a row unsupported by either key route.
    v.add_tas(db,-1,None,'MSSA',924,parent_src='OTHER',level25_product_bp_nm='Универсальная заявка')
    db.execute(v.execution_sql())
    # Deliberate damaged/stale intermediate outputs: diagnose rather than silently accept.
    db.execute(f'''insert into {S}.prt_if2_kn_kk_verification
        (questionnaire_id,questionnaire_rk,questionnaire_dttm,level25_product_bp_nm,application_num)
        values ('NULL_QRK',NULL,'2025-01-01','Потребкредит','R_NULL_QRK')''')
    db.execute(f'delete from {S}.prt_if2_kn_kk_bdm where bdm_application_rk=920')
    db.execute(f'delete from {S}.prt_if2_kn_kk_matches where tas_application_rk in (920,921)')
    db.execute(f'update {S}.prt_if2_kn_kk_fin set questionnaire_rk=NULL where application_rk in (920,921,922)')
    db.execute(f'delete from {S}.prt_if2_kn_kk_fin where application_rk=923')
    return db


def test_reverse():
    source = SCRIPT.read_text()
    stmts = parse_sql(v.pg_sql(VALUES,source=source))
    targets = re.findall(r'^create table &db_sbx\.(\w+)',source,re.M)
    assert targets and all(t.startswith('prt_ifr_') for t in targets)
    assert not re.search(r'select\s+(?:\w+\.)?\*',source,re.I)
    assert 'count(distinct' not in source.lower()
    db = fixture()
    names = [f'{S}.prt_if2_kn_kk_tas',f'{S}.prt_if2_kn_kk_fin',f'{S}.prt_if2_kn_kk_matches',
             f'{S}.prt_if2_kn_kk_bdm',f'{S}.prt_if2_kn_kk_verification',f'{S}.prt_if2_tqs_questionnaire_all',v.old.RAW,'bdm.application']
    before = {n:Counter(db.execute(f'select * from {n}').fetchall()) for n in names}
    for _ in range(2):
        db.execute(sql())
        reasons = dict(db.execute(f'''select application_rk,reason from {S}.prt_ifr_reasons
                                     where application_rk between 910 and 923''').fetchall())
        assert reasons == {
            910:'03_no_bdm_for_rk_and_source',911:'04_bdm_has_no_current_version',
            912:'05_bdm_date_old_or_null',913:'06_bdm_application_num_null',
            914:'07_number_present_before_rk_only',915:'09_number_absent_from_prepared_questionnaires',
            916:'09_number_absent_from_prepared_questionnaires',917:'10_questionnaire_product_mismatch',
            918:'11_questionnaire_outside_period',919:'12_questionnaire_rk_null',
            920:'13_candidate_missing_from_saved_bridge',921:'14_candidate_exists_check_join_mode_or_run',
            922:'01_saved_match_missing_from_final',923:'00_tas_pair_missing_from_final',
        },reasons
        assert db.execute(f'select reason from {S}.prt_ifr_reasons where parent_application_rk=924').fetchall()==[('02_no_supported_join_route',)]
        assert db.execute(f'select reason from {S}.prt_ifr_reasons where application_rk=926').fetchall()==[('08_number_before_rk_other_product',)]
        raw = dict(db.execute(f'select application_num,raw_found_flg from {S}.prt_ifr_raw_numbers').fetchall())
        assert raw['R_RAW_ONLY']==1 and raw['R_NO_RAW']==0 and raw['N_NO_RK']==1
        # Pair with two product labels is classified once; real zero RK is not confused with NULL.
        assert db.execute(f'select count(*) from {S}.prt_ifr_reasons where application_rk=905').fetchone()==(1,)
        assert db.execute(f'select linked_flg from {S}.prt_ifr_base where application_rk=0 and parent_application_rk is null').fetchone()==(1,)
        assert db.execute(f'select linked_flg from {S}.prt_ifr_base where application_rk is null and parent_application_rk=0').fetchone()==(0,)
        baseline=db.execute(f'select count(*),sum(linked_flg),sum(1-linked_flg) from {S}.prt_ifr_base').fetchone()
        grouped=db.execute(f'select reason,count(*) from {S}.prt_ifr_reasons group by reason').fetchall()
        assert sum(r[1] for r in grouped)==baseline[2]
        assert db.execute(f'''select count(*) from (select parent_application_rk,application_rk
               from {S}.prt_ifr_reasons group by parent_application_rk,application_rk having count(*)>1) x''').fetchone()==(0,)
        # All SELECT reports also execute independently, after their CTAS dependencies.
        d.statement_results(db,sql())
    assert before=={n:Counter(db.execute(f'select * from {n}').fetchall()) for n in names}
    print(f'PASS: {len(stmts)} parsed statements; reverse pair conservation, BDM history/date, missing numbers, pre/post RK, product/period, damaged stages, RAW existence, NULL/zero and repeatability.')


def test_empty_and_alternative_route():
    db=v.db_new();db.execute(v.execution_sql());db.execute(sql())
    assert db.execute(f'select count(*) from {S}.prt_ifr_reasons').fetchone()==(0,)
    reports=d.statement_results(db,sql())
    assert reports[('tas_pair_count','linked_pair_count','unlinked_pair_count','missing_from_final_count')]==[(0,0,0,0)]
    # A valid UZ-parent route plus an unsuccessful direct route must not be labeled no-number.
    db=v.db_new()
    v.mapped_raw(db,'PARENT_ONLY_MATCH',500,'KN','0','UZ_GOOD')
    db.executemany('insert into bdm.application values (?,?,?,?,?)',[
        (700,'UZ_GOOD','MSSA','2999-12-31','2025-01-01'),
        (701,'DIRECT_NO_QUESTION','MSCL','2999-12-31','2025-01-01')])
    v.add_tas(db,701,'CHILD','MSCL',700,level25_product_bp_nm='Потребкредит')
    db.execute(v.execution_sql({'p_kn_kk_link_mode':"'DIRECT'"}))
    db.execute(sql())
    assert db.execute(f'select reason from {S}.prt_ifr_reasons').fetchall()==[('14_candidate_exists_check_join_mode_or_run',)]
    print('PASS: empty cohorts; one viable alternative route overrides failures of another, while disabled UZ remains an explicit candidate.')


if __name__=='__main__':
    test_reverse()
    test_empty_and_alternative_route()
    print('Offline synthetic checks only; real Greenplum volume and bank data are not available here.')
