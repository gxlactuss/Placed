from __future__ import annotations

import random
import re
from dataclasses import dataclass
from enum import Enum

from app.ai.interview_mode import InterviewMode
from app.ai.interview_rounds import SeedQuestion, opens_with_seed, spec_for

MIN_QUESTIONS = 10
MAX_QUESTIONS = 50
CALIBRATION_QUESTIONS = 3

LOWEST_LEVEL = 1
START_LEVEL = 3
HIGHEST_LEVEL = 5

SETTLE_WINDOW = 4

IGNORED_PAUSE_SECONDS = 180


class Verdict(str, Enum):
    STRONG = "strong"
    ADEQUATE = "adequate"
    WEAK = "weak"


def verdict_for(accuracy: int | None, ease: int | None) -> Verdict:
    if accuracy is None:
        return Verdict.ADEQUATE
    score = 2 * accuracy + (1 if ease is None else ease)
    if score >= 7:
        return Verdict.STRONG
    if score <= 3:
        return Verdict.WEAK
    return Verdict.ADEQUATE


def step(level: int, verdict: Verdict) -> int:
    delta = {Verdict.STRONG: 1, Verdict.ADEQUATE: 0, Verdict.WEAK: -1}[verdict]
    return max(LOWEST_LEVEL, min(HIGHEST_LEVEL, level + delta))


def calibrated_level(verdicts: tuple[Verdict, ...]) -> int:
    net = sum({Verdict.STRONG: 1, Verdict.ADEQUATE: 0, Verdict.WEAK: -1}[v] for v in verdicts)
    if net >= 2:
        return START_LEVEL + 1
    if net <= -2:
        return START_LEVEL - 1
    return START_LEVEL

_ASSESS_LINE = re.compile(r"`*\[\[\s*ASSESS\b(?P<body>[^\]]*)\]\]`*", re.IGNORECASE)
_GRADE = re.compile(r"\b(accuracy|ease)\s*[=:]\s*([A-Za-z0-9/]+)", re.IGNORECASE)
_TOPIC = re.compile(r"\btopic\s*[=:]\s*", re.IGNORECASE)


@dataclass(frozen=True)
class Assessment:
    accuracy: int | None = None
    ease: int | None = None
    topic: str | None = None

    @property
    def verdict(self) -> Verdict:
        return verdict_for(self.accuracy, self.ease)


def _grade(raw: str | None, top: int) -> int | None:
    if raw is None:
        return None
    digits = raw.split("/")[0]
    if not digits.isdigit():
        return None
    return max(0, min(top, int(digits)))


def is_long_pause(think_seconds: object, long_pause_seconds: int) -> bool:
    return (
        isinstance(think_seconds, (int, float))
        and long_pause_seconds < think_seconds <= IGNORED_PAUSE_SECONDS
    )


def cap_ease_for_pause(
    assessment: Assessment, think_seconds: object, long_pause_seconds: int
) -> Assessment:
    if assessment.ease is None or assessment.ease <= 1:
        return assessment
    if not is_long_pause(think_seconds, long_pause_seconds):
        return assessment
    return Assessment(assessment.accuracy, 1, assessment.topic)


def split_assessment(reply: str) -> tuple[Assessment, str]:
    match = _ASSESS_LINE.search(reply)
    if not match:
        return Assessment(), reply.strip()

    body = match.group("body")
    topic_split = _TOPIC.split(body, maxsplit=1)
    grades = {name.lower(): value for name, value in _GRADE.findall(topic_split[0])}
    topic = topic_split[1].strip().strip("\"'").strip() if len(topic_split) > 1 else ""

    spoken = (reply[: match.start()] + reply[match.end() :]).strip()
    return (
        Assessment(
            accuracy=_grade(grades.get("accuracy"), 3),
            ease=_grade(grades.get("ease"), 2),
            topic=topic[:80] or None,
        ),
        spoken,
    )

@dataclass(frozen=True)
class RoundState:
    mode: InterviewMode
    answered: int
    level: int
    seeds_asked: tuple[str, ...]
    warm_up_verdicts: tuple[Verdict, ...]
    last_question_was_seed: bool
    adaptive_levels: tuple[int, ...]

    @classmethod
    def from_transcript(cls, mode: InterviewMode, transcript: list[dict]) -> "RoundState":
        answered = 0
        level = START_LEVEL
        seeds: list[str] = []
        warm_up: list[Verdict] = []
        adaptive: list[int] = []
        last_was_seed = False

        for turn in transcript:
            if turn.get("speaker") == "ai":
                raw_level = turn.get("level")
                level = raw_level if isinstance(raw_level, int) else level
                seed = turn.get("seed")
                last_was_seed = bool(seed)
                if seed:
                    seeds.append(seed)
                elif len(seeds) >= CALIBRATION_QUESTIONS:
                    adaptive.append(level)
            elif turn.get("speaker") == "user":
                answered += 1
                if last_was_seed and "accuracy" in turn:
                    warm_up.append(verdict_for(turn.get("accuracy"), turn.get("ease")))

        return cls(
            mode=mode,
            answered=answered,
            level=level,
            seeds_asked=tuple(seeds),
            warm_up_verdicts=tuple(warm_up),
            last_question_was_seed=last_was_seed,
            adaptive_levels=tuple(adaptive),
        )


@dataclass(frozen=True)
class TurnPlan:
    answered: int
    current_level: int
    seed: SeedQuestion | None
    warm_up_number: int | None
    finishes_warm_up: bool
    levels: dict[Verdict, int]
    may_close: bool
    must_close: bool
    is_final_question: bool
    settled_level: int | None
    recent_levels: tuple[int, ...]

    def level_for(self, verdict: Verdict) -> int:
        return self.levels[verdict]


def opening_seed(mode: InterviewMode, rng: random.Random | None = None) -> SeedQuestion | None:
    if not opens_with_seed(mode):
        return None
    return (rng or random).choice(spec_for(mode).seeds)


def plan_next_turn(state: RoundState, rng: random.Random | None = None) -> TurnPlan:
    choose = (rng or random).choice
    must_close = state.answered >= MAX_QUESTIONS

    seed: SeedQuestion | None = None
    if not must_close and len(state.seeds_asked) < CALIBRATION_QUESTIONS:
        unused = [s for s in spec_for(state.mode).seeds if s.id not in state.seeds_asked]
        seed = choose(unused) if unused else None

    finishes_warm_up = (
        seed is None
        and state.last_question_was_seed
        and len(state.seeds_asked) >= CALIBRATION_QUESTIONS
    )
    if seed is not None:
        levels = {v: START_LEVEL for v in Verdict}
    elif finishes_warm_up:
        levels = {v: calibrated_level(state.warm_up_verdicts + (v,)) for v in Verdict}
    else:
        levels = {v: step(state.level, v) for v in Verdict}

    recent = state.adaptive_levels[-SETTLE_WINDOW:]
    settled = (
        int(sum(recent) / len(recent) + 0.5)
        if len(recent) == SETTLE_WINDOW and max(recent) - min(recent) <= 1
        else None
    )

    return TurnPlan(
        answered=state.answered,
        current_level=state.level,
        seed=seed,
        warm_up_number=len(state.seeds_asked) + 1 if seed else None,
        finishes_warm_up=finishes_warm_up,
        levels=levels,
        may_close=state.answered >= MIN_QUESTIONS,
        must_close=must_close,
        is_final_question=state.answered == MAX_QUESTIONS - 1,
        settled_level=settled,
        recent_levels=recent,
    )
