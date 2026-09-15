#!/usr/bin/env python3

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

POSITIONAL = re.compile(
    r"(of the above)|(\b(both|either|neither|options?|answers?)\b[^.]{0,20}\b[ABCD]\b\s*(and|,|&|or)\s*\b[ABCD]\b)",
    re.I,
)


def is_positional(question):
    return any(POSITIONAL.search(option["text"]) for option in question["options"])


def has_pattern(letters):
    steps = [(IDS.index(b) - IDS.index(a)) % 4 for a, b in zip(letters, letters[1:])]

    run = 0
    for i, step in enumerate(steps):
        run = run + 1 if i and steps[i - 1] == step else 1
        if run >= 4 and step in (0, 1, 3):
            return True
        if run >= 2 and step == 0:
            return True
    return False


def deal(rng, slots, fixed):
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
