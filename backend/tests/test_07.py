from __future__ import annotations

import unittest
from backend.tests.db_test_fixtures import get_in_memory_db


class Test07CascadeDeletion(unittest.TestCase):
    def setUp(self) -> None:
        self.engine, self.conn = get_in_memory_db()
        self.cursor = self.conn.cursor()

    def tearDown(self) -> None:
        self.conn.close()
        self.engine.dispose()

    def test_07_cascade_deletion(self) -> None:
        # Create dedicated quiz for deletion test
        self.cursor.execute(
            """
            INSERT INTO Quiz (slug, title, questions_to_pass)
            VALUES ('temp-quiz', 'Temporary Quiz', 1);
            """
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
        self.conn.commit()

        # Delete Quiz
        self.cursor.execute("DELETE FROM Quiz WHERE id = ?;", (temp_quiz_id,))
        self.conn.commit()

        # Verify child questions and options were cascade-deleted
        self.cursor.execute("SELECT COUNT(*) FROM Question WHERE quiz_id = ?;", (temp_quiz_id,))
        self.assertEqual(self.cursor.fetchone()[0], 0)

        self.cursor.execute("SELECT COUNT(*) FROM Option WHERE question_id = ?;", (temp_question_id,))
        self.assertEqual(self.cursor.fetchone()[0], 0)


if __name__ == "__main__":
    unittest.main()
