"""Synthetic tests for the standalone questionnaire verification layer.

Run with duckdb and pglast installed. No bank connection or real data.
"""

from pathlib import Path
import re

import duckdb
from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
RULES = ROOT / "sql/status_by_product.sql"
WORKFLOW = ROOT / "sql/workflow/01_questionnaire_verification.sql"
SCHEMA = "sbx_pre_orb_fd"


def postgres_sql(path):
    return re.sub(r"\bdistributed\s+randomly\s*;", ";", path.read_text(), flags=re.I)


def offline_sql(path):
    return re.sub(
        r"with\s*\(appendonly\s*=\s*true,\s*orientation\s*=\s*column,\s*"
        r"compresstype\s*=\s*zstd,\s*compresslevel\s*=\s*5\)",
        "",
        postgres_sql(path),
        flags=re.I,
    )


def make_db():
    db = duckdb.connect()
    db.execute(f"create schema {SCHEMA}")
    db.execute("create macro btrim(value) as trim(value)")
    db.execute(f"""
        create table {SCHEMA}.tech_questionnaire_status (
            questionnaire_rk bigint, questionnaire_id text, src_cd text,
            level25_product_bp_nm text, status_cd text,
            effective_from_dttm timestamp, effective_to_dttm timestamp
        )
    """)
    return db


def populate(db):
    data = [
        (1, "q1", "1376.1", "Потребкредит", "CHECK_LIST_EMPTY", "2025-01-01", "2025-02-01"),
        (1, "q1", "1376.1", "Потребкредит", "закрыта", "2025-02-01", "2999-12-31"),
        (1, "a1", "1388.1", "Автокредит", "DRAFT", "2025-01-01", "2999-12-31"),
        (2, "q2", "1376.1", "Потребкредит", "DRAFT", "2025-01-01", "2999-12-31"),
        (3, "q3", "1383.1", "Кредитные карты", "DONE", "2025-01-01", "2999-12-31"),
        (4, "q4", "1388.1", "Автокредит", "VERIFICATION", "2025-01-01", "2999-12-31"),
        (5, "q5", "1388.1", "Автокредит", "APPROVED", "2025-01-01", "2999-12-31"),
        (6, "q6", "1376.1", "Потребкредит", "IDENTIFICATION", "2025-01-01", "2999-12-31"),
        (7, "q7", "1376.1", "Кредитные карты", "DONE", "2025-01-01", "2999-12-31"),
        (8, "q8", "1383.1", "Кредитные карты", None, "2025-01-01", "2999-12-31"),
        (9, "q9", "1376.1", "Потребкредит", "DRAFT", "2025-01-01", "2080-01-01"),
        (9, "q9", "1376.1", "Потребкредит", "CHECK_LIST_EMPTY", "2080-01-01", "2999-12-31"),
        (10, "q10", "1376.1", "Потребкредит", "CHECK_LIST_EMPTY", "2025-01-01", "2025-02-01"),
        (10, "q10", "1376.1", "UNKNOWN", "DRAFT", "2025-02-01", "2999-12-31"),
        (11, "q11a", "1376.1", "Потребкредит", "CHECK_LIST_EMPTY", "2025-01-01", "2025-02-01"),
        (11, "q11b", "1376.1", "Потребкредит", "DRAFT", "2025-02-01", "2999-12-31"),
        (12, "q12", "1376.1", "Потребкредит", "CHECK_LIST_EMPTY", None, "2999-12-31"),
        (13, "q13", "1388.1", "Автокредит", "DEAL_VER", "2025-01-01", "2999-12-31"),
        (13, "q13", "1388.1", "Автокредит", "REVIEW", "2025-01-01", "2999-12-31"),
        (14, "q14", "1383.1", "Кредитные карты", "DONE", "2025-01-01", "2999-12-31"),
        (14, "q14", "1383.1", "Кредитные карты", "DONE", "2025-01-01", "2999-12-31"),
        (15, "future_only", "1383.1", "Кредитные карты", "DONE", "2080-01-01", "2999-12-31"),
        (16, "q16", "1376.1", "Потребкредит", "одобрено", "2025-01-01", "2999-12-31"),
        (17, "q17", "1376.1", "Потребкредит", "DONE", "2025-01-01", "2999-12-31"),
        (None, "null_key", "1388.1", "Автокредит", "VERIFICATION", "2025-01-01", "2999-12-31"),
        (-1, "placeholder", "1388.1", "Автокредит", "VERIFICATION", "2025-01-01", "2999-12-31"),
    ]
    db.executemany(f"insert into {SCHEMA}.tech_questionnaire_status values (?, ?, ?, ?, ?, ?, ?)", data)


def recalculate(db):
    # Recompute after changing policy, without recreating policy/parameters.
    sql = offline_sql(WORKFLOW)
    db.execute(sql[sql.index("-- 1.3."):])


def setup(db):
    db.execute(offline_sql(RULES))
    db.execute(offline_sql(WORKFLOW))
    db.execute(f"update {SCHEMA}.prt_qs_verification_params set report_dttm = '2026-10-15'")
    recalculate(db)


def flags(db):
    result = db.execute(f"""
        select questionnaire_rk, src_cd, verification_flg,
               verification_candidate_flg, verification_reason
        from {SCHEMA}.prt_qs_verification_flags
    """).fetchall()
    assert len(result) == len({(r[0], r[1]) for r in result})
    return {(r[0], r[1]): r[2:] for r in result}


def check_cases():
    db = make_db()
    populate(db)
    setup(db)
    draft = flags(db)
    assert all(value[0] is None for value in draft.values())
    assert draft[(1, "1376.1")][1] == 1  # Historical hit survives current non-hit.
    assert draft[(1, "1388.1")][1] == 0  # Same RK in another source stays separate.
    assert draft[(9, "1376.1")][1] == 0  # Future hit not used.
    assert draft[(17, "1376.1")][1] == 0  # DONE only a KK candidate.
    assert (15, "1383.1") not in draft
    assert all(key[0] is not None and key[0] != -1 for key in draft)
    assert flags_after_restart(db) == draft

    db.execute(f"update {SCHEMA}.prt_qs_verification_policy set status_rule_confirmed = true")
    recalculate(db)
    positive_only = flags(db)
    for key in [(1, "1376.1"), (3, "1383.1"), (4, "1388.1"), (13, "1388.1"), (14, "1383.1"), (16, "1376.1")]:
        assert positive_only[key][0] is True, (key, positive_only[key])
    for key in [(2, "1376.1"), (5, "1388.1"), (6, "1376.1"), (9, "1376.1")]:
        assert positive_only[key][0] is None, (key, positive_only[key])

    db.execute(f"update {SCHEMA}.prt_qs_verification_policy set history_complete_confirmed = true")
    recalculate(db)
    complete = flags(db)
    for key in [(2, "1376.1"), (5, "1388.1"), (6, "1376.1"), (9, "1376.1"), (17, "1376.1")]:
        assert complete[key][0] is False, (key, complete[key])
    for key in [(7, "1376.1"), (8, "1383.1"), (10, "1376.1"), (11, "1376.1"), (12, "1376.1")]:
        assert complete[key][0] is None, (key, complete[key])

    db.execute(f"update {SCHEMA}.prt_qs_verification_policy set verification_mode = 'CURRENT_STATUS'")
    recalculate(db)
    current = flags(db)
    assert current[(1, "1376.1")][0] is False
    assert current[(3, "1383.1")][0] is True
    assert current[(13, "1388.1")][0] is None  # Two simultaneous statuses.
    assert current[(14, "1383.1")][0] is None  # Duplicate active input needs review.
    assert current[(8, "1383.1")][0] is None  # Missing status is not False.
    print("PASS: draft rules stay NULL; candidates are product/source-qualified.")
    print("PASS: past/current/future status semantics; completeness gates; source isolation.")
    print("PASS: conflicting IDs/products, invalid intervals, duplicate active statuses,")
    print("      invalid keys, unique output keys and repeatable setup.")


def flags_after_restart(db):
    setup(db)
    return flags(db)


if __name__ == "__main__":
    for path in (RULES, WORKFLOW):
        print(f"PARSED: {path.name}, {len(parse_sql(postgres_sql(path)))} PostgreSQL statements")
    check_cases()
    empty_db = make_db()
    setup(empty_db)
    assert flags(empty_db) == {}
    print("PASS: empty input. Offline tests do not confirm bank rules or Greenplum execution.")
