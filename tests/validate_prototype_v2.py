"""Prototype v2: original KN/KK TQS chain and a separate ready-TQS auto branch.

DuckDB adapters preserve PostgreSQL SIMILAR TO and NOT LIKE ANY semantics;
storage/distribution syntax is removed only for offline execution. Production
SQL is independently parsed with pglast. No bank or Greenplum connection is used.
"""
from pathlib import Path
import re
from pglast import parse_sql
import validate_combined as old

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'sql/build_internet_funnel_v2.sql'
S=old.S
FINAL=f'{S}.prt_if2_tech_internet_funnel'
MACROS=old.TEST_MACROS | {
    'p_db_tqs':S,'p_db_tas':S,
    'P_UZ_SRC':"'MSSA'",'P_KN_SRC':"'MSCL'",'P_KK_SRC':"'CCPP_CRCA', 'CCPP_BATR'",'P_AUTO_SRC':"'ALPP'",
}
FINAL_FIELDS='questionnaire_rk questionnaire_dttm quest_verification_flg parent_application_rk parent_application_dt parent_open_flg parent_prescoring_flg parent_at_work_flg parent_approved_flg application_rk application_dt deal_issue_date create_flg at_work_flg final_approved_flg agr_signed_flg level25_product_bp_nm level35_product_bp_nm processed_dttm'.split()

def pg_sql(overrides=None):
    values=MACROS|(overrides or {})
    sql=re.sub(r'&([A-Za-z_][A-Za-z0-9_]*)',lambda m:values[m[1]],SCRIPT.read_text())
    return re.sub(r'\bdistributed\s+randomly\s*;', ';',sql,flags=re.I)

def execution_sql(overrides=None):
    sql=re.sub(r'with\s*\(APPENDONLY\s*=\s*true,\s*ORIENTATION\s*=\s*column,\s*COMPRESSTYPE\s*=\s*zstd,\s*COMPRESSLEVEL\s*=\s*5\)','',pg_sql(overrides),flags=re.I)
    # PostgreSQL LIKE ANY over an array is existential, including NOT LIKE ANY.
    sql=re.sub(r"coalesce\(upper\(r.first_nm\), '#'\) not like any \(array\[(.*?)\]\)",
               r"exists (select 1 from unnest(array[\1]) patterns(pattern) where coalesce(upper(r.first_nm), '#') not like pattern)",sql,flags=re.S)
    # This source SIMILAR TO pattern uses SQL '%' for an arbitrary suffix.
    sql=re.sub(r"similar to '([^']*)'",lambda m:"~ '"+m[1].replace('%','.*')+"'",sql)
    return sql

def db_new():
    db=old.make_db()
    db.execute(f'''create table {S}.tech_questionnaire_status (
        questionnaire_id text,questionnaire_rk bigint,questionnaire_dttm timestamp,
        utmcn_info text,utmcmd_info text,utmcsr_info text,utmctr_info text,utmcct_info text,
        status_cd text,scoring_status_nm text,prescoring_status_nm text,product_type_cd text,
        status_name text,program_type text,src_cd text,level25_product_bp_nm text,
        effective_from_dttm timestamp,effective_to_dttm timestamp,processed_dttm timestamp)''')
    return db

def mapped_raw(db,qid,rk,code='KN',status='DRAFT',num=None,**kw):
    old.add_raw(db,qid,code,status,num,**kw)
    db.execute("insert into dm_pik_fd_cdmr.tech_questionnaire_x_customer values (?,?,'2999-12-31')",[qid,rk])

def auto_status(db,qid,rk,status,product='Автокредит',end='2999-12-31',**kw):
    record=dict(questionnaire_id=qid,questionnaire_rk=rk,questionnaire_dttm='2025-01-01 00:00:00',
                status_cd=status,level25_product_bp_nm=product,src_cd='SHARED_SOURCE',
                effective_from_dttm='2025-01-01 00:00:00',effective_to_dttm=end)
    record.update(kw)
    db.execute(f"insert into {S}.tech_questionnaire_status ({', '.join(record)}) values ({', '.join('?' for _ in record)})",list(record.values()))

def rows(db,sql):return db.execute(sql).fetchall()

def test_two_sources_and_links():
    db=db_new()
    mapped_raw(db,'KN_DIRECT',101,status='DRAFT',num='KN_NEW')
    mapped_raw(db,'KN_DIRECT',101,status='0',num='KN_OLD',createtime_dttm='2025-01-10 00:00:00')
    mapped_raw(db,'KN_DIRECT',101,status='DRAFT',num='LOSING_NUM',createtime_dttm='2025-01-05 00:00:00')
    mapped_raw(db,'CC_UZ_LONG',102,'CreditCard','COURIER','UZ_NUM')
    mapped_raw(db,'KN_NO_LINK',103,status='SCORING',num='NO_BDM')
    mapped_raw(db,'KN_NO_LINK',103,status='0',num='ALSO_NO_BDM')
    mapped_raw(db,'CC_NO_CHILD',104,'CreditCard','DONE','UZ_ONLY_NUM')
    # This auto record exists in RAW only and must never enter the new auto branch.
    mapped_raw(db,'AUTO_RAW_ONLY',190,'AutoLoan','APPROVED')
    # A credit record in ready TQS must not enter the copied RAW KN/KK branch.
    auto_status(db,'CREDIT_TQS_ONLY',191,'DONE',product='Кредитные карты')
    auto_status(db,'AUTO_READY',201,'VERIFICATION',end='2025-02-01')
    auto_status(db,'AUTO_READY',201,'DRAFT',effective_from_dttm='2025-02-01 00:00:00')
    auto_status(db,'AUTO_QUESTION_ONLY',202,'COURIER')  # KK status is false for auto.
    db.executemany("insert into bdm.application values (?, ?, ?, '2999-12-31', '2025-01-01')",[
        (301,'KN_OLD','MSCL'),(301,'KN_NEW','MSCL'),(401,'KN_NEW','MSSA'),
        (402,'UZ_NUM','MSSA'),(403,'UZ_ONLY_NUM','MSSA')])
    old.add_tas(db,301,'KN_APP','MSCL',401,level25_product_bp_nm='Потребкредит')
    old.add_tas(db,301,'KN_APP','MSCL',401,level25_product_bp_nm='Потребкредит')
    old.add_tas(db,302,'CC_APP1','CCPP_CRCA',402,level25_product_bp_nm='Кредитные карты')
    old.add_tas(db,303,'CC_APP2','CCPP_BATR',402,level25_product_bp_nm='Кредитные карты')
    old.add_tas(db,-1,None,None,403,level25_product_bp_nm='Универсальная заявка')
    old.add_tas(db,304,'KN_APP_ONLY','MSCL',-1,level25_product_bp_nm='Потребкредит')
    old.add_tas(db,501,'AUTO_READY','ALPP',-1,level25_product_bp_nm='Автокредит')
    old.add_tas(db,502,'AUTO_APP_ONLY','ALPP',-1,level25_product_bp_nm='Автокредит')
    raw_before=rows(db,f'select count(*) from {old.RAW}')
    # Old results are sentinels: v2 must not drop or write them.
    db.execute(f'create table {S}.prt_tqs_questionnaire (sentinel integer); insert into {S}.prt_tqs_questionnaire values (777)')
    for _ in range(2):
        db.execute(execution_sql())
        assert rows(db,f'select questionnaire_rk,application_rk from {FINAL} order by questionnaire_rk nulls last,application_rk nulls last')==[
            (101,301),(102,302),(102,303),(103,None),(104,None),(201,501),(202,None),(None,304),(None,502)]
        assert rows(db,f'select questionnaire_rk,quest_verification_flg from {FINAL} where questionnaire_rk is not null order by questionnaire_rk')==[
            (101,True),(102,True),(102,True),(103,True),(104,True),(201,True),(202,False)]
        assert rows(db,f'select count(*) from {FINAL} where questionnaire_rk=103')==[(1,)]
        assert rows(db,f'select count(*) from {S}.prt_if2_kn_kk_matches where q_questionnaire_rk=101')==[(1,)]
        assert rows(db,f"select application_num from {S}.prt_if2_tqs_questionnaire where questionnaire_id='KN_DIRECT' and status='DRAFT'")==[('KN_NEW',)]
        assert rows(db,f'select count(*) from {FINAL} where questionnaire_rk in (190,191)')==[(0,)]
        assert rows(db,f'select count(*) from {FINAL} where level25_product_bp_nm is distinct from level35_product_bp_nm')==[(0,)]
    assert rows(db,f'select count(*) from {old.RAW}')==raw_before
    assert rows(db,f'select sentinel from {S}.prt_tqs_questionnaire')==[(777,)]
    for mode,matched in [('DIRECT',1),('UZ',4)]:
        db.execute(execution_sql({'p_kn_kk_link_mode':repr(mode)}))
        assert rows(db,f'select count(*) from {S}.prt_if2_kn_kk_matches')==[(matched,)]
    assert [r[0] for r in rows(db,f'describe {FINAL}')]==FINAL_FIELDS
    assert [r[1] for r in rows(db,f'describe {FINAL}')]==['BIGINT','TIMESTAMP','BOOLEAN','BIGINT','DATE',
        'BOOLEAN','BOOLEAN','BOOLEAN','BOOLEAN','BIGINT','DATE','DATE','BOOLEAN','BOOLEAN','BOOLEAN','BOOLEAN','VARCHAR','VARCHAR','TIMESTAMP_S']
    print('PASS: separate RAW KN/KK and ready-TQS auto, original priorities, history numbers, UZ, N:M, unmatched sides, modes, 19 fields and isolated outputs.')

def test_verification_lists():
    db=db_new()
    for i,(code,product,sts) in enumerate([
        ('KN','Потребкредит',['0','10.0','одобрено','CHECK_LIST_EMPTY','CHECK_LIST_ANTIFRAUD_OR_PRODUCT']),
        ('CreditCard','Кредитные карты',['DONE','COURIER']),
        ('AutoLoan','Автокредит',['APPROVE_RKK','APPROVED','PRE_APPROVED','APPROVE_CALL2','APPROVE_CALL3','ORDER_CREATED','VERIFICATION','DRIVER_CARD_ISSUE','DRIVER_CARD_ISSUE_UPLOADED','DOSSIER_UPLOADED','DEAL_VER','CREDIT_ISSUED','PRODUCT_BASKET_SIGNED'])]):
        for n,status in enumerate(sts):
            qid=f'PRODUCT_{i}_STATUS_{n}';rk=1000+100*i+n
            if code=='AutoLoan':
                auto_status(db,qid,rk,status,end='2025-02-01')
                auto_status(db,qid,rk,'DRAFT',effective_from_dttm='2025-02-01')
            else:
                mapped_raw(db,qid,rk,code,status)
                mapped_raw(db,qid,rk,code,'DRAFT')
    mapped_raw(db,'NEGATIVE_KN',2001,'KN','DONE')
    mapped_raw(db,'NEGATIVE_KK',2002,'CreditCard','0')
    auto_status(db,'NEGATIVE_AUTO',2003,'COURIER')
    db.execute(execution_sql())
    assert rows(db,f'select count(*) from {FINAL} where quest_verification_flg')==[(20,)]
    assert rows(db,f'select count(*) from {FINAL} where not quest_verification_flg')==[(3,)]
    print('PASS: all 20 highlighted statuses from history, product-specific negative cases; auto current DRAFT does not reset flag.')

def test_structure_and_original_filters():
    source=SCRIPT.read_text()
    targets=re.findall(r'^create table &db_sbx\.(\w+)$',source,re.M)
    assert len(targets)==15 and all(n.startswith('prt_if2_') for n in targets)
    assert source.count('from &p_db_rawd.v_sn_all_mart_dapp_prod_dm_dsa_cd_questionnaire_x_intention')==1
    assert source.count('from &p_db_tqs.tech_questionnaire_status')==1
    assert not re.search(r'select\s+(?:\w+\.)?\*',source,re.I)
    assert not re.search(r'prt_if2_\w*(?:raw|parsed|checked|ranked)\b',source)
    assert "not like any (array[&p_test_first_nm_like_text_list])" in source
    db=db_new()
    mapped_raw(db,'TEST_CLIENT',2001,first_nm='ЛИД')
    mapped_raw(db,'123456',2002,'CreditCard','DONE')
    mapped_raw(db,'OLD_COHORT',2003,questionnaire_dt='2023-01-01 00:00:00')
    db.execute(execution_sql())
    assert rows(db,f'select count(*) from {FINAL}')==[(0,)]
    # Confirm the test adapter preserves the screenshot's NOT LIKE ANY behavior.
    db=db_new();mapped_raw(db,'ORIGINAL_ANY',2100,first_nm='ФИО_ТЕСТ_ФИО')
    db.execute(execution_sql())
    assert rows(db,f'select count(*) from {FINAL}')==[(1,)]
    db=db_new();db.execute(execution_sql())
    assert rows(db,f'select count(*) from {FINAL}')==[(0,)]
    print('PASS: 15 sequential steps, original WHERE semantics, no added validation tables, no SELECT *, empty input and no old-output writes.')

def test_step_instructions():
    source=SCRIPT.read_text()
    doc=(ROOT/'docs/prototype_v2_steps.txt').read_text()
    sql_lines=source.splitlines()
    blocks=re.findall(r'^-- Шаг (\d+\.\d+)\. ([^\n]+)\n-- Откуда: ([^\n]+)\n-- Зачем: ([^\n]+)\n-- Копирование: ([^\n]+)\ndrop table',source,re.M)
    assert len(blocks)==15
    documented=re.findall(r'^ШАГ (\d+\.\d+) — [^\n]+\nSQL V2: строки (\d+)–(\d+)\.',doc,re.M)
    assert len(documented)==16  # 15 DROP/CREATE steps plus the read-only report 3.2.
    assert {num for num,_,_ in documented}=={block[0] for block in blocks}|{'3.2'}
    for num,start,end in documented:
        assert sql_lines[int(start)-1].startswith(f'-- Шаг {num}. ')
        assert int(end)>=int(start)
    for marker in ['1.1-A','1.1-B']:
        assert marker in source and marker in doc
    assert 'Можно полностью скопировать из tech_questionnaire_status' in doc
    print('PASS: all 15 table steps explain origin/purpose/copying; TXT step ranges match the actual SQL lines.')

if __name__=='__main__':
    print('PARSED PostgreSQL statements:',len(parse_sql(pg_sql())))
    test_two_sources_and_links()
    test_verification_lists()
    test_structure_and_original_filters()
    test_step_instructions()
    print('Offline synthetic tests only; Greenplum and bank data remain unverified.')
