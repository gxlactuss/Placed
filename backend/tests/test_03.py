from __future__ import annotations

import sqlite3
import unittest
from backend.tests.db_test_fixtures import get_in_memory_db


class Test03CompanyProblemAssociation(unittest.TestCase):
    def setUp(self) -> None:
        self.engine, self.conn = get_in_memory_db()
        self.cursor = self.conn.cursor()

        # Set up isolated data for this test
        self.cursor.execute(
            "INSERT INTO Company (slug, name, is_partner_recruiter) VALUES (?, ?, ?);",
            ("tcs", "Tata Consultancy Services", 1),
        )
        self.company_id = self.cursor.lastrowid

        self.cursor.execute(
            "INSERT INTO Problem (slug, title, difficulty, url) VALUES (?, ?, ?, ?);",
            ("two-sum", "Two Sum", "Easy", "https://leetcode.com/problems/two-sum/"),
        )
        self.problem_id = self.cursor.lastrowid
        self.conn.commit()

    def tearDown(self) -> None:
        self.conn.close()
        self.engine.dispose()

    def test_03_company_problem_association_and_fk_enforcement(self) -> None:
        # Valid association
        self.cursor.execute(
            "INSERT INTO CompanyProblem (company_id, problem_id, topics) VALUES (?, ?, ?);",
            (self.company_id, self.problem_id, "Array, Hash Table"),
        )
        self.conn.commit()

        # Duplicate composite primary key should fail
        with self.assertRaises(sqlite3.IntegrityError):
            self.cursor.execute(
                "INSERT INTO CompanyProblem (company_id, problem_id, topics) VALUES (?, ?, ?);",
                (self.company_id, self.problem_id, "Duplicate"),
            )

        # Invalid foreign key company_id should fail
        with self.assertRaises(sqlite3.IntegrityError):
            self.cursor.execute(
                "INSERT INTO CompanyProblem (company_id, problem_id, topics) VALUES (?, ?, ?);",
                (99999, self.problem_id, "Non-existent Company"),
            )

        # Invalid foreign key problem_id should fail
        with self.assertRaises(sqlite3.IntegrityError):
            self.cursor.execute(
                "INSERT INTO CompanyProblem (company_id, problem_id, topics) VALUES (?, ?, ?);",
                (self.company_id, 99999, "Non-existent Problem"),
            )


if __name__ == "__main__":
    unittest.main()
