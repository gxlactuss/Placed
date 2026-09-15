#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/liquidslr/leetcode-company-wise-problems.git"
DEST="$(cd "$(dirname "$0")/.." && pwd)/PlacementPrep/Resources/Companies"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Cloning $REPO …"
git clone --depth 1 --quiet "$REPO" "$TMP/repo"

mkdir -p "$DEST"
count=0
while IFS= read -r dir; do
    company="$(basename "$dir")"
    src="$dir/5. All.csv"
    if [[ -f "$src" ]]; then
        cp "$src" "$DEST/$company.csv"
        count=$((count + 1))
    fi
done < <(find "$TMP/repo" -mindepth 1 -maxdepth 1 -type d ! -name '.*')

echo "Wrote $count company CSVs to:"
echo "  $DEST"
echo
echo "Next: cd frontend && xcodegen generate"
