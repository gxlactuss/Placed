from __future__ import annotations

import sqlite3
import unittest
from backend.tests.db_test_fixtures import get_in_memory_db


class Test06ForeignKeyConstraint(unittest.TestCase):
    def setUp(self) -> None:
        self.engine, self.conn = get_in_memory_db()
        self.cursor = self.conn.cursor()

    def tearDown(self) -> None:
        self.conn.close()
        self.engine.dispose()

    def test_06_submission_foreign_key_constraint(self) -> None:
        # Inserting a quiz result with non-existent user_id must fail FK constraint to users.id
        with self.assertRaises(sqlite3.IntegrityError):
            self.cursor.execute(
                """
                INSERT INTO quiz_results (user_id, quiz_id, score)
                VALUES (?, ?, ?);
                """,
                (99999, "cs-dbms-01", 5),
            )


if __name__ == "__main__":
    unittest.main()
