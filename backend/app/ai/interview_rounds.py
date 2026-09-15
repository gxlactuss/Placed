from __future__ import annotations

from dataclasses import dataclass

from app.ai.interview_mode import InterviewMode


@dataclass(frozen=True)
class SeedQuestion:
    id: str
    topic: str
    text: str


@dataclass(frozen=True)
class RoundSpec:
    seeds: tuple[SeedQuestion, ...]
    tailored: bool
    ladder: tuple[str, str, str, str, str]
    accuracy_means: str
    conclusion: str
    long_pause_seconds: int
    turn_noun: str = "question"


_HR = RoundSpec(
    seeds=(
        SeedQuestion(
            "hr-conflict",
            "Teamwork: disagreement",
            "Tell me about a time you disagreed with a teammate about how something should "
            "be done. What did you do, and how did it end?",
        ),
        SeedQuestion(
            "hr-setback",
            "Failure and learning",
            "Tell me about something you worked hard on that did not go the way you wanted. "
            "What went wrong, and what would you do differently now?",
        ),
        SeedQuestion(
            "hr-motivation",
            "Motivation for the role",
            "Why {role}? What have you already done that makes you think you would be good at it?",
        ),
        SeedQuestion(
            "hr-pressure",
            "Working under pressure",
            "Tell me about a time you had more to do than you had time for. How did you "
            "decide what to drop?",
        ),
    ),
    tailored=False,
    ladder=(
        "Warm, open prompts answerable from everyday experience, with no pressure on the "
        "example they give.",
        "Standard behavioural questions, accepting any reasonable example without probing it.",
        "Standard behavioural questions, then one push for a concrete detail: what they "
        "personally did, and how it turned out.",
        "Probe the example hard: challenge the parts that sound rehearsed, ask what it cost "
        "them, and ask for a result they can actually point to.",
        "Situational dilemmas with no clean answer — a manager asking them to cut a corner, "
        "two commitments they cannot both keep — and pressing on inconsistencies between "
        "their earlier answers.",
    ),
    accuracy_means=(
        "a specific, real, relevant example that says what they personally did and how it "
        "turned out, rather than generalities or a rehearsed script"
    ),
    conclusion=(
        "you have heard a specific, real example for each of: why they want this role, "
        "working with others or through conflict, a failure or setback, their strengths and "
        "weaknesses, and working under pressure — and pushing further would only repeat "
        "ground already covered"
    ),
    long_pause_seconds=8,
)

_CORE_CS = RoundSpec(
    seeds=(
        SeedQuestion(
            "cs-process-thread",
            "OS: processes and threads",
            "What is the difference between a process and a thread, and when would you pick "
            "one over the other?",
        ),
        SeedQuestion(
            "cs-index",
            "DBMS: indexing",
            "Why does adding an index make some database queries faster, and what does that "
            "index cost you?",
        ),
        SeedQuestion(
            "cs-tcp-udp",
            "Networks: TCP and UDP",
            "When would you choose UDP over TCP, and what do you give up by doing it?",
        ),
        SeedQuestion(
            "cs-composition",
            "OOP: composition and inheritance",
            "When would you use composition instead of inheritance? Give me an example where "
            "inheritance would have been the wrong choice.",
        ),
    ),
    tailored=False,
    ladder=(
        "Definitions and basic distinctions — what a primary key is, what an operating "
        "system is for.",
        "How a standard mechanism works, in their own words — paging, normal forms, the TCP "
        "handshake.",
        "Compare and justify: why one mechanism over another, and what it costs.",
        "Apply it to a concrete scenario they must reason through — two transactions at a "
        "given isolation level, a process thrashing under memory pressure — and explain why "
        "it behaves that way.",
        "Internals, failure modes and trade-offs with no single right answer — how a B+ tree "
        "stays balanced, why congestion control backs off the way it does, how they would "
        "design around a race.",
    ),
    accuracy_means="technically correct and complete for the level asked, with the reasoning and not just the conclusion",
    conclusion=(
        "you have asked about each of operating systems, DBMS, computer networks and OOP at "
        "least once, and you know roughly where their ceiling is — the difficulty has "
        "settled rather than still climbing or falling"
    ),
    long_pause_seconds=12,
)

_TECH_STACK = RoundSpec(
    seeds=(
        SeedQuestion(
            "ts-choice",
            "Choosing a technology",
            "Why did you choose <a technology they list> over the obvious alternative, and "
            "what would have been different if you had gone the other way?",
        ),
        SeedQuestion(
            "ts-debugging",
            "Debugging",
            "Tell me about the bug in <a technology they list> that took you longest to track "
            "down. How did you find it?",
        ),
        SeedQuestion(
            "ts-limits",
            "Limits of the tool",
            "What does <a technology they list> do badly, and how have you worked around it?",
        ),
        SeedQuestion(
            "ts-under-the-hood",
            "Under the hood",
            "Walk me through what actually happens when <a common operation in a technology "
            "they list> runs.",
        ),
    ),
    tailored=True,
    ladder=(
        "What the tool is for and how they use it day to day.",
        "How a core feature they use works, at the depth of its documentation.",
        "Why and how: a choice they made with it, a bug they fixed, and what it does badly.",
        "Internals and failure modes: what happens underneath, performance, concurrency, "
        "what breaks under load.",
        "Senior-level judgement: designing with the tool at scale, migrating off it, and "
        "trade-offs between approaches where both are defensible.",
    ),
    accuracy_means="technically correct, and specific enough to show they have really used the tool rather than read about it",
    conclusion=(
        "you have tested at least three distinct areas drawn from the role and their skills, "
        "found how deep they go in each, and the difficulty has settled"
    ),
    long_pause_seconds=12,
)

_PROJECTS = RoundSpec(
    seeds=(
        SeedQuestion(
            "pj-decision",
            "Design decisions",
            "What was the biggest technical decision in <a named project>, and what did you "
            "reject to make it?",
        ),
        SeedQuestion(
            "pj-ownership",
            "Personal contribution",
            "Which part of <a named project> did you personally build, and what was hardest "
            "about it?",
        ),
        SeedQuestion(
            "pj-breakage",
            "What broke",
            "What broke in <a named project>, and how did you find out?",
        ),
        SeedQuestion(
            "pj-scale",
            "Scaling",
            "If <a named project> suddenly had a hundred times the users, what would fail first?",
        ),
    ),
    tailored=True,
    ladder=(
        "What the project does, who it is for, and what they built in it.",
        "How one part of it works, walked through end to end.",
        "Decisions and trade-offs: why that design, what they rejected, what broke.",
        "Verification: how a claimed number was measured, the hardest bug in full detail, "
        "what they would rebuild.",
        "Stress it: what fails under heavy load, where the security holes are, and how they "
        "would redesign it knowing what they know now.",
    ),
    accuracy_means="specific, technically sound and clearly their own work, rather than a description anyone could read off the README",
    conclusion=(
        "every project that matters for this role (up to three) has been questioned on its "
        "decisions, their personal contribution and what broke, and any number they claimed "
        "has been checked"
    ),
    long_pause_seconds=10,
)

_DSA = RoundSpec(
    seeds=(
        SeedQuestion(
            "dsa-subarray-sum",
            "Arrays and hashing: subarray sum",
            "Given an array of integers and a number k, how would you count the subarrays that "
            "sum to k in better than quadratic time? Talk me through the idea, not the code.",
        ),
        SeedQuestion(
            "dsa-longest-substring",
            "Sliding window: longest substring",
            "How would you find the length of the longest substring without repeating "
            "characters, and what is the time complexity of your approach?",
        ),
        SeedQuestion(
            "dsa-islands",
            "Graphs: number of islands",
            "Given a grid of land and water, how would you count the islands? Which traversal "
            "would you use, and why that one?",
        ),
        SeedQuestion(
            "dsa-merge-intervals",
            "Sorting: merge intervals",
            "Given a list of meetings as start and end times, how would you merge the ones "
            "that overlap, and why does sorting first make that work?",
        ),
    ),
    tailored=False,
    ladder=(
        "An easy problem — a single pass or a hash map lookup — with a hint as soon as they stall.",
        "An easy problem, asking for its complexity and one edge case, with hints only if they stall for a while.",
        "A medium problem: a brute-force approach first, then a better one, with its complexity.",
        "A hard problem, or a medium one with a constraint that breaks their first approach — "
        "streaming input, constant extra memory. A hint only when they are fully stuck.",
        "A hard problem taken to an optimal approach, with why it is correct and the edge "
        "cases that break naive versions. No hints.",
    ),
    accuracy_means="a correct approach with the right complexity, justified rather than recited",
    conclusion=(
        "after the warm-up they have talked at least two problems all the way through — "
        "approach, improvement, complexity and edge cases — and the difficulty has settled"
    ),
    long_pause_seconds=30,
)

_PANEL_DEBATE = RoundSpec(
    seeds=(
        SeedQuestion(
            "gd-evidence",
            "Challenge: evidence",
            "The opponent asks what their last claim is actually based on, and wants one "
            "concrete example.",
        ),
        SeedQuestion(
            "gd-cost",
            "Challenge: who pays",
            "The opponent asks who loses out if things go the candidate's way, and why that is "
            "acceptable.",
        ),
        SeedQuestion(
            "gd-counterexample",
            "Challenge: counterexample",
            "The opponent raises a well-known real-world case that cuts against the candidate's "
            "position and asks how it fits.",
        ),
        SeedQuestion(
            "gd-line",
            "Challenge: where to draw the line",
            "The opponent asks where exactly the candidate would draw the line — what would "
            "have to be true for them to change their mind.",
        ),
    ),
    tailored=True,
    ladder=(
        "The opponent is agreeable: asks them to explain or expand a point and concedes readily.",
        "The opponent disagrees politely and asks for a reason or an example.",
        "The opponent pushes back on each claim, asks for evidence and offers a common counterpoint.",
        "The opponent attacks the premise, brings a specific counterexample, and holds ground "
        "unless the rebuttal is genuinely good.",
        "The opponent argues at full strength: makes the best case for their own side, "
        "exposes contradictions with what the candidate said earlier, and forces them to "
        "concede or defend a trade-off.",
    ),
    accuracy_means="a clear position backed by a reason, that actually answers what the opponent just said",
    conclusion=(
        "the topic has been argued from both sides, the candidate's main position has met "
        "the strongest counterargument and they have answered it, and further exchanges would "
        "only repeat points already made"
    ),
    long_pause_seconds=8,
    turn_noun="point from the opponent",
)


ROUNDS: dict[InterviewMode, RoundSpec] = {
    InterviewMode.HR: _HR,
    InterviewMode.CORE_CS: _CORE_CS,
    InterviewMode.TECH_STACK: _TECH_STACK,
    InterviewMode.PROJECTS: _PROJECTS,
    InterviewMode.DSA_APPROACH: _DSA,
    InterviewMode.PANEL_DEBATE: _PANEL_DEBATE,
}


def spec_for(mode: InterviewMode) -> RoundSpec:
    return ROUNDS[mode]


def opens_with_seed(mode: InterviewMode) -> bool:
    return mode is not InterviewMode.PANEL_DEBATE
