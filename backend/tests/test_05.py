from __future__ import annotations

import unittest
from backend.tests.db_test_fixtures import get_in_memory_db


class Test05UserProgress(unittest.TestCase):
    def setUp(self) -> None:
        self.engine, self.conn = get_in_memory_db()
        self.cursor = self.conn.cursor()

        # Set up isolated User and Quiz for progress tracking tests
        self.user_id = 42
        self.cursor.execute(
            """
            INSERT INTO users (id, email, hashed_password, is_verified, onboarded, created_at)
            VALUES (?, ?, ?, 0, 0, datetime('now'));
            """,
            (self.user_id, "user42@example.com", "dummyhash"),
        )

        self.pass_threshold = 3
        self.quiz_slug = "cs-dbms-01"
        self.cursor.execute(
            """
            INSERT INTO Quiz (slug, title, category, difficulty, questions_to_pass)
            VALUES (?, ?, ?, ?, ?);
            """,
            (self.quiz_slug, "DBMS Assessment", "Core CS", "Medium", self.pass_threshold),
        )
        self.quiz_id = self.cursor.lastrowid
        self.conn.commit()

    def tearDown(self) -> None:
        self.conn.close()
        self.engine.dispose()

    def test_05_storing_and_querying_user_progress(self) -> None:
        # Record attempt 1: user scored 2
        self.cursor.execute(
            """
            INSERT INTO quiz_results (user_id, quiz_id, score, submitted_at)
            VALUES (?, ?, ?, datetime('now', '-1 hour'));
            """,
            (self.user_id, self.quiz_slug, 2),
        )
        submission_id_1 = self.cursor.lastrowid

        # Record attempt 2: user scored 4
        self.cursor.execute(
            """
            INSERT INTO quiz_results (user_id, quiz_id, score, submitted_at)
            VALUES (?, ?, ?, datetime('now'));
            """,
            (self.user_id, self.quiz_slug, 4),
        )
        submission_id_2 = self.cursor.lastrowid
        self.conn.commit()

        # Query progress history for user_id using submitted_at
        self.cursor.execute(
            """
            SELECT id, score, submitted_at
            FROM quiz_results
            WHERE user_id = ? AND quiz_id = ?
            ORDER BY submitted_at ASC, id ASC;
            """,
            (self.user_id, self.quiz_slug),
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
            FROM quiz_results
            WHERE user_id = ? AND quiz_id = ?;
            """,
            (self.pass_threshold, self.user_id, self.quiz_slug),
        )
        summary = self.cursor.fetchone()
        total_attempts, highest_score, has_passed = summary

        self.assertEqual(total_attempts, 2)
        self.assertEqual(highest_score, 4)
        self.assertEqual(has_passed, 1, "User should have passed after achieving score 4 >= 3")


if __name__ == "__main__":
    unittest.main()
