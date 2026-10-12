from __future__ import annotations

import unittest
from backend.tests.db_test_fixtures import get_in_memory_db


class Test01AllTablesExist(unittest.TestCase):
    def setUp(self) -> None:
        self.engine, self.conn = get_in_memory_db()
        self.cursor = self.conn.cursor()

    def tearDown(self) -> None:
        self.conn.close()
        self.engine.dispose()

    def test_01_all_tables_exist(self) -> None:
        self.cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';"
        )
        tables = {row[0] for row in self.cursor.fetchall()}
        expected = {
            "Company",
            "Problem",
            "CompanyProblem",
            "Quiz",
            "Question",
            "Option",
            "quiz_results",
        }
        self.assertTrue(expected.issubset(tables), f"Missing tables: {expected - tables}")


if __name__ == "__main__":
    unittest.main()
