#!/usr/bin/env python3
"""
Validates every quiz JSON in PlacementPrep/Resources/Quizzes.

Crucially this cross-checks the `category`, `subject` and `difficulty` strings
against the actual Swift enums in QuizBankModels.swift. A structurally perfect
JSON file with a value the enum does not declare still fails to decode at run
time, and the app can only report it as a load error after the fact.

Also checks: option ids are exactly A-D, the answer key names a real option,
option texts are distinct, ids and prompts are unique across the whole bank,
orders do not collide within a category, and the A-D answer spread is not so
skewed that guessing pays.

Usage:  python3 Scripts/validate-quizzes.py
Exit code is non-zero if anything fails, so it can gate a commit.
"""

import collections
import glob
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MODELS = os.path.join(ROOT, "PlacementPrep", "Models", "QuizBankModels.swift")
QUIZZES = os.path.join(ROOT, "PlacementPrep", "Resources", "Quizzes", "*.json")


def swift_enum_values(source, name):
    """Raw values of a String-backed Swift enum.

    Handles both `case a = "x"` and the comma form `case a, b, c` — missing the
    latter is exactly the kind of gap that makes a validator quietly useless.
    """
    match = re.search(r"enum\s+%s\s*:[^{]*\{(.*?)\n\}" % name, source, re.S)
    if not match:
        sys.exit(f"could not find enum {name} in {MODELS}")

    values = []
    for line in match.group(1).splitlines():
        line = line.split("//")[0].strip()
        if not line.startswith("case "):
            continue
        for item in line[len("case "):].split(","):
            item = item.strip()
            if not item:
                continue
            explicit = re.match(r'(\w+)\s*=\s*"([^"]+)"', item)
            if explicit:
                values.append(explicit.group(2))
            elif re.fullmatch(r"\w+", item):
                values.append(item)
    return values


def main():
    source = open(MODELS).read()
    categories = swift_enum_values(source, "Category")
    subjects = swift_enum_values(source, "Subject")
    difficulties = swift_enum_values(source, "Difficulty")

    problems = []
    quiz_ids = collections.Counter()
    question_ids = collections.Counter()
    prompts = collections.Counter()
    orders = collections.defaultdict(collections.Counter)
    keys = collections.Counter()
    total = 0

    files = sorted(glob.glob(QUIZZES))
    if not files:
        sys.exit("no quiz files found")

    for path in files:
        name = os.path.basename(path)
        try:
            quiz = json.load(open(path))
        except json.JSONDecodeError as exc:
            problems.append(f"{name}: invalid JSON — {exc}")
            continue

        # Enum cross-check — the failure mode that only shows up at run time.
        if quiz.get("category") not in categories:
            problems.append(f"{name}: category {quiz.get('category')!r} is not a Category case")
        if "subject" in quiz and quiz["subject"] not in subjects:
            problems.append(f"{name}: subject {quiz['subject']!r} is not a Subject case")
        if quiz.get("difficulty") not in difficulties:
            problems.append(f"{name}: difficulty {quiz.get('difficulty')!r} is not a Difficulty case")

        quiz_ids[quiz.get("id")] += 1
        orders[quiz.get("category")][quiz.get("order")] += 1

        for question in quiz.get("questions", []):
            total += 1
            qid = question.get("id", "?")
            question_ids[qid] += 1
            prompts[question.get("prompt", "").strip().lower()] += 1

            option_ids = [o["id"] for o in question.get("options", [])]
            if sorted(option_ids) != list("ABCD"):
                problems.append(f"{name}/{qid}: option ids {option_ids}, expected A-D")
            if question.get("correct_option_id") not in option_ids:
                problems.append(f"{name}/{qid}: answer key names no existing option")
            if len({o["text"] for o in question.get("options", [])}) != len(option_ids):
                problems.append(f"{name}/{qid}: duplicate option text")
            if "difficulty" in question:
                problems.append(f"{name}/{qid}: per-question difficulty is obsolete")
            for field in ("prompt", "explanation", "concept"):
                if not question.get(field):
                    problems.append(f"{name}/{qid}: empty {field}")
            keys[question.get("correct_option_id")] += 1

    problems += [f"duplicate quiz id {k}" for k, v in quiz_ids.items() if v > 1]
    problems += [f"duplicate question id {k}" for k, v in question_ids.items() if v > 1]
    problems += [f"duplicate prompt: {k[:60]}..." for k, v in prompts.items() if v > 1]
    for category, counts in orders.items():
        problems += [f"{category}: order {o} used {n} times"
                     for o, n in counts.items() if n > 1]

    # A heavy skew lets a student beat the pass mark by always picking one letter.
    if total:
        worst = max(keys.values()) / total
        if worst > 0.35:
            problems.append(f"answer key skew: one letter is {worst:.0%} of all answers")

    print(f"{len(files)} quiz files, {total} questions")
    print(f"answer spread: {dict(sorted(keys.items()))}")
    if problems:
        print(f"\n{len(problems)} PROBLEM(S):")
        for p in problems:
            print(f"  {p}")
        sys.exit(1)
    print("all checks passed")


if __name__ == "__main__":
    main()
