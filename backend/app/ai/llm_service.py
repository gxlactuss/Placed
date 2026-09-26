import json
import logging
import re
from typing import NamedTuple

import google.generativeai as genai
import httpx
from fastapi import HTTPException

from app.core.config import settings
from app.ai.interview_difficulty import (
    MIN_QUESTIONS,
    Assessment,
    TurnPlan,
    cap_ease_for_pause,
    split_assessment,
)
from app.ai.interview_prompts import (
    END_INTERVIEW_SENTINEL,
    ROUND_COMPLETE_SENTINEL,
    RUBRIC_DIMENSIONS,
    InterviewMode,
    feedback_prompt,
    follow_up_prompt,
    opening_prompt,
)
from app.ai.interview_rounds import SeedQuestion, spec_for
from app.ai.quiz_prompts import quiz_summary_prompt
from app.ai.resume_checks import DeviceFacts, ResumeSignals
from app.ai.resume_prompts import FACTOR_WEIGHTS, resume_review_prompt

genai.configure(api_key=settings.gemini_api_key)

logger = logging.getLogger(__name__)

_TIMEOUT = 60.0

_THINK_BLOCK = re.compile(r"<think>.*?</think>", re.DOTALL | re.IGNORECASE)
_UNCLOSED_THINK = re.compile(r"<think>.*", re.DOTALL | re.IGNORECASE)


def _strip_reasoning(text: str) -> str:
    return _UNCLOSED_THINK.sub("", _THINK_BLOCK.sub("", text)).strip()


class _QuotaExhausted(Exception):
    pass


class _AuthRejected(Exception):
    pass

def _call_groq(model: str, prompt: str, temperature: float | None) -> str:
    body: dict = {"model": model, "messages": [{"role": "user", "content": prompt}]}
    if temperature is not None:
        body["temperature"] = temperature
    response = httpx.post(
        f"{settings.groq_base_url}/chat/completions",
        headers={"Authorization": f"Bearer {settings.groq_api_key}"},
        json=body,
        timeout=_TIMEOUT,
    )
    if response.status_code in (413, 429):
        raise _QuotaExhausted(response.text[:200])
    if response.status_code in (401, 403):
        raise _AuthRejected(response.text[:200])
    if response.status_code == 404:
        raise _QuotaExhausted(f"unknown model {model}")
    response.raise_for_status()
    return _strip_reasoning(response.json()["choices"][0]["message"]["content"])


def transcribe_audio(data: bytes, filename: str, content_type: str | None) -> str:
    if not settings.groq_api_key:
        raise HTTPException(status_code=503, detail="Voice transcription is not configured.")

    try:
        response = httpx.post(
            f"{settings.groq_base_url}/audio/transcriptions",
            headers={"Authorization": f"Bearer {settings.groq_api_key}"},
            files={"file": (filename, data, content_type or "application/octet-stream")},
            data={"model": settings.groq_transcription_model, "response_format": "json"},
            timeout=120.0,
        )
    except httpx.HTTPError as exc:
        logger.exception("Transcription transport failure")
        raise HTTPException(
            status_code=502, detail="Couldn't reach the transcription service."
        ) from exc

    if response.status_code == 429:
        raise HTTPException(
            status_code=503,
            detail="Voice transcription has hit its usage limit for now. Try again shortly.",
        )
    if response.status_code in (401, 403):
        logger.error("Groq rejected our key for transcription")
        raise HTTPException(status_code=503, detail="Voice transcription is not configured.")
    if response.status_code >= 400:
        logger.error("Transcription failed (%s): %s", response.status_code, response.text[:300])
        raise HTTPException(status_code=502, detail="Couldn't transcribe that recording.")

    return response.json().get("text", "").strip()


def _call_gemini(model: str, prompt: str, temperature: float | None) -> str:
    config = {"temperature": temperature} if temperature is not None else None
    try:
        return (
            genai.GenerativeModel(model)
            .generate_content(prompt, generation_config=config)
            .text.strip()
        )
    except Exception as exc:
        text = str(exc)
        if "429" in text or "RESOURCE_EXHAUSTED" in text or "exceeded your current quota" in text:
            raise _QuotaExhausted(text[:200]) from exc
        raise


_PROVIDERS = {"groq": _call_groq, "gemini": _call_gemini}

def _generate(prompt: str, temperature: float | None = None) -> str:
    chain = settings.llm_chain
    if not chain:
        raise HTTPException(status_code=503, detail="Interview service is not configured.")

    exhausted: list[str] = []
    dead_providers: set[str] = set()

    for provider, model in chain:
        if provider in dead_providers:
            continue
        try:
            return _PROVIDERS[provider](model, prompt, temperature)
        except _QuotaExhausted as exc:
            exhausted.append(f"{provider}/{model}")
            logger.warning("LLM quota exhausted for %s/%s (%s), trying next", provider, model, exc)
            continue
        except _AuthRejected as exc:
            dead_providers.add(provider)
            exhausted.append(f"{provider}/* (auth rejected)")
            logger.error("LLM provider %s rejected our key: %s", provider, exc)
            continue
        except Exception as exc:
            logger.exception("LLM call failed on %s/%s", provider, model)
            raise HTTPException(
                status_code=502,
                detail="The interview service is having trouble right now. Please try again.",
            ) from exc

    logger.error("Every LLM provider/model exhausted: %s", ", ".join(exhausted))
    raise HTTPException(
        status_code=503,
        detail=(
            "The interview service has hit its usage limit for now. "
            "Please try again in a few minutes."
        ),
    )


def generate_first_question(
    target_role: str,
    mode: InterviewMode,
    context: dict | None = None,
    seed: SeedQuestion | None = None,
) -> str:
    reply = _generate(opening_prompt(target_role, mode, context or {}, seed))
    return split_assessment(reply)[1]

NO_PROJECTS_SENTINEL = "NO_PROJECTS_FOUND"


def summarize_projects(target_role: str, projects_text: str) -> tuple[str, bool]:
    prompt = (
        f"You are preparing to interview a candidate for a '{target_role}' role.\n"
        f"Below is the projects section of their resume, extracted on-device by "
        f"OCR — expect noisy line breaks and the occasional misread character.\n\n"
        f"---\n{projects_text}\n---\n\n"
        f"Summarise every project you can identify. For each, give the project "
        f"name, one sentence on what it does, and the main technologies used. "
        f"Reply as a short bulleted list, one bullet per project, no preamble.\n"
        f"If the text contains no recognisable projects, reply with exactly: "
        f"{NO_PROJECTS_SENTINEL}"
    )
    summary = _generate(prompt)
    if NO_PROJECTS_SENTINEL in summary:
        return "", True
    return summary, False


class AnswerRubric(NamedTuple):
    answer: int
    scores: dict[str, int]
    score: float
    note: str
    level: int | None


class Feedback(NamedTuple):
    rating: int
    summary: str
    improvements: list[str]
    mistakes: list[str]
    rubric: dict[str, int] | None
    answers: list[AnswerRubric]


def _extract_json_object(raw: str) -> dict:
    start, end = raw.find("{"), raw.rfind("}")
    if start == -1 or end <= start:
        raise ValueError("no JSON object in reply")
    value = json.loads(raw[start : end + 1])
    if not isinstance(value, dict):
        raise ValueError("JSON was not an object")
    return value


def _clean_list(value, limit: int) -> list[str]:
    if not isinstance(value, list):
        return []
    items = [str(v).strip() for v in value if str(v).strip()]
    return items[:limit]


def _clamp_score(value) -> int | None:
    if isinstance(value, bool):
        return None
    try:
        number = round(float(value))
    except (TypeError, ValueError, OverflowError):
        return None
    return max(0, min(10, number))


def _rubric(value) -> dict[str, int] | None:
    if not isinstance(value, dict):
        return None
    if isinstance(value.get("scores"), dict):
        value = value["scores"]
    scores: dict[str, int] = {}
    for name in RUBRIC_DIMENSIONS:
        score = _clamp_score(value.get(name))
        if score is None:
            return None
        scores[name] = score
    return scores


_ANSWER_NUMBER = re.compile(r"\[?\s*A?\s*(\d+)\s*\]?", re.IGNORECASE)


def _answer_number(value) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value) if value.is_integer() else None
    match = _ANSWER_NUMBER.fullmatch(str(value).strip())
    return int(match.group(1)) if match else None


def _answer_levels(transcript: list[dict]) -> list[int | None]:
    levels: list[int | None] = []
    current: int | None = None
    for turn in transcript:
        if turn.get("speaker") == "user":
            levels.append(current)
        else:
            level = turn.get("level")
            current = level if isinstance(level, int) else None
    return levels


def _answer_rubrics(value, levels: list[int | None]) -> list[AnswerRubric]:
    if not isinstance(value, list):
        return []
    found: dict[int, AnswerRubric] = {}
    for entry in value:
        if not isinstance(entry, dict):
            continue
        number = _answer_number(entry.get("answer"))
        if number is None or not 1 <= number <= len(levels) or number in found:
            continue
        scores = _rubric(entry)
        if scores is None:
            continue
        found[number] = AnswerRubric(
            answer=number,
            scores=scores,
            score=round(sum(scores.values()) / len(scores), 1),
            note=str(entry.get("note", "")).strip(),
            level=levels[number - 1],
        )
    return [found[number] for number in sorted(found)]


def _mean_rubric(answers: list[AnswerRubric]) -> dict[str, int] | None:
    if not answers:
        return None
    return {
        name: round(sum(a.scores[name] for a in answers) / len(answers))
        for name in RUBRIC_DIMENSIONS
    }


def generate_feedback(
    target_role: str, mode: InterviewMode, transcript: list[dict], context: dict | None = None
) -> Feedback:
    prompt = feedback_prompt(target_role, mode, transcript, context)
    data: dict | None = None
    for _attempt in range(2):
        raw = _generate(prompt)
        try:
            data = _extract_json_object(raw)
            break
        except (ValueError, json.JSONDecodeError):
            logger.warning("Feedback reply was not usable JSON: %s", raw[:300])
    if data is None:
        raise HTTPException(
            status_code=502, detail="Couldn't put your results together. Try again in a moment."
        )

    try:
        rating = int(float(data.get("rating", 0)))
    except (TypeError, ValueError):
        rating = 0

    levels = _answer_levels(transcript)
    answers = _answer_rubrics(data.get("answers"), levels)
    if len(answers) < len(levels):
        logger.info("Feedback scored %d of %d answers", len(answers), len(levels))

    return Feedback(
        rating=max(0, min(10, rating)),
        summary=str(data.get("summary", "")).strip(),
        improvements=_clean_list(data.get("improvements"), limit=5),
        mistakes=_clean_list(data.get("mistakes"), limit=8),
        rubric=_rubric(data.get("rubric")) or _mean_rubric(answers),
        answers=answers,
    )


class QuizSummary(NamedTuple):
    summary: str
    focus: list[str]


def generate_quiz_summary(
    quiz_title: str,
    subject: str,
    score_percentage: int,
    correct_count: int,
    total_questions: int,
    missed: list[dict],
) -> QuizSummary:
    raw = _generate(
        quiz_summary_prompt(
            quiz_title, subject, score_percentage, correct_count, total_questions, missed
        )
    )
    try:
        data = _extract_json_object(raw)
    except (ValueError, json.JSONDecodeError) as exc:
        logger.warning("Quiz summary reply was not usable JSON: %s", raw[:300])
        raise HTTPException(
            status_code=502, detail="Couldn't put your summary together. Try again in a moment."
        ) from exc

    return QuizSummary(
        summary=str(data.get("summary", "")).strip(),
        focus=_clean_list(data.get("focus"), limit=4),
    )


class FactorScore(NamedTuple):
    key: str
    weight: int
    score: int
    reason: str


class ResumeReview(NamedTuple):
    overall: int
    factors: list[FactorScore]
    strengths: list[str]
    improvements: list[dict]
    rewrites: list[dict]


_PRIORITIES = ("high", "medium", "low")
_PLACEHOLDER = re.compile(r"\[[^\]]*\]")
_DIGITS = re.compile(r"\d+(?:\.\d+)?")
_QUOTES = str.maketrans({"\u2018": "'", "\u2019": "'", "\u201c": '"', "\u201d": '"'})


def _comparable(text: str) -> str:
    return " ".join(text.translate(_QUOTES).lower().split())


def _factors(value) -> list[FactorScore] | None:
    if not isinstance(value, dict):
        return None
    factors = []
    for key, weight in FACTOR_WEIGHTS.items():
        entry = value.get(key)
        detail = entry if isinstance(entry, dict) else {"score": entry}
        score = _clamp_score(detail.get("score"))
        if score is None:
            return None
        factors.append(FactorScore(key, weight, score, str(detail.get("reason", "")).strip()))
    return factors


def _improvements(value, limit: int) -> list[dict]:
    if not isinstance(value, list):
        return []
    items = []
    for entry in value:
        if not isinstance(entry, dict):
            continue
        issue = str(entry.get("issue", "")).strip()
        fix = str(entry.get("fix", "")).strip()
        if not issue or not fix:
            continue
        priority = str(entry.get("priority", "")).strip().lower()
        factor = str(entry.get("factor", "")).strip()
        items.append({
            "factor": factor if factor in FACTOR_WEIGHTS else None,
            "priority": priority if priority in _PRIORITIES else "medium",
            "section": str(entry.get("section", "")).strip(),
            "issue": issue,
            "fix": fix,
        })
        if len(items) == limit:
            break
    return sorted(items, key=lambda item: _PRIORITIES.index(item["priority"]))


def _invents_numbers(original: str, improved: str) -> bool:
    stated = set(_DIGITS.findall(original))
    return any(n not in stated for n in _DIGITS.findall(_PLACEHOLDER.sub("", improved)))


def _rewrites(value, resume_text: str, limit: int) -> list[dict]:
    if not isinstance(value, list):
        return []
    source = _comparable(resume_text)
    rewrites = []
    for entry in value:
        if not isinstance(entry, dict):
            continue
        original = str(entry.get("original", "")).strip().lstrip("•●▪◦·‣∙-–—* ")
        improved = str(entry.get("improved", "")).strip()
        if not original or not improved or _comparable(original) == _comparable(improved):
            continue
        if _comparable(original) not in source:
            logger.info("Dropped a rewrite whose original is not in the resume: %s", original[:80])
            continue
        if _invents_numbers(original, improved):
            logger.info("Dropped a rewrite that invented a number: %s", improved[:80])
            continue
        rewrites.append({
            "original": original,
            "improved": improved,
            "why": str(entry.get("why", "")).strip(),
        })
        if len(rewrites) == limit:
            break
    return rewrites


def generate_resume_review(
    target_role: str,
    resume_text: str,
    signals: ResumeSignals,
    device: DeviceFacts,
    already_reported: list[str],
) -> ResumeReview:
    prompt = resume_review_prompt(target_role, resume_text, signals, device, already_reported)
    for _attempt in range(2):
        raw = _generate(prompt, temperature=0)
        try:
            data = _extract_json_object(raw)
        except (ValueError, json.JSONDecodeError):
            logger.warning("Resume review reply was not usable JSON: %s", raw[:300])
            continue
        factors = _factors(data.get("factors"))
        if factors is None:
            logger.warning("Resume review reply had incomplete factors: %s", raw[:300])
            continue
        return ResumeReview(
            overall=round(sum(f.score * f.weight for f in factors) / 10),
            factors=factors,
            strengths=_clean_list(data.get("strengths"), limit=3),
            improvements=_improvements(data.get("improvements"), limit=6),
            rewrites=_rewrites(data.get("rewrites"), resume_text, limit=3),
        )

    raise HTTPException(
        status_code=502, detail="Couldn't review that resume. Try again in a moment."
    )


class FollowUp(NamedTuple):
    message: str
    complete: bool
    ended_early: bool
    assessment: Assessment


class _Reply(NamedTuple):
    assessment: Assessment
    message: str
    closed: bool
    ended_early: bool


def _read_reply(reply: str) -> _Reply:
    assessment, spoken = split_assessment(reply)
    ended_early = END_INTERVIEW_SENTINEL in spoken
    closed = ended_early or ROUND_COMPLETE_SENTINEL in spoken
    for sentinel in (END_INTERVIEW_SENTINEL, ROUND_COMPLETE_SENTINEL):
        spoken = spoken.replace(sentinel, "")
    return _Reply(assessment, spoken.strip(), closed, ended_early)


def generate_follow_up(
    target_role: str,
    mode: InterviewMode,
    context: dict | None,
    transcript: list[dict],
    latest_answer: str,
    plan: TurnPlan,
) -> FollowUp:
    prompt = follow_up_prompt(target_role, mode, context or {}, transcript, latest_answer, plan)
    reply = _read_reply(_generate(prompt))

    if reply.closed and not reply.ended_early and not plan.may_close:
        logger.warning("Model closed a round after %d answers; regenerating", plan.answered)
        reply = _read_reply(
            _generate(
                f"{prompt}\n\nYou tried to close the round, but they have given only "
                f"{plan.answered} answers and every round runs to at least {MIN_QUESTIONS}. "
                "Do not close it. Write your reply again, ending with your next question."
            )
        )
        if reply.closed and not reply.ended_early:
            logger.error("Model closed a round below the minimum twice; keeping it open")
            reply = reply._replace(closed=False)

    if reply.assessment.accuracy is None and reply.assessment.topic is None:
        logger.info("Follow-up carried no usable assessment line; holding the level")

    latest = next((t for t in reversed(transcript) if t.get("speaker") == "user"), {})
    assessment = cap_ease_for_pause(
        reply.assessment, latest.get("think_seconds"), spec_for(mode).long_pause_seconds
    )

    closed = reply.closed or plan.must_close
    message = reply.message
    if closed and not message:
        message = (
            "I'm going to stop the interview here. Let's try again another time."
            if reply.ended_early
            else "That's where we'll close this round. Thank you."
        )
    return FollowUp(message, closed, reply.ended_early, assessment)
