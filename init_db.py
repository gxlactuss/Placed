"""Database initialization script for the 'placed' project.

Applies schema.sql to an SQLite database with foreign keys enabled and verifies
the created tables.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sqlite3
import sys

BASE_DIR = Path(__file__).resolve().parent
DEFAULT_DB_PATH = BASE_DIR / "placed.db"
DEFAULT_SCHEMA_PATH = BASE_DIR / "schema.sql"

EXPECTED_TABLES = [
    "Company",
    "Problem",
    "CompanyProblem",
    "Quiz",
    "Question",
    "Option",
    "Submission",
]


def init_database(db_path: Path = DEFAULT_DB_PATH, schema_path: Path = DEFAULT_SCHEMA_PATH) -> None:
    if not schema_path.exists():
        raise FileNotFoundError(f"Schema file not found at: {schema_path}")

    print(f"Initializing database at: {db_path}")
    print(f"Using schema file: {schema_path}")

    with sqlite3.connect(db_path) as conn:
        cursor = conn.cursor()

        # Step 1: Explicitly enable foreign key constraints
        cursor.execute("PRAGMA foreign_keys = ON;")
        fk_status = cursor.execute("PRAGMA foreign_keys;").fetchone()[0]
        if fk_status != 1:
            raise RuntimeError("Failed to enable foreign key constraints in SQLite.")
        print("[OK] Foreign key constraints enabled (PRAGMA foreign_keys = ON).")

        # Step 2: Read and execute the schema script
        schema_sql = schema_path.read_text(encoding="utf-8")
        cursor.executescript(schema_sql)
        conn.commit()
        print("[OK] Executed schema.sql successfully.")

        # Step 3: Verify all expected tables exist
        cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;"
        )
        existing_tables = {row[0] for row in cursor.fetchall()}

        print("\nVerifying tables:")
        missing_tables = []
        for table in EXPECTED_TABLES:
            if table in existing_tables:
                cursor.execute(f"PRAGMA table_info('{table}');")
                columns = [f"{col[1]} ({col[2]})" for col in cursor.fetchall()]
                print(f"  - {table}: {', '.join(columns)}")
            else:
                missing_tables.append(table)
                print(f"  [MISSING] {table}")

        if missing_tables:
            raise RuntimeError(f"Missing expected tables: {missing_tables}")

        # Step 4: Verify foreign key integrity
        cursor.execute("PRAGMA foreign_key_check;")
        fk_violations = cursor.fetchall()
        if fk_violations:
            raise RuntimeError(f"Foreign key violations found: {fk_violations}")
        print("\n[OK] Schema integrity check passed with zero violations.")

    print(f"\nDatabase initialization complete: {db_path}\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Initialize the SQLite database for placed.")
    parser.add_argument(
        "--db",
        type=Path,
        default=DEFAULT_DB_PATH,
        help=f"Path to output SQLite database file (default: {DEFAULT_DB_PATH})",
    )
    parser.add_argument(
        "--schema",
        type=Path,
        default=DEFAULT_SCHEMA_PATH,
        help=f"Path to SQL schema file (default: {DEFAULT_SCHEMA_PATH})",
    )
    args = parser.parse_args()

    try:
        init_database(db_path=args.db, schema_path=args.schema)
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
