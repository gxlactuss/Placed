import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from fastapi.testclient import TestClient
from sqlmodel import Session, create_engine

import database.db as db
from app.ai import routes as interview_routes
from app.ai.interview_difficulty import MIN_QUESTIONS, RoundState, plan_next_turn
from app.ai.interview_mode import InterviewMode
from app.ai.interview_prompts import feedback_prompt, follow_up_prompt, opening_prompt
from app.auth.jwt import create_access_token, hash_password
from app.content.company_expectations import DATA_FILE, company_names, find_company
from app.main import app
from database.models.user import User

BUNDLED_CSVS = Path(__file__).resolve().parents[2] / "frontend/PlacementPrep/Resources/Companies"

TRANSCRIPT = [
    {"speaker": "ai", "text": "Tell me about a disagreement.", "level": 3, "topic": "Teamwork"},
    {"speaker": "user", "text": "I disagreed with my teammate about the database."},
]


class CompanyDataTests(unittest.TestCase):

    def test_every_company_appears_once(self):
        raw = json.loads(DATA_FILE.read_text())
        names = [entry["company"].casefold() for entry in raw["companies"]]
        self.assertEqual(len(names), len(set(names)))

    def test_every_bundled_company_has_expectations(self):
        if not BUNDLED_CSVS.is_dir():
            self.skipTest("frontend resources not checked out")
        bundled = {path.stem for path in BUNDLED_CSVS.glob("*.csv")}
        self.assertEqual(bundled - set(company_names()), set())

    def test_every_company_has_something_to_interview_on(self):
        for name in company_names():
            company = find_company(name)
            assert company is not None
            self.assertTrue(company.interview_expectations, name)
            self.assertTrue(company.principles, name)
            self.assertEqual(bool(company.values), bool(company.values_label), name)

    def test_amazon_has_all_sixteen_leadership_principles(self):
        amazon = find_company(" amazon ")
        assert amazon is not None
        self.assertEqual(amazon.values_label, "Leadership Principles")
        self.assertEqual(len(amazon.values), 16)
        self.assertIn("Dive Deep", [value.name for value in amazon.values])


class CompanyPromptTests(unittest.TestCase):

    def test_hr_round_uses_the_company_principles(self):
        prompt = opening_prompt("SDE", InterviewMode.HR, {"company": "Amazon"})
        self.assertIn("THE COMPANY: Amazon", prompt)
        self.assertIn("Leadership Principles", prompt)
        self.assertIn("Have Backbone; Disagree and Commit", prompt)
        self.assertIn("at Amazon", prompt)

    def test_general_round_has_no_company(self):
        prompt = opening_prompt("SDE", InterviewMode.HR, {})
        self.assertNotIn("THE COMPANY", prompt)

    def test_technical_round_sets_the_bar_without_the_values_list(self):
        prompt = opening_prompt("SDE", InterviewMode.CORE_CS, {"company": "Amazon"})
        self.assertIn("THE COMPANY: Amazon", prompt)
        self.assertIn("The 'Bar Raiser' Standard", prompt)
        self.assertNotIn("Strive to be Earth's Best Employer", prompt)

    def test_debate_ignores_the_company(self):
        prompt = opening_prompt("SDE", InterviewMode.PANEL_DEBATE, {"company": "Amazon"})
        self.assertNotIn("THE COMPANY", prompt)

    def test_dsa_pool_is_described_as_the_company_most_asked(self):
        context = {"company": "Amazon", "dsa_problems": {"easy": ["Two Sum"]}}
        prompt = opening_prompt("SDE", InterviewMode.DSA_APPROACH, context)
        self.assertIn("the problems Amazon asks most often", prompt)
        self.assertIn("Two Sum", prompt)

    def test_unknown_company_falls_back_to_its_name(self):
        prompt = opening_prompt("SDE", InterviewMode.HR, {"company": "Initech"})
        self.assertIn("THE COMPANY: Initech", prompt)
        self.assertIn("published values", prompt)

    def test_hr_round_cannot_close_before_covering_the_principles(self):
        transcript = []
        for number in range(MIN_QUESTIONS):
            transcript.append({"speaker": "ai", "text": f"Q{number}", "level": 3})
            transcript.append({"speaker": "user", "text": "An answer.", "accuracy": 2, "ease": 1})
        plan = plan_next_turn(RoundState.from_transcript(InterviewMode.HR, transcript))
        self.assertTrue(plan.may_close)
        prompt = follow_up_prompt(
            "SDE", InterviewMode.HR, {"company": "Amazon"}, transcript, "answer", plan
        )
        self.assertIn("four of Amazon's Leadership Principles", prompt)
        general = follow_up_prompt("SDE", InterviewMode.HR, {}, transcript, "answer", plan)
        self.assertNotIn("Leadership Principles", general)

    def test_feedback_judges_against_the_company(self):
        prompt = feedback_prompt("SDE", InterviewMode.HR, TRANSCRIPT, {"company": "Amazon"})
        self.assertIn("Amazon's HR round", prompt)
        self.assertIn("Customer Obsession", prompt)
        self.assertNotIn("Amazon", feedback_prompt("SDE", InterviewMode.HR, TRANSCRIPT))


class CompanyRouteTests(unittest.TestCase):

    def setUp(self):
        handle, self.path = tempfile.mkstemp(suffix=".db")
        os.close(handle)
        url = f"sqlite:///{self.path}"
        self.engine = create_engine(url, connect_args={"check_same_thread": False})
        self.patches = [
            mock.patch.object(db, "engine", self.engine),
            mock.patch.object(db, "DATABASE_URL", url),
            mock.patch.object(interview_routes, "generate_first_question", return_value="Hi."),
        ]
        for patch in self.patches:
            patch.start()

    def tearDown(self):
        for patch in self.patches:
            patch.stop()
        self.engine.dispose()
        os.remove(self.path)

    def test_company_is_normalised_and_returned(self):
        with TestClient(app) as client:
            with Session(self.engine) as session:
                user = User(email="a@example.com", hashed_password=hash_password("password123"))
                session.add(user)
                session.commit()
                session.refresh(user)
                user_id = user.id
            headers = {"Authorization": f"Bearer {create_access_token(str(user_id))}"}

            response = client.post(
                "/api/interview/start",
                json={"target_role": "SDE", "mode": "hr", "context": {"company": " amazon "}},
                headers=headers,
            )
            self.assertEqual(response.status_code, 200)
            session_id = response.json()["session_id"]

            response = client.get(f"/api/interview/{session_id}", headers=headers)
            self.assertEqual(response.json()["company"], "Amazon")


if __name__ == "__main__":
    unittest.main()
