#!/usr/bin/env python3
"""
Empties every table in the database the app is configured to use.

Deletes rows rather than the SQLite file, so the schema — including the columns
`init_db()` bolts on by ALTER TABLE, since there is no migrations framework —
survives and the API keeps serving without a restart. Runs `VACUUM` afterwards
so the file actually shrinks instead of keeping the freed pages.

Reads `DATABASE_URL` exactly the way `database/db.py` does, which means it hits
whatever the environment points at: `backend/.env` locally, and the mounted
volume (`sqlite:////data/placement_prep.db`) inside the Fly machine.

    python3 scripts/wipe_database.py --yes            # wipe
    python3 scripts/wipe_database.py                  # counts only, no writes

This is unrecoverable — accounts, interview transcripts, solved problems and
quiz results all go. `--yes` is required precisely so a stray shell history
entry cannot do it by itself.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import app  # noqa: F401  — bootstraps sys.path for `database` and loads backend/.env

from sqlalchemy import text
from database.db import engine


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--yes", action="store_true", help="actually delete; omit for a dry run")
    args = parser.parse_args()

    print(f"database: {os.environ.get('DATABASE_URL', '(default from database/db.py)')}")

    with engine.connect() as connection:
        tables = [
            row[0]
            for row in connection.execute(
                text("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
            )
        ]
        if not tables:
            sys.exit("no tables found — is DATABASE_URL pointing where you think?")

        for table in tables:
            count = connection.execute(text(f'SELECT COUNT(*) FROM "{table}"')).scalar()
            print(f"  {table}: {count} rows")

        if not args.yes:
            print("\ndry run — nothing deleted. Re-run with --yes to wipe.")
            return

        for table in tables:
            connection.execute(text(f'DELETE FROM "{table}"'))
        # Autoincrement counters live here, so ids restart at 1 for a fresh bank.
        if connection.execute(
            text("SELECT COUNT(*) FROM sqlite_master WHERE name='sqlite_sequence'")
        ).scalar():
            connection.execute(text("DELETE FROM sqlite_sequence"))
        connection.commit()
        connection.execute(text("VACUUM"))

        print("\nwiped:")
        for table in tables:
            count = connection.execute(text(f'SELECT COUNT(*) FROM "{table}"')).scalar()
            print(f"  {table}: {count} rows")


if __name__ == "__main__":
    main()
