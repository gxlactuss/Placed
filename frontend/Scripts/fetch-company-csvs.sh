#!/usr/bin/env bash
set -euo pipefail

# Seeds one or more new companies from the raw liquidslr snapshot, so build-company-csvs.py has a
# bundled CSV to fill in. It never touches a company that is already bundled unless --force is
# given, because the bundled lists hold merged sources and the curated KJSIT lists.
#
#   ./Scripts/fetch-company-csvs.sh "Airbnb"            # seed Airbnb.csv
#   ./Scripts/fetch-company-csvs.sh --force Airbnb      # replace an existing Airbnb.csv
#   ./Scripts/fetch-company-csvs.sh --all               # old behaviour: overwrite every list (asks first)
#
# Names match the upstream directory case-insensitively, and the file is saved under the name as
# you typed it, which is the name the app shows and the name the logo must use.
#
# COMPANIES_DIR overrides where the CSVs go; COMPANIES_REPO overrides the upstream repo (a URL or a
# local clone). Both exist for testing.

usage() {
    cat <<'EOF'
Usage: fetch-company-csvs.sh [--force] COMPANY...
       fetch-company-csvs.sh --all

Copies "<COMPANY>/5. All.csv" from liquidslr/leetcode-company-wise-problems into
Placed/Resources/Companies/<COMPANY>.csv.

  --force   overwrite a company that is already bundled (loses its merged and curated rows)
  --all     copy every upstream company over the bundled lists, after a confirmation prompt
  -h        show this help
EOF
}

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
REPO="${COMPANIES_REPO:-https://github.com/liquidslr/leetcode-company-wise-problems.git}"
DEST="${COMPANIES_DIR:-$SCRIPTS/../Placed/Resources/Companies}"
NOT_BUNDLED="$SCRIPTS/companies-not-bundled.txt"

force=0
all=0
names=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) force=1 ;;
        --all) all=1 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; names+=("$@"); break ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *) names+=("$1") ;;
    esac
    shift
done

if [[ $all -eq 1 && ${#names[@]} -gt 0 ]]; then
    echo "--all takes no company names." >&2
    exit 2
fi
if [[ $all -eq 0 && ${#names[@]} -eq 0 ]]; then
    usage >&2
    exit 2
fi

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
# Same idea as company_key() in build-company-csvs.py: "Media.net" and "medianet" are one company.
key() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'; }

if [[ $all -eq 1 ]]; then
    echo "--all overwrites EVERY bundled list in:"
    echo "  $DEST"
    echo "with the raw upstream snapshot, losing the merged sources and the curated KJSIT lists."
    printf 'Type "overwrite" to continue: '
    answer=""
    read -r answer || true
    if [[ "$answer" != "overwrite" ]]; then
        echo "Aborted, nothing written."
        exit 1
    fi
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Cloning $REPO …"
git clone --depth 1 --quiet "$REPO" "$TMP/repo"

upstream=()
while IFS= read -r dir; do
    [[ -f "$dir/5. All.csv" ]] && upstream+=("$(basename "$dir")")
done < <(find "$TMP/repo" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)

if [[ ${#upstream[@]} -eq 0 ]]; then
    echo "error: no \"<company>/5. All.csv\" files found in $REPO" >&2
    exit 1
fi

mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"

if [[ $all -eq 1 ]]; then
    for company in "${upstream[@]}"; do
        cp "$TMP/repo/$company/5. All.csv" "$DEST/$company.csv"
    done
    echo "Wrote ${#upstream[@]} company CSVs to:"
    echo "  $DEST"
    echo
    echo "Next, from frontend/: python3 Scripts/build-company-csvs.py, then xcodegen generate"
    exit 0
fi

# Resolve and check every name before writing anything.
sources=()
replaces=()
failed=0
for name in "${names[@]}"; do
    match=""
    for company in "${upstream[@]}"; do
        if [[ "$(lower "$company")" == "$(lower "$name")" ]]; then
            match="$company"
            break
        fi
    done

    if [[ -z "$match" ]]; then
        echo "error: \"$name\" is not an upstream company." >&2
        close="$(printf '%s\n' "${upstream[@]}" | python3 -c '
import difflib, re, sys
name = sys.argv[1]
key = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())
names = [l.rstrip("\n") for l in sys.stdin if l.strip()]
hits = [n for n in names if min(len(key(name)), len(key(n))) >= 3
        and (key(name) in key(n) or key(n) in key(name))]
by_key = {key(n): n for n in names}
hits += [by_key[k] for k in difflib.get_close_matches(key(name), list(by_key), n=5, cutoff=0.7)]
print("\n".join(dict.fromkeys(hits)))
' "$name" 2>/dev/null || true)"
        if [[ -n "$close" ]]; then
            echo "  Close matches:" >&2
            printf '%s\n' "$close" | sed 's/^/    /' >&2
        else
            echo "  No close matches. Upstream companies are the directory names in $REPO" >&2
        fi
        failed=1
        continue
    fi

    existing=""
    for path in "$DEST"/*.csv; do
        [[ -e "$path" ]] || continue
        bundled="$(basename "$path" .csv)"
        if [[ "$(key "$bundled")" == "$(key "$name")" ]]; then
            existing="$bundled"
            break
        fi
    done
    if [[ -n "$existing" && $force -eq 0 ]]; then
        echo "error: \"$existing.csv\" is already bundled; refusing to overwrite it." >&2
        echo "  To refresh it keep the curated rows: python3 Scripts/build-company-csvs.py \"$existing\"" >&2
        echo "  To replace it with the raw upstream list anyway, pass --force." >&2
        failed=1
        continue
    fi
    sources+=("$match")
    replaces+=("$existing")
done

if [[ $failed -ne 0 ]]; then
    echo "Nothing written." >&2
    exit 1
fi

i=0
for name in "${names[@]}"; do
    if [[ -n "${replaces[$i]}" ]]; then
        # --force keeps the bundled spelling, so "google" still overwrites Google.csv.
        target="${replaces[$i]}"
        verb="Overwrote (--force)"
    else
        target="$name"
        verb="Wrote"
    fi
    cp "$TMP/repo/${sources[$i]}/5. All.csv" "$DEST/$target.csv"
    rows=$(($(awk 'END { print NR }' "$DEST/$target.csv") - 1))
    echo "$verb $target.csv ($rows problems, from upstream \"${sources[$i]}\")"
    if [[ "$target" != "${sources[$i]}" ]]; then
        echo "  note: upstream spells it \"${sources[$i]}\"; the file name is the name the app shows."
    fi
    if [[ -z "${replaces[$i]}" && -f "$NOT_BUNDLED" ]] && grep -qixF -- "$name" "$NOT_BUNDLED"; then
        echo "  \"$name\" is listed in Scripts/companies-not-bundled.txt; remove that line."
    fi
    names[i]="$target"
    i=$((i + 1))
done
echo "  in $DEST"
echo
quoted="$(printf ' "%s"' "${names[@]}")"
echo "Next, from frontend/ (README, \"Add a new company\"):"
echo "  python3 Scripts/build-company-csvs.py$quoted"
echo "  add each one to COMPANIES in Scripts/fetch-company-logos.py, then:"
echo "  python3 Scripts/fetch-company-logos.py$quoted"
echo "  xcodegen generate"
