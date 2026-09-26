import unittest

from app.ai.llm_service import _factors, _improvements, _rewrites
from app.ai.resume_checks import DeviceFacts, analyse, checks, drop_repeats, hard_failures

STRONG = """\
[redacted] | [redacted]
EDUCATION
B.Tech Computer Science, 2021 - 2025, CGPA 8.7
SKILLS
Python, FastAPI, PostgreSQL, Redis, Docker, AWS
PROJECTS
ChatNest - realtime chat
• Built a realtime chat service with FastAPI websockets and Redis pub/sub serving 1,200 daily users
• Reduced message latency by 40% by batching database writes
• Deployed on AWS ECS with a GitHub Actions pipeline that runs 180 tests in 3 minutes
EXPERIENCE
Backend Intern, May 2024 - July 2024
• Designed a caching layer that cut p95 API latency from 900 ms to 250 ms
• Migrated 3 cron jobs to a Celery queue, removing 2 hours of nightly downtime
INTERESTS
Chess and long-distance running
"""

WEAK = """\
Objective
I am a hardworking student looking for opportunities to grow.
Projects
Worked on a website using HTML, CSS and JavaScript.
Responsible for the backend of a college project in Java.
I made a calculator app in my free time.
Hobbies
Reading novels and watching movies with my friends on weekends.
"""

# PDF text layers often drop bullet glyphs and wrap long bullets onto a second line.
UNGLYPHED = """\
Education
B.E. Information Technology 2020 - 2024
Skills
Java, Spring Boot, MySQL
Projects
Developed an inventory service in Spring Boot that tracks
stock for 3 warehouses
Implemented role-based access with Spring Security for admin users
"""

DEVICE_OK = DeviceFacts(True, True, True, 1, True)
DEVICE_BAD = DeviceFacts(False, True, False, 2, False)


class AnalyseTests(unittest.TestCase):

    def test_strong_resume_signals(self):
        s = analyse(STRONG)
        self.assertEqual(s.sections, ("education", "experience", "projects", "skills"))
        self.assertEqual(len(s.bullets), 5)
        self.assertEqual(s.quantified_bullets, 5)
        self.assertEqual(s.action_verb_bullets, 5)
        self.assertEqual(s.first_person_count, 0)
        self.assertEqual(s.missing_core_sections, [])

    def test_weak_resume_signals(self):
        s = analyse(WEAK)
        self.assertEqual(s.sections, ("projects",))
        self.assertEqual(s.missing_core_sections, ["education", "skills"])
        self.assertEqual(len(s.bullets), 3, "the Hobbies line must not count as a project bullet")
        self.assertEqual(s.quantified_bullets, 0)
        self.assertEqual(s.action_verb_bullets, 0)
        self.assertEqual(s.first_person_count, 4)

    def test_years_are_not_metrics(self):
        s = analyse("Projects\n• Built a portfolio site during summer 2023 for my club\n")
        self.assertEqual(s.quantified_bullets, 0)

    def test_bullets_without_glyphs_fall_back_to_section_lines(self):
        s = analyse(UNGLYPHED)
        self.assertEqual(len(s.bullets), 2)
        self.assertIn("stock for 3 warehouses", s.bullets[0], "wrapped line joins its bullet")
        self.assertEqual(s.quantified_bullets, 1)
        self.assertEqual(s.action_verb_bullets, 2)


class CheckTests(unittest.TestCase):

    def test_strong_resume_passes_every_check(self):
        results = checks(analyse(STRONG), DEVICE_OK)
        self.assertEqual([c.key for c in results if not c.passed], [])

    def test_weak_resume_fails_the_right_checks(self):
        failed = {c.key for c in checks(analyse(WEAK), DEVICE_BAD) if not c.passed}
        self.assertEqual(
            failed,
            {"ats_readable", "email", "links", "length", "sections", "metrics",
             "action_verbs", "first_person"},
        )

    def test_hard_failures_are_high_priority(self):
        failures = hard_failures(analyse(WEAK), DEVICE_BAD)
        self.assertEqual([f["section"] for f in failures], ["Whole resume", "Header", "Education", "Skills"])
        self.assertTrue(all(f["priority"] == "high" for f in failures))
        self.assertEqual(hard_failures(analyse(STRONG), DEVICE_OK), [])

    def test_restated_hard_failures_are_dropped(self):
        failures = hard_failures(analyse(WEAK), DEVICE_BAD)
        model = [
            {"section": "Contact", "issue": "Email address is missing.", "fix": "Add one."},
            {"section": "Skills", "issue": "A Skills section is absent.", "fix": "Add a concise Skills list."},
            {"section": "Projects", "issue": "Bullets lack outcomes.", "fix": "Add a result to each."},
        ]
        self.assertEqual([i["section"] for i in drop_repeats(model, failures)], ["Projects"])
        self.assertEqual(len(drop_repeats(model, [])), 3)


class ReplyParsingTests(unittest.TestCase):

    def test_factors_require_all_five_and_clamp(self):
        full = {k: {"score": 7, "reason": "ok"} for k in ("role_fit", "impact", "depth", "clarity")}
        self.assertIsNone(_factors(full), "a missing factor makes the reply unusable")
        parsed = _factors({**full, "format": 14, "impact": {"score": "-2"}})
        self.assertIsNotNone(parsed)
        scores = {f.key: f.score for f in parsed}
        self.assertEqual(scores["format"], 10)
        self.assertEqual(scores["impact"], 0)
        self.assertIsNone(_factors({**full, "format": {"score": "lots"}}))
        self.assertIsNone(_factors("not a dict"))

    def test_improvements_default_and_sort(self):
        items = _improvements(
            [
                {"priority": "low", "issue": "a", "fix": "b", "factor": "clarity"},
                {"priority": "urgent", "issue": "c", "fix": "d", "factor": "vibes"},
                {"priority": "high", "issue": "e", "fix": "f"},
                {"priority": "high", "issue": "", "fix": "dropped"},
                "junk",
            ],
            limit=6,
        )
        self.assertEqual([i["issue"] for i in items], ["e", "c", "a"])
        self.assertEqual(items[1]["priority"], "medium")
        self.assertIsNone(items[1]["factor"])
        self.assertEqual(_improvements(None, limit=6), [])

    def test_rewrites_must_quote_the_resume_and_not_invent_numbers(self):
        rewrites = _rewrites(
            [
                {   # kept: quoted with a leading glyph and different spacing, placeholder only
                    "original": "•  Responsible for the backend of a  college project in Java.",
                    "improved": "Built the Java backend for a college project used by [N students].",
                    "why": "Leads with what they built.",
                },
                {   # dropped: not in the resume
                    "original": "Led a team of five engineers.",
                    "improved": "Led [N] engineers.",
                },
                {   # dropped: invents a number outside a placeholder
                    "original": "Worked on a website using HTML, CSS and JavaScript.",
                    "improved": "Built a website in HTML, CSS and JavaScript used by 500 visitors a month.",
                },
                {   # dropped: no change
                    "original": "I made a calculator app in my free time.",
                    "improved": "I made a calculator app in my free time.",
                },
            ],
            WEAK,
            limit=3,
        )
        self.assertEqual(len(rewrites), 1)
        self.assertEqual(
            rewrites[0]["original"], "Responsible for the backend of a  college project in Java."
        )


if __name__ == "__main__":
    unittest.main()
