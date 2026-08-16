#!/usr/bin/env python3
"""
Randomises which option letter holds the answer, across every quiz JSON.

The bank was authored with the answer key walking A, B, C, D, A, B, C, D down
the question list. That is invisible in any single question and obvious over a
whole quiz — a student who notices it can clear the pass mark without reading a
prompt. This rewrites each question's four option *texts* onto a fresh
arrangement of the A-D ids and moves `correct_option_id` with the answer.

Option **ids stay A-D and stay in that order**; only the text under each id
moves. That matters because the ids are the persistence and answer keys (see
`Question.correctOptionID` in QuizBankModels.swift) — nothing downstream keys
off an option's position, so a saved score or a bookmarked question survives
this untouched.

Two questions are left exactly as authored:

  * anything whose options refer to other options by letter ("Both A and B") or
    to their own position ("All of the above") — moving those breaks the text;
  * anything already carrying a hand-placed arrangement we would only undo.

The target letters are dealt from a balanced deck rather than sampled
independently, so each quiz keeps a roughly even A/B/C/D spread, and the result
is re-rolled until it trips none of the pattern checks in `validate-quizzes.py`
(no cycling run, no long same-letter run).

Usage:  python3 Scripts/shuffle-quiz-answers.py [--seed N] [--dry-run]

Deterministic for a given seed, so a re-run reproduces the same bank and the
diff can be reviewed rather than taken on trust.
"""

import argparse
import glob
import json
import os
import random
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
QUIZZES = os.path.join(ROOT, "PlacementPrep", "Resources", "Quizzes", "*.json")

IDS = ["A", "B", "C", "D"]

# Options that name a letter or a position cannot be moved without lying.
POSITIONAL = re.compile(
    r"(of the above)|(\b(both|either|neither|options?|answers?)\b[^.]{0,20}\b[ABCD]\b\s*(and|,|&|or)\s*\b[ABCD]\b)",
    re.I,
)


def is_positional(question):
    return any(POSITIONAL.search(option["text"]) for option in question["options"])


def has_pattern(letters):
    """True if the answer key reads as a pattern rather than as noise.

    Two shapes matter, and they are the two `validate-quizzes.py` rejects: a
    cycle (each answer one letter on from the last, wrapping D->A, in either
    direction) running five deep, and the same letter four times over.
    """
    steps = [(IDS.index(b) - IDS.index(a)) % 4 for a, b in zip(letters, letters[1:])]

    run = 0
    for i, step in enumerate(steps):
        run = run + 1 if i and steps[i - 1] == step else 1
        # 4 identical steps span 5 answers: ABCDA, or DCBAD, or AAAA.
        if run >= 4 and step in (0, 1, 3):
            return True
        # 3 identical answers in a row is already a tell.
        if run >= 2 and step == 0:
            return True
    return False


def deal(rng, slots, fixed):
    """Answer letters for the open `slots`, balanced across A-D.

    `fixed` maps the positions we are not allowed to touch to the letters they
    already hold. The pattern check runs over the merged sequence, because a
    run that a left-alone question completes is still a run the student sees.
    """
    count = len(slots)
    for _ in range(400):
        deck = []
        while len(deck) < count:
            round_ = IDS[:]
            rng.shuffle(round_)
            deck += round_
        deck = deck[:count]
        rng.shuffle(deck)

        merged = dict(fixed)
        merged.update(zip(slots, deck))
        if not has_pattern([merged[i] for i in sorted(merged)]):
            return deck
    sys.exit("could not deal a pattern-free answer key")


def shuffle_quiz(quiz, rng):
    """Rewrites `quiz` in place. Returns the number of questions moved."""
    movable, slots, fixed = [], [], {}
    for position, question in enumerate(quiz["questions"]):
        if is_positional(question):
            fixed[position] = question["correct_option_id"]
        else:
            movable.append(question)
            slots.append(position)

    targets = deal(rng, slots, fixed)

    for question, target in zip(movable, targets):
        answer = next(o for o in question["options"] if o["id"] == question["correct_option_id"])
        others = [o for o in question["options"] if o["id"] != question["correct_option_id"]]
        rng.shuffle(others)

        texts = {target: answer["text"]}
        for option_id, option in zip([i for i in IDS if i != target], others):
            texts[option_id] = option["text"]

        question["options"] = [{"id": i, "text": texts[i]} for i in IDS]
        question["correct_option_id"] = target

    return len(movable)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=20260815)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    rng = random.Random(args.seed)
    files = sorted(glob.glob(QUIZZES))
    if not files:
        sys.exit("no quiz files found")

    moved = skipped = 0
    for path in files:
        with open(path) as handle:
            quiz = json.load(handle)

        count = shuffle_quiz(quiz, rng)
        moved += count
        skipped += len(quiz["questions"]) - count

        if not args.dry_run:
            with open(path, "w") as handle:
                json.dump(quiz, handle, indent=2, ensure_ascii=False)
                handle.write("\n")

    verb = "would move" if args.dry_run else "moved"
    print(f"{len(files)} quiz files, {verb} {moved} questions, left {skipped} positional ones alone")


if __name__ == "__main__":
    main()
