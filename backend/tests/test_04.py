from __future__ import annotations

import sqlite3
import unittest
from backend.tests.db_test_fixtures import get_in_memory_db


class Test04QuizQuestionsAndOptions(unittest.TestCase):
    def setUp(self) -> None:
        self.engine, self.conn = get_in_memory_db()
        self.cursor = self.conn.cursor()

    def tearDown(self) -> None:
        self.conn.close()
        self.engine.dispose()

    def test_04_quiz_questions_and_options(self) -> None:
        self.cursor.execute(
            """
            INSERT INTO Quiz (slug, title, category, difficulty, questions_to_pass)
            VALUES (?, ?, ?, ?, ?);
            """,
            ("python-core-assessment", "Python Core Assessment", "Core CS", "Medium", 3),
        )
        quiz_id = self.cursor.lastrowid
        self.assertIsNotNone(quiz_id)

        # Insert Question (correct_option_id removed as per schema refactoring)
        self.cursor.execute(
            """
            INSERT INTO Question (quiz_id, prompt)
            VALUES (?, ?);
            """,
            (quiz_id, "What is the output of print(type([])) in Python?"),
        )
        question_id = self.cursor.lastrowid
        self.assertIsNotNone(question_id)

        # Insert Options with is_correct field
        self.cursor.execute(
            "INSERT INTO Option (question_id, label, text, is_correct) VALUES (?, ?, ?, ?);",
            (question_id, "A", "<class 'tuple'>", 0),
        )
        self.cursor.execute(
            "INSERT INTO Option (question_id, label, text, is_correct) VALUES (?, ?, ?, ?);",
            (question_id, "B", "<class 'list'>", 1),
        )
        self.conn.commit()

        # Query options and verify is_correct values
        self.cursor.execute(
            "SELECT label, text, is_correct FROM Option WHERE question_id = ? ORDER BY id ASC;",
            (question_id,),
        )
        options = self.cursor.fetchall()
        self.assertEqual(len(options), 2)
        self.assertEqual(options[0], ("A", "<class 'tuple'>", 0))
        self.assertEqual(options[1], ("B", "<class 'list'>", 1))

        # Invalid question with non-existent quiz_id should fail
        with self.assertRaises(sqlite3.IntegrityError):
            self.cursor.execute(
                "INSERT INTO Question (quiz_id, prompt) VALUES (?, ?);",
                (88888, "Invalid question prompt"),
            )


if __name__ == "__main__":
    unittest.main()
