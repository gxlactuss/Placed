#!/usr/bin/env python3

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import app

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
