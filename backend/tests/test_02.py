from __future__ import annotations

import sqlite3
import unittest
from backend.tests.db_test_fixtures import get_in_memory_db


class Test02Constraints(unittest.TestCase):
    def setUp(self) -> None:
        self.engine, self.conn = get_in_memory_db()
        self.cursor = self.conn.cursor()

    def tearDown(self) -> None:
        self.conn.close()
        self.engine.dispose()

    def test_02_company_and_problem_unique_constraints(self) -> None:
        # Insert Company with is_partner_recruiter
        self.cursor.execute(
            "INSERT INTO Company (slug, name, is_partner_recruiter) VALUES (?, ?, ?);",
            ("tcs", "Tata Consultancy Services", 1),
        )
        company_id = self.cursor.lastrowid
        self.assertIsNotNone(company_id)

        # Duplicate company slug should fail
        with self.assertRaises(sqlite3.IntegrityError):
            self.cursor.execute(
                "INSERT INTO Company (slug, name, is_partner_recruiter) VALUES (?, ?, ?);",
                ("tcs", "Duplicate TCS", 0),
            )

        # Insert Problem
        self.cursor.execute(
            "INSERT INTO Problem (slug, title, difficulty, url) VALUES (?, ?, ?, ?);",
            ("two-sum", "Two Sum", "Easy", "https://leetcode.com/problems/two-sum/"),
        )
        problem_id = self.cursor.lastrowid
        self.assertIsNotNone(problem_id)

        # Duplicate problem slug should fail
        with self.assertRaises(sqlite3.IntegrityError):
            self.cursor.execute(
                "INSERT INTO Problem (slug, title, difficulty) VALUES (?, ?, ?);",
                ("two-sum", "Two Sum Duplicate", "Medium"),
            )

        # Insert Quiz with valid difficulty and unique slug
        self.cursor.execute(
            "INSERT INTO Quiz (slug, title, category, difficulty, questions_to_pass) VALUES (?, ?, ?, ?, ?);",
            ("cs-dbms-01", "DBMS Assessment", "Core CS", "Medium", 3),
        )
        quiz_id = self.cursor.lastrowid
        self.assertIsNotNone(quiz_id)

        # Duplicate quiz slug should fail
        with self.assertRaises(sqlite3.IntegrityError):
            self.cursor.execute(
                "INSERT INTO Quiz (slug, title, category, difficulty, questions_to_pass) VALUES (?, ?, ?, ?, ?);",
                ("cs-dbms-01", "Another DBMS Assessment", "Core CS", "Easy", 3),
            )

        # Invalid difficulty should fail CHECK constraint
        with self.assertRaises(sqlite3.IntegrityError):
            self.cursor.execute(
                "INSERT INTO Quiz (slug, title, category, difficulty, questions_to_pass) VALUES (?, ?, ?, ?, ?);",
                ("invalid-diff-quiz", "Invalid Difficulty Quiz", "General", "SuperHard", 5),
            )

        self.conn.commit()


if __name__ == "__main__":
    unittest.main()
