"""Prompt construction for the post-quiz debrief.

Split from `interview_prompts` for the same reason that module exists at all:
this is *content*, edited far more often than the code that sends it. The two
don't share wording — an interview reply is spoken aloud and must be plain
speech, while this is rendered as a report and asks for JSON.
"""

from __future__ import annotations


def quiz_summary_prompt(
    quiz_title: str,
    subject: str,
    score_percentage: int,
    correct_count: int,
    total_questions: int,
    missed: list[dict],
) -> str:
    """Turns the questions a student got wrong into a debrief they can act on.

    `missed` carries the whole question — prompt, what they picked, the right
    answer, and the concept tag — because a summary written from concept names
    alone ("revise Arrays") is exactly the raw-data restatement this is meant to
    replace.
    """
    if missed:
        detail = "\n\n".join(
            f"Question: {item.get('prompt', '').strip()}\n"
            f"They answered: {item.get('chosen_text') or 'nothing — left it blank'}\n"
            f"Correct answer: {item.get('correct_text', '').strip()}\n"
            f"Concept: {item.get('concept', '').strip()}"
            for item in missed
        )
        body = f"They got these wrong:\n---\n{detail}\n---"
    else:
        # A clean sweep still gets a debrief; it just has nothing to correct.
        body = "They answered every question correctly."

    return f"""A student has just finished a practice quiz and needs to know what to do about the result.

Quiz: {quiz_title} ({subject})
Score: {correct_count} out of {total_questions} ({score_percentage}%)

{body}

Write them a short debrief. Address them directly as "you".

What matters here:
- Find the pattern across what they missed. If several wrong answers share a root cause — one confused definition, one formula applied backwards, one step consistently skipped — say that, because it is the single most useful thing you can tell them and they cannot see it themselves from a list of ticks and crosses.
- Never simply restate which questions were wrong. They already have that on screen. Explain WHY the right answer is right, in a way that transfers to the next question of that kind.
- If they only made careless slips on material they clearly know, say so plainly rather than prescribing revision they don't need.
- If they got everything right, say what the result actually demonstrates and what to try next, and do not invent a weakness.
- Be encouraging but never inflate. A student who is weak on a topic is best served by being told.

Reply with ONLY a JSON object and nothing else — no markdown fence, no commentary before or after. Exactly this shape:
{{"summary": "<2 to 3 sentences on how it went and the pattern behind the mistakes>", "focus": ["<one specific thing to revise, and what about it>", "..."]}}

Give one to four focus entries, each a single sentence that stands on its own on a
results screen. Give an empty list if there is genuinely nothing to revise."""
