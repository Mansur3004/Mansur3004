"""Offline checks, not a replacement for execution in the bank's Greenplum.

Install duckdb and pglast in an isolated directory or virtual environment.
Run: python tests/validate_diagnostics.py
Only the Greenplum distribution clauses are removed for the offline engine.
No real business data or credentials are used.
"""

from pathlib import Path
import re

import duckdb
from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]


def portable_sql(path):
    sql = path.read_text()
    return re.sub(r"\bdistributed\s+randomly\s*;", ";", sql, flags=re.I)


def run_file(db, name):
    db.execute(portable_sql(ROOT / "sql" / name))


def rows(db, sql):
    return db.execute(sql).fetchall()


def make_db():
    db = duckdb.connect()
    db.execute("create schema sbx_pre_orb_fd; create schema bdm")
    # DuckDB names PostgreSQL's single-argument BTRIM function TRIM.
    db.execute("create macro btrim(value) as trim(value)")
    db.execute("""
        create table sbx_pre_orb_fd.man_prt_tqs_questionnaire (
            questionnaire_id text, application_num text, src_cd text,
            product_type_cd text
        );
        create table bdm.application (
            application_rk bigint, application_num text, src_cd text,
            effective_to_date date, application_begin_date date
        );
        create table sbx_pre_orb_fd.tech_questionnaire_status (
            questionnaire_rk bigint, questionnaire_id text, src_cd text,
            questionnaire_dttm timestamp, effective_from_dttm timestamp,
            effective_to_dttm timestamp, product_type_cd text,
            level25_product_bp_nm text
        );
        create table sbx_pre_orb_fd.tech_application_status (
            parent_application_rk bigint, parent_src_cd text,
            application_rk bigint, application_id text, src_cd text,
            application_dt date, processed_dttm timestamp
        )
    """)
    return db


def populate(db):
    q_rows = [
        ("q1", "N1", "1376.2.e", "KN"),
        ("q1", "N1", "1376.2.e", "KN"),  # Another source status.
        ("q2", "N2", "1376.2.n", "KN"),
        ("q3", None, "1376.2.n", "KN"),  # Must stay in denominator.
        ("q4", "N2", "1376.2.i", "KN"),
        ("q4", "N4", "1376.2.i", "KN"),  # Ambiguous number mapping.
        ("q1", "NO_MATCH", "1376.2.n", "KN"),  # Same ID, other source.
        ("c1", "C1", "1383.1.n", "CreditCard"),
        ("c2", "C2", "1383.1.n", "CreditCard"),
        ("c3", "", "1383.1.n", "CreditCard"),
        ("AUTO1", None, "1383.1.n", "CreditCard"),  # ID source collision.
        ("AUTO1", None, "1388.1.n", "AutoLoan"),
        ("AUTO_MISSING", None, "1388.1.n", "AutoLoan"),
        (None, "N1", "1376.2.n", "KN"),  # Invalid business identifier.
        ("outside", "N1", "1446.2", "DebitCard"),
    ]
    db.executemany(
        "insert into sbx_pre_orb_fd.man_prt_tqs_questionnaire values (?, ?, ?, ?)",
        q_rows,
    )
    app_rows = [
        (201, "N1", "MSCL"), (201, "N1", "MSCL"),
        (901, "N1", "MSSA"), (902, "N2", "MSSA"), (903, "N4", "MSSA"),
        (204, "N4", "MSCL"), (205, "N4", "MSCL"),
        (401, "C1", "CCPP_CRCA"), (402, "C2", "CCPP_BATR"),
        (941, "C1", "MSSA"), (942, "C2", "MSSA"),
        (999, "N2", "CCPP_BATR"),  # Must not match the KN branch.
        (None, "N1", "MSSA"), (666, None, "MSSA"),
    ]
    db.executemany(
        "insert into bdm.application values (?, ?, ?, '2999-12-31', '2025-02-01')",
        app_rows,
    )
    db.execute("""
        insert into bdm.application values
        (777, 'NO_MATCH', 'MSCL', '2024-12-31', '2025-02-01'),
        (778, 'N2', 'MSCL', '2999-12-31', '2024-01-01')
    """)
    q_keys = [
        (101, "q1", "1376.2.e"), (101, "q1", "1376.2.e"),
        (102, "q2", "1376.2.n"), (103, "q3", "1376.2.n"),
        (104, "q4", "1376.2.i"), (105, "q1", "1376.2.n"),
        (301, "c1", "1383.1.n"), (302, "c2", "1383.1.n"),
        (303, "c3", "1383.1.n"), (304, "AUTO1", "1383.1.n"),
        (501, "AUTO1", "1388.1.n"), (502, "AUTO_MISSING", "1388.1.n"),
        (None, "invalid_key", "1376.2.n"),
    ]
    db.executemany("""
        insert into sbx_pre_orb_fd.tech_questionnaire_status values
        (?, ?, ?, '2025-02-01', '2025-02-01', '2999-12-31 23:59:59', 'TEST', 'TEST')
    """, q_keys)
    db.execute("""
        update sbx_pre_orb_fd.tech_questionnaire_status
        set questionnaire_dttm = null where questionnaire_rk = 103;
        insert into sbx_pre_orb_fd.tech_questionnaire_status values
        (999, 'historical', '1376.2.n', '2025-02-01', '2025-02-01', '2025-06-01', 'KN', 'KN')
    """)
    tas_rows = [
        (901, "MSSA", 201, "T1", "MSCL"),
        (901, "MSSA", 201, "T1", "MSCL"),  # Duplicate snapshot row.
        (902, "MSSA", 204, "T4", "MSCL"),
        (902, "MSSA", 205, "T5", "MSCL"),
        (903, "MSSA", 206, "T6", "MSCL"),
        (None, None, 207, "UNMATCHED", "MSCL"),
        (901, "OTHER", 208, "WRONG_PARENT_SOURCE", "MSCL"),
        (None, None, 350, "AUTO1", "MSCL"),  # Must not match AUTO branch.
        (None, None, 901, "UZ1", "MSSA"),
        (None, None, 902, "UZ2", "MSSA"),
        (None, None, 903, "UZ3", "MSSA"),
        (941, "MSSA", 401, "C1", "CCPP_CRCA"),
        (None, None, 402, "C2", "CCPP_BATR"),
        (942, "MSSA", 404, "C4", "CCPP_BATR"),
        (901, "MSSA", 501, "WRONG_CHILD_PRODUCT", "CCPP_CRCA"),
        (None, None, 201, "SAME_RK_OTHER_SOURCE", "CCPP_CRCA"),
        (None, None, 601, "AUTO1", "ALPP"),
        (None, None, 601, "AUTO1", "ALPP"),
        (None, None, 602, "AUTO2", "ALPP"),
        (None, None, None, "INVALID_RK", "ALPP"),
    ]
    db.executemany("""
        insert into sbx_pre_orb_fd.tech_application_status values
        (?, ?, ?, ?, ?, '2025-02-01', '2025-02-02')
    """, tas_rows)


def check_fixture():
    db = make_db()
    populate(db)
    for _ in range(2):  # Re-running every DROP/CREATE must reproduce reports.
        run_file(db, "01_inventory.sql")
        run_file(db, "02_probe_uz.sql")
        run_file(db, "03_probe_full_paths.sql")
        first = rows(db, """
            select route, q_total, q_matched, q_coverage_pct,
                   pair_count, q_with_many_apps, apps_with_many_q, many_to_many_pairs
            from sbx_pre_orb_fd.man_qas_02_report where branch = 'KN' order by route
        """)
        assert first == [
            ("DIRECT_PRODUCT", 5, 2, 40.0, 3, 1, 0, 0),
            ("UZ_MSSA", 5, 3, 60.0, 4, 1, 1, 1),
        ], first
        full = rows(db, """
            select route, q_total, q_matched, app_matched, pair_count,
                   q_with_many_apps, apps_with_many_q, many_to_many_pairs,
                   tas_snapshot_confirmed
            from sbx_pre_orb_fd.man_qas_03_report where branch = 'KN' order by route
        """)
        assert full == [
            ("DIRECT_PRODUCT", 5, 2, 3, 3, 1, 0, 0, False),
            ("UZ_PARENT", 5, 3, 4, 6, 2, 2, 4, False),
            ("UZ_SELF", 5, 3, 3, 4, 1, 1, 1, False),
        ], full
        assert rows(db, """
            select q_total, q_matched, app_total, app_matched, pair_count
            from sbx_pre_orb_fd.man_qas_03_report where branch = 'AUTO'
        """) == [(2, 1, 2, 1, 1)]
        assert rows(db, """
            select route, q_total, q_matched, app_total, app_matched
            from sbx_pre_orb_fd.man_qas_03_report where branch = 'KK' order by route
        """) == [
            ("DIRECT_PRODUCT", 4, 2, 5, 2),
            ("UZ_PARENT", 4, 2, 5, 2),
            ("UZ_SELF", 4, 0, 3, 0),
        ]
    print("PASS: source isolation, missing numbers in denominators, status duplicates,")
    print("      competing keys, null parents, historic/current filter, UZ parent vs self,")
    print("      exact coverage counts, N:M detection and repeatability.")


def check_empty():
    db = make_db()
    run_file(db, "02_probe_uz.sql")
    run_file(db, "03_probe_full_paths.sql")
    for table, expected_count in (("02", 4), ("03", 7)):
        report = rows(db, f"""
            select q_total, q_coverage_pct
            from sbx_pre_orb_fd.man_qas_{table}_report
        """)
        assert len(report) == expected_count, report
        assert all(total == 0 and pct is None for total, pct in report), report
    print("PASS: empty inputs keep all route rows; zero denominator returns NULL.")


if __name__ == "__main__":
    for path in sorted((ROOT / "sql").glob("*.sql")):
        count = len(parse_sql(portable_sql(path)))
        print(f"PARSED: {path.name}, {count} PostgreSQL statements")
    check_fixture()
    check_empty()
    print("Offline validation only; Greenplum plans, permissions and real data unverified.")
