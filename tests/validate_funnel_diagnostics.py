"""Offline semantic checks for diagnostics; no connection to bank sources."""
from pathlib import Path
from collections import Counter
import re
from pglast import parse_sql
import validate_prototype_v2 as v2

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'sql/diagnose_internet_funnel_coverage.sql'
S = v2.S
VALUES = {
    'p_kn_numbers_table': f'{S}.prt_if2_kn_kk_verification',
    'p_kn_bdm_table': f'{S}.prt_if2_kn_kk_bdm',
    'p_kn_matches_table': f'{S}.prt_if2_kn_kk_matches',
    'p_auto_q_table': f'{S}.prt_if2_auto_verification',
    'p_tqs_all_table': f'{S}.prt_if2_tqs_questionnaire_all',
}


def prepared(overrides=None):
    return v2.execution_sql(VALUES | (overrides or {}), source=SCRIPT.read_text())


def statement_results(db, sql):
    """Run each independent report, retaining its column names and rows."""
    statements = parse_sql(sql)
    reports = {}
    for statement in statements:
        if statement.stmt.__class__.__name__ != 'SelectStmt':
            continue
        # pglast exposes character positions in its Python parse_sql result.
        start = statement.stmt_location
        size = statement.stmt_len
        fragment = sql[start:start + size if size else None]
        cursor = db.execute(fragment)
        reports[tuple(c[0] for c in cursor.description)] = cursor.fetchall()
    return reports


def fixture():
    db = v2.db_new()
    # All four questionnaire-level loss stages, plus every BDM rejection reason.
    specs = [
        ('DIRECT', 101, 'N_DIRECT'), ('UZ', 102, 'N_UZ'),
        ('NO_NUMBER', 103, None), ('NO_BDM', 104, 'N_ABSENT'),
        ('NO_TAS', 105, 'N_NO_TAS'), ('EXPIRED', 106, 'N_EXPIRED'),
        ('WRONG_SRC', 107, 'N_WRONG_SRC'), ('BAD_RK', 108, 'N_BAD_RK'),
        ('OLD_DATE', 109, 'N_OLD_DATE'), ('NULL_DATE', 110, 'N_NULL_DATE'),
        ('SPACES', 111, ' N_SPACES '), ('BLANK', 112, '   '),
        ('BOTH', 113, 'N_BOTH_DIRECT'), ('ZERO', 114, 'N_ZERO'),
    ]
    for qid, rk, number in specs:
        v2.mapped_raw(db, 'KN_' + qid, rk, status='SCORING', num=number)
    # Same questionnaire has another valid historical number; one success suffices.
    v2.old.add_raw(db, 'KN_BOTH', 'KN', '0', 'N_BOTH_UZ')
    # Cleaned RAW without an RK must be counted before the copied INNER JOIN.
    v2.old.add_raw(db, 'KN_NO_RK', 'KN', '0', 'N_NO_RK')
    db.executemany('insert into bdm.application values (?,?,?,?,?)', [
        (301, 'N_DIRECT', 'MSCL', '2999-12-31', '2025-01-01'),
        (402, 'N_UZ', 'MSSA', '2999-12-31', '2025-01-01'),
        (305, 'N_NO_TAS', 'MSCL', '2999-12-31', '2025-01-01'),
        (306, 'N_EXPIRED', 'MSCL', '2025-02-01', '2025-01-01'),
        (307, 'N_WRONG_SRC', 'OTHER', '2999-12-31', '2025-01-01'),
        (-1, 'N_BAD_RK', 'MSCL', '2999-12-31', '2025-01-01'),
        (309, 'N_OLD_DATE', 'MSCL', '2999-12-31', '2024-12-31'),
        (310, 'N_NULL_DATE', 'MSCL', '2999-12-31', None),
        (311, 'N_SPACES', 'MSCL', '2999-12-31', '2025-01-01'),
        (313, 'N_BOTH_DIRECT', 'MSCL', '2999-12-31', '2025-01-01'),
        (413, 'N_BOTH_UZ', 'MSSA', '2999-12-31', '2025-01-01'),
        (0, 'N_ZERO', 'MSCL', '2999-12-31', '2025-01-01'),
    ])
    v2.add_tas(db, 301, 'DIRECT_APP', 'MSCL', level25_product_bp_nm='Потребкредит')
    v2.add_tas(db, -1, None, None, 402, level25_product_bp_nm='Универсальная заявка')
    v2.add_tas(db, 313, 'BOTH_APP', 'MSCL', 413, level25_product_bp_nm='Потребкредит')
    # TAS includes non-target products, unknown product, unlinked target and target from another source.
    v2.add_tas(db, 901, 'NON_TARGET', 'MSCL', level25_product_bp_nm='Депозиты')
    v2.add_tas(db, 902, 'NULL_PRODUCT', 'MSCL', level25_product_bp_nm=None)
    v2.add_tas(db, 903, 'NO_QUESTION', 'MSCL', level25_product_bp_nm='Потребкредит')
    v2.add_tas(db, 904, 'OUTSIDE_SOURCE', 'OTHER', level25_product_bp_nm='Потребкредит')
    # One TAS pair has two product labels: sums by product cannot be the denominator.
    v2.add_tas(db, 905, 'MULTI_LABEL', 'MSCL', level25_product_bp_nm='Потребкредит')
    v2.add_tas(db, 905, 'MULTI_LABEL', 'MSCL', level25_product_bp_nm='Депозиты')
    # Zero must remain distinct from NULL in the hashable diagnostic joins.
    v2.add_tas(db, 0, 'ZERO_DIRECT', 'MSCL', level25_product_bp_nm='Потребкредит')
    v2.add_tas(db, -1, None, None, 0, level25_product_bp_nm='Универсальная заявка')
    v2.auto_status(db, 'AUTO_OK', 201, 'VERIFICATION')
    v2.auto_status(db, 'AUTO_OLD', 202, 'VERIFICATION')
    v2.auto_status(db, 'AUTO_NO_ID', 203, 'VERIFICATION')
    v2.auto_status(db, 'AUTO_BAD_PRODUCT', 204, 'VERIFICATION')
    v2.add_tas(db, 501, 'AUTO_OK', 'ALPP', level25_product_bp_nm='Автокредит')
    v2.add_tas(db, 502, 'AUTO_OLD', 'ALPP', application_dt='2024-12-01', level25_product_bp_nm='Автокредит')
    v2.add_tas(db, 504, 'AUTO_BAD_PRODUCT', 'ALPP', level25_product_bp_nm='Кредитные карты')
    db.execute(v2.execution_sql())
    return db


def test_diagnostics():
    source = SCRIPT.read_text()
    statements = parse_sql(v2.pg_sql(VALUES, source=source))
    assert not re.search(r'select\s+(?:\w+\.)?\*', source, re.I)
    targets = re.findall(r'^create table &db_sbx\.(\w+)', source, re.M)
    assert targets and all(n.startswith('prt_ifd_') for n in targets)
    assert len(targets) == source.count('drop table if exists')
    db = fixture()
    original = db.execute(f'select {", ".join(v2.FINAL_FIELDS)} from {v2.FINAL}').fetchall()
    for _ in range(2):
        db.execute(prepared())
        stages = dict(db.execute(f'select questionnaire_rk,lost_at from {S}.prt_ifd_kn_stage').fetchall())
        assert stages[101] == stages[102] == stages[113] == '04_matched_tas'
        assert stages[103] == '01_no_application_num'
        assert stages[104] == '02_no_bdm_under_prototype_filters'
        assert stages[105] == '03_bdm_found_no_tas_match'
        assert len(stages) == 14
        assert db.execute(f'select linked_flg from {S}.prt_ifd_tas_product where parent_application_rk=0 and application_rk is null').fetchall() == [(0,)]
        assert db.execute(f'select linked_flg from {S}.prt_ifd_tas_product where parent_application_rk is null and application_rk=0').fetchall() == [(1,)]
        assert db.execute(f'select has_rk_flg from {S}.prt_ifd_pre_rk where questionnaire_id=\'KN_NO_RK\'').fetchall() == [(0,)]
        assert db.execute(f'select direct_flg,uz_flg from {S}.prt_ifd_route_q where questionnaire_rk=113').fetchall() == [(1,1)]
        assert db.execute(f'select any_target_product_flg from {S}.prt_ifd_route_q where questionnaire_rk=102').fetchall() == [(0,)]
        assert db.execute(f'select level25_product_bp_nm from {S}.prt_ifd_q_product where questionnaire_rk=102').fetchall() == [('Потребкредит',)]
        assert db.execute(f'select level25_product_bp_nm from {v2.FINAL} where questionnaire_rk=102').fetchall() == [('Универсальная заявка',)]
        flags = dict((row[0], row[1:]) for row in db.execute(f'''select questionnaire_rk,exact_id_found_flg,
            exact_id_in_period_flg,exact_id_auto_product_flg from {S}.prt_ifd_auto_ids''').fetchall())
        assert flags == {201:(1,1,1),202:(1,0,0),203:(0,0,0),204:(1,1,0)}
        reasons = dict((row[0], row[1:]) for row in db.execute(f'''select application_num,any_bdm_flg,
            current_bdm_flg,current_source_flg,current_source_key_flg,all_filters_flg from {S}.prt_ifd_bdm_reasons''').fetchall())
        assert reasons['N_ABSENT'] == (0,0,0,0,0)
        assert reasons['N_EXPIRED'] == (1,0,0,0,0)
        assert reasons['N_WRONG_SRC'] == (1,1,0,0,0)
        assert reasons['N_BAD_RK'] == (1,1,1,0,0)
        assert reasons['N_OLD_DATE'] == reasons['N_NULL_DATE'] == (1,1,1,1,0)
        assert reasons['N_DIRECT'] == (1,1,1,1,1)
        assert reasons[' N_SPACES '] == (0,0,0,0,0)
        reports = statement_results(db, prepared())
        scopes = dict((r[0], r[1:]) for r in reports[('scope','application_count','linked_application_count','application_link_pct')])
        assert scopes['01_final_original'] == scopes['02_tas_prototype_sources']
        assert scopes['03_tas_three_products'][0] < scopes['01_final_original'][0]
        # Product restriction removes a real linked UZ as well as unlinked non-targets.
        assert scopes['03_tas_three_products'][1] == scopes['01_final_original'][1] - 1
        issues = dict(reports[('issue','pair_count')])
        assert issues == {'tas_pair_absent_from_final':0,'final_pair_absent_from_current_tas_cohort':0,
                          'tas_pair_with_multiple_product_labels':1,'final_row_without_any_rk':0}
    assert Counter(original) == Counter(db.execute(f'select {", ".join(v2.FINAL_FIELDS)} from {v2.FINAL}').fetchall())
    # Detect a source-cohort pair lost from the final table rather than hiding it in its denominator.
    db.execute(f'delete from {v2.FINAL} where application_rk=903')
    db.execute(prepared())
    reports = statement_results(db, prepared())
    assert dict(reports[('issue','pair_count')])['tas_pair_absent_from_final'] == 1
    print(f'PASS: {len(statements)} parsed statements; exact coverage, strict product loss, NULL pair, product conflicts, all BDM rejections, route overlap, auto dates, source conservation and repeatability.')


def test_empty_and_alias():
    db = v2.db_new()
    db.execute(v2.execution_sql())
    db.execute(prepared())
    reports = statement_results(db, prepared())
    assert reports[('questionnaire_count','linked_questionnaire_count','questionnaire_link_pct','application_count','linked_application_count','application_link_pct')] == [(0,0,None,0,0,None)]
    assert all(r[1:] == (0,0,None) for r in reports[('scope','application_count','linked_application_count','application_link_pct')])
    db.execute(f'create table {S}.custom_final as select {", ".join(v2.FINAL_FIELDS)} from {v2.FINAL}')
    db.execute(f'''insert into {S}.custom_final (questionnaire_rk,parent_application_rk,level25_product_bp_nm)
                   values (99,100,'Потребкредит')''')
    db.execute(prepared({'p_funnel_table':f'{S}.custom_final'}))
    assert db.execute(f'select linked_flg from {S}.prt_ifd_final_q').fetchall() == [(1,)]
    assert db.execute(f'select count(*) from {v2.FINAL}').fetchall() == [(0,)]
    print('PASS: empty cohorts return NULL percentages; custom final macro works without changing prototype results.')


if __name__ == '__main__':
    test_diagnostics()
    test_empty_and_alias()
    print('Synthetic PostgreSQL/DuckDB validation only; no bank/Greenplum execution.')
