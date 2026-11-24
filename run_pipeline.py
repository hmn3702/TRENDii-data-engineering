"""
TRENDii data engineering pipeline runner.

Runs the SQL models in order (staging -> dimensions -> facts -> marts ->
analysis) inside a DuckDB database, runs data-quality tests, and exports
the analysis answers to CSV.

Usage:
    python run_pipeline.py
    python run_pipeline.py --data-dir data --db warehouse/trendii.duckdb --output-dir output
    python run_pipeline.py --skip-tests
"""
from __future__ import annotations

import argparse
import logging
import re
import sys
import time
from pathlib import Path

try:
    import duckdb
except ImportError:  # pragma: no cover
    sys.exit("DuckDB is not installed. Run:  python -m pip install -r requirements.txt")

ROOT = Path(__file__).resolve().parent
SQL_DIR = ROOT / "sql"
TEST_FILE = ROOT / "tests" / "data_quality.sql"
LAYERS = ["01_staging", "02_dimensions", "03_facts", "04_marts", "05_analysis"]
REQUIRED_INPUTS = ["dim_product.csv", "dim_campaign.csv"]

log = logging.getLogger("pipeline")


class PipelineError(Exception):
    """Raised when a step fails; carries a readable message."""


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Build the TRENDii analytics model in DuckDB.")
    p.add_argument("--data-dir", default=str(ROOT / "data"), help="Folder with *.parquet events and dim CSVs")
    p.add_argument("--db", default=str(ROOT / "warehouse" / "trendii.duckdb"), help="DuckDB database file")
    p.add_argument("--output-dir", default=str(ROOT / "output"), help="Where answer CSVs are written")
    p.add_argument("--temp-dir", default=None, help="Optional DuckDB spill folder")
    p.add_argument("--skip-tests", action="store_true", help="Do not run data-quality tests")
    p.add_argument("-v", "--verbose", action="store_true")
    return p.parse_args()


def validate_inputs(data_dir: Path) -> None:
    """Fail fast with a clear message if input files are missing."""
    if not data_dir.is_dir():
        raise PipelineError(f"Data folder not found: {data_dir}")
    parquet = sorted(data_dir.glob("*.parquet"))
    if not parquet:
        raise PipelineError(f"No *.parquet event files in {data_dir}")
    missing = [f for f in REQUIRED_INPUTS if not (data_dir / f).is_file()]
    if missing:
        raise PipelineError(f"Missing dimension file(s) in {data_dir}: {', '.join(missing)}")
    bad_names = [f.name for f in parquet if not re.fullmatch(r"\d{4}-\d{2}-\d{2}\.parquet", f.name)]
    if bad_names:
        log.warning("Files not named YYYY-MM-DD.parquet will be rejected (no event_date): %s", bad_names)
    log.info("Inputs OK: %d event files (%s .. %s)", len(parquet), parquet[0].stem, parquet[-1].stem)


def sql_literal(value: str) -> str:
    """Escape a value for use inside a single-quoted SQL string ('it''s')."""
    return value.replace("'", "''")


def render(sql: str, params: dict[str, str]) -> str:
    for key, value in params.items():
        sql = sql.replace("{{" + key + "}}", value)
    leftover = re.findall(r"\{\{\s*\w+\s*\}\}", sql)
    if leftover:
        raise PipelineError(f"Unresolved template variables: {leftover}")
    return sql


def run_models(con: duckdb.DuckDBPyConnection, params: dict[str, str]) -> None:
    for layer in LAYERS:
        files = sorted((SQL_DIR / layer).glob("*.sql"))
        if not files:
            raise PipelineError(f"No SQL files found in {SQL_DIR / layer}")
        log.info("== Layer %s (%d models)", layer, len(files))
        for f in files:
            start = time.perf_counter()
            try:
                con.execute("BEGIN TRANSACTION")
                con.execute(render(f.read_text(encoding="utf-8"), params))
                con.execute("COMMIT")
            except duckdb.Error as exc:
                con.execute("ROLLBACK")
                raise PipelineError(f"Model {f.relative_to(ROOT)} failed: {exc}") from exc
            log.info("   %-45s %6.2fs", f.name, time.perf_counter() - start)


def parse_tests(text: str) -> list[tuple[str, str, str]]:
    tests = []
    pattern = re.compile(r"^--\s*test:\s*(.+?)\s*\|\s*(error|warn)\s*$\n(.*?;)", re.M | re.S)
    for name, severity, query in pattern.findall(text):
        tests.append((name, severity, query.strip()))
    return tests


def run_tests(con: duckdb.DuckDBPyConnection) -> bool:
    tests = parse_tests(TEST_FILE.read_text(encoding="utf-8"))
    log.info("== Data-quality tests (%d)", len(tests))
    ok = True
    for name, severity, query in tests:
        try:
            row = con.execute(query).fetchone()
        except duckdb.Error as exc:
            log.error("   ERROR  %-60s query failed: %s", name, exc)
            ok = False
            continue
        failing = row[0] if row else None
        if failing is None:
            log.error("   ERROR  %-60s returned no value", name)
            ok = False
        elif failing == 0:
            log.info("   PASS   %s", name)
        elif severity == "warn":
            log.warning("   WARN   %-60s %d rows", name, failing)
        else:
            log.error("   FAIL   %-60s %d rows", name, failing)
            ok = False
    return ok


def export_answers(con: duckdb.DuckDBPyConnection, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    tables = [r[0] for r in con.execute(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_name LIKE 'ans_%' ORDER BY table_name").fetchall()]
    log.info("== Exporting %d answer tables to %s", len(tables), out_dir)
    for t in tables:
        target = out_dir / f"{t.removeprefix('ans_')}.csv"
        con.execute(f"COPY {t} TO '{sql_literal(target.as_posix())}' (HEADER, DELIMITER ',')")
        log.info("   %s", target.name)


def main() -> int:
    args = parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)-7s %(message)s", datefmt="%H:%M:%S")
    data_dir = Path(args.data_dir).resolve()
    db_path = Path(args.db).resolve()
    started = time.perf_counter()
    try:
        validate_inputs(data_dir)
        db_path.parent.mkdir(parents=True, exist_ok=True)
        config = {"temp_directory": args.temp_dir} if args.temp_dir else {}
        with duckdb.connect(str(db_path), config=config) as con:
            run_models(con, {"data_dir": sql_literal(data_dir.as_posix())})
            if args.skip_tests:
                log.warning("Data-quality tests skipped (--skip-tests)")
                tests_ok = True
            else:
                tests_ok = run_tests(con)
            if tests_ok:
                export_answers(con, Path(args.output_dir).resolve())
            else:
                log.error("Answers NOT exported because an error-level test failed. "
                          "Any CSVs already in %s are from an earlier run.", args.output_dir)
    except PipelineError as exc:
        log.error("Pipeline failed: %s", exc)
        return 1
    except duckdb.Error as exc:
        log.error("Database error: %s", exc)
        return 1
    if not tests_ok:
        log.error("Finished with failing data-quality tests (%.1fs)", time.perf_counter() - started)
        return 2
    log.info("Pipeline finished OK in %.1fs. Database: %s", time.perf_counter() - started, db_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
