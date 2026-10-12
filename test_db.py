"""Automated test suite verifying SQLite database setup, foreign key integrity,
and user progress tracking for the 'placed' project.
"""

from __future__ import annotations

from pathlib import Path
import sqlite3
import unittest

from init_db import init_database

TEST_DB_PATH = Path(__file__).resolve().parent / "test_placed.db"
SCHEMA_PATH = Path(__file__).resolve().parent / "schema.sql"


class TestDatabaseSetupAndProgress(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if TEST_DB_PATH.exists():
            TEST_DB_PATH.unlink()
        init_database(db_path=TEST_DB_PATH, schema_path=SCHEMA_PATH)

    @classmethod
    def tearDownClass(cls) -> None:
        if TEST_DB_PATH.exists():
            TEST_DB_PATH.unlink()


    def setUp(self) -> None:
        self.conn = sqlite3.connect(TEST_DB_PATH)
        self.conn.execute("PRAGMA foreign_keys = ON;")
        self.cursor = self.conn.cursor()

    def tearDown(self) -> None:
        self.conn.close()

    def test_01_all_tables_exist(self) -> None:
        """Verify all 7 expected tables exist in the database."""
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
            "Submission",
        }
        self.assertTrue(expected.issubset(tables), f"Missing tables: {expected - tables}")

    def test_02_company_and_problem_unique_constraints(self) -> None:
        """Verify insertion of Company and Problem, and UNIQUE slug constraints."""
        # Insert Company
        self.cursor.execute(
            "INSERT INTO Company (slug, name, is_kjsit_recruiter) VALUES (?, ?, ?);",
            ("tcs", "Tata Consultancy Services", 1),
        )
        company_id = self.cursor.lastrowid
        self.assertIsNotNone(company_id)

        # Duplicate slug should fail
        with self.assertRaises(sqlite3.IntegrityError):
            self.cursor.execute(
                "INSERT INTO Company (slug, name, is_kjsit_recruiter) VALUES (?, ?, ?);",
                ("tcs", "Duplicate TCS", 0),
            )

        # Insert Problem
        self.cursor.execute(
            "INSERT INTO Problem (slug, title, difficulty, url) VALUES (?, ?, ?, ?);",
            ("two-sum", "Two Sum", "Easy", "https://leetcode.com/problems/two-sum/"),
        )
        problem_id = self.cursor.lastrowid
        self.assertIsNotNone(problem_id)

        # Duplicate slug should fail
        with self.assertRaises(sqlite3.IntegrityError):
            self.cursor.execute(
                "INSERT INTO Problem (slug, title, difficulty) VALUES (?, ?, ?);",
                ("two-sum", "Two Sum Duplicate", "Medium"),
            )

        self.conn.commit()

    def test_03_company_problem_association_and_fk_enforcement(self) -> None:
        """Verify CompanyProblem join table, composite primary key, and foreign key enforcement."""
        # Query existing IDs
        self.cursor.execute("SELECT id FROM Company WHERE slug = 'tcs';")
        company_id = self.cursor.fetchone()[0]
        self.cursor.execute("SELECT id FROM Problem WHERE slug = 'two-sum';")
        problem_id = self.cursor.fetchone()[0]

        # Valid association
        self.cursor.execute(
            "INSERT INTO CompanyProblem (company_id, problem_id, topics) VALUES (?, ?, ?);",
            (company_id, problem_id, "Array, Hash Table"),
        )
        self.conn.commit()

        # Duplicate composite primary key should fail
        with self.assertRaises(sqlite3.IntegrityError):
            self.cursor.execute(
                "INSERT INTO CompanyProblem (company_id, problem_id, topics) VALUES (?, ?, ?);",
                (company_id, problem_id, "Duplicate"),
            )

        # Invalid foreign key company_id should fail
        with self.assertRaises(sqlite3.IntegrityError):
            self.cursor.execute(
                "INSERT INTO CompanyProblem (company_id, problem_id, topics) VALUES (?, ?, ?);",
                (99999, problem_id, "Non-existent Company"),
            )

        # Invalid foreign key problem_id should fail
        with self.assertRaises(sqlite3.IntegrityError):
            self.cursor.execute(
                "INSERT INTO CompanyProblem (company_id, problem_id, topics) VALUES (?, ?, ?);",
                (company_id, 99999, "Non-existent Problem"),
            )

    def test_04_quiz_questions_and_options(self) -> None:
        """Verify Quiz, Question, and Option relationships."""
        self.cursor.execute(
            """
            INSERT INTO Quiz (title, category, difficulty, questions_to_pass)
            VALUES (?, ?, ?, ?);
            """,
            ("Python Core Assessment", "Core CS", "Medium", 3),
        )
        quiz_id = self.cursor.lastrowid

        # Insert Question
        self.cursor.execute(
            """
            INSERT INTO Question (quiz_id, prompt, correct_option_id)
            VALUES (?, ?, ?);
            """,
            (quiz_id, "What is the output of print(type([])) in Python?", "opt-2"),
        )
        question_id = self.cursor.lastrowid

        # Insert Options
        self.cursor.execute(
            "INSERT INTO Option (question_id, label, text) VALUES (?, ?, ?);",
            (question_id, "A", "<class 'tuple'>"),
        )
        self.cursor.execute(
            "INSERT INTO Option (question_id, label, text) VALUES (?, ?, ?);",
            (question_id, "B", "<class 'list'>"),
        )
        self.conn.commit()

        # Invalid question with non-existent quiz_id should fail
        with self.assertRaises(sqlite3.IntegrityError):
            self.cursor.execute(
                "INSERT INTO Question (quiz_id, prompt) VALUES (?, ?);",
                (88888, "Invalid question prompt"),
            )

    def test_05_storing_and_querying_user_progress(self) -> None:
        """Verify that user submissions correctly store and retrieve user progress."""
        self.cursor.execute("SELECT id, questions_to_pass FROM Quiz LIMIT 1;")
        quiz = self.cursor.fetchone()
        quiz_id = quiz[0]
        pass_threshold = quiz[1]

        user_id = 42

        # Record attempt 1: user scored 2
        self.cursor.execute(
            """
            INSERT INTO Submission (user_id, quiz_id, score)
            VALUES (?, ?, ?);
            """,
            (user_id, quiz_id, 2),
        )
        submission_id_1 = self.cursor.lastrowid

        # Record attempt 2: user scored 4
        self.cursor.execute(
            """
            INSERT INTO Submission (user_id, quiz_id, score)
            VALUES (?, ?, ?);
            """,
            (user_id, quiz_id, 4),
        )
        submission_id_2 = self.cursor.lastrowid
        self.conn.commit()

        # Query progress history for user_id
        self.cursor.execute(
            """
            SELECT id, score, timestamp
            FROM Submission
            WHERE user_id = ? AND quiz_id = ?
            ORDER BY timestamp ASC, id ASC;
            """,
            (user_id, quiz_id),
        )
        submissions = self.cursor.fetchall()

        self.assertEqual(len(submissions), 2)
        self.assertEqual(submissions[0][0], submission_id_1)
        self.assertEqual(submissions[0][1], 2)
        self.assertEqual(submissions[1][0], submission_id_2)
        self.assertEqual(submissions[1][1], 4)

        # Verify aggregate progress (highest score, total attempts, passed status)
        self.cursor.execute(
            """
            SELECT 
                COUNT(*) AS total_attempts,
                MAX(score) AS highest_score,
                MAX(score) >= ? AS has_passed
            FROM Submission
            WHERE user_id = ? AND quiz_id = ?;
            """,
            (pass_threshold, user_id, quiz_id),
        )
        summary = self.cursor.fetchone()
        total_attempts, highest_score, has_passed = summary

        self.assertEqual(total_attempts, 2)
        self.assertEqual(highest_score, 4)
        self.assertEqual(has_passed, 1, "User should have passed after achieving score 4 >= 3")

    def test_06_submission_foreign_key_constraint(self) -> None:
        """Verify that creating a submission with invalid quiz_id is rejected."""
        with self.assertRaises(sqlite3.IntegrityError):
            self.cursor.execute(
                "INSERT INTO Submission (user_id, quiz_id, score) VALUES (?, ?, ?);",
                (1, 99999, 5),
            )

    def test_07_cascade_deletion(self) -> None:
        """Verify ON DELETE CASCADE removes dependent records when parent is deleted."""
        # Create dedicated quiz for deletion test
        self.cursor.execute(
            "INSERT INTO Quiz (title, questions_to_pass) VALUES ('Temporary Quiz', 1);"
        )
        temp_quiz_id = self.cursor.lastrowid

        self.cursor.execute(
            "INSERT INTO Question (quiz_id, prompt) VALUES (?, 'Temp Question');",
            (temp_quiz_id,),
        )
        temp_question_id = self.cursor.lastrowid

        self.cursor.execute(
            "INSERT INTO Option (question_id, text) VALUES (?, 'Temp Option');",
            (temp_question_id,),
        )

        self.cursor.execute(
            "INSERT INTO Submission (user_id, quiz_id, score) VALUES (99, ?, 1);",
            (temp_quiz_id,),
        )
        self.conn.commit()

        # Delete Quiz
        self.cursor.execute("DELETE FROM Quiz WHERE id = ?;", (temp_quiz_id,))
        self.conn.commit()

        # Verify child questions, options, and submissions were deleted
        self.cursor.execute("SELECT COUNT(*) FROM Question WHERE quiz_id = ?;", (temp_quiz_id,))
        self.assertEqual(self.cursor.fetchone()[0], 0)

        self.cursor.execute("SELECT COUNT(*) FROM Option WHERE question_id = ?;", (temp_question_id,))
        self.assertEqual(self.cursor.fetchone()[0], 0)

        self.cursor.execute("SELECT COUNT(*) FROM Submission WHERE quiz_id = ?;", (temp_quiz_id,))
        self.assertEqual(self.cursor.fetchone()[0], 0)


if __name__ == "__main__":
    unittest.main()
