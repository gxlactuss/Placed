#!/usr/bin/env python3
"""Grow each bundled company CSV with every public source that tags problems to that company.

The bundled lists started as snapshots of one repo, so smaller companies had only a handful of
problems. This merges every public source below into the existing CSVs, re-tags every row from
LeetCode's live catalog, and never drops a row that is already bundled (the hand-curated KJSIT
lists stay intact).

Sources, in order of trust:
  liquidslr/leetcode-company-wise-problems        LeetCode company tags, current (primary)
  snehasishroy/leetcode-companywise-interview-questions  LeetCode company tags, current
  krishnadey30/LeetCode-Questions-CompanyWise     LeetCode company tags, 2021 snapshot
  hxu296/leetcode-company-wise-problems-2022      mined from LeetCode Discuss interview posts
  ssavi-ict/LeetCode-Which-Company                company -> problem index behind the extension
  GeeksforGeeks practice company tags             mapped to LeetCode by gfg-leetcode-equivalents.json
                                                  (hand-checked) or an identical title
  LeetCode Discuss interview posts                mined live for companies under DISCUSS_BELOW
                                                  problems: linked problems plus exact titles, and
                                                  interview-experience-problems.json for questions a
                                                  post describes without naming (read by hand)

Frequency keeps the 0-100 LeetCode scale. A problem only the older or secondary sources report
gets 0, which the app shows without a "Freq" badge and sorts after the current ones, most
corroborated first.

Usage:
  python3 Scripts/build-company-csvs.py                 # every bundled company
  python3 Scripts/build-company-csvs.py Deloitte Nykaa  # just these
  python3 Scripts/build-company-csvs.py --dry-run       # print the report, write nothing

Pass --cache DIR to reuse clones and the catalog between runs.
"""

import argparse
import csv
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(ROOT, "PlacementPrep", "Resources", "Companies")

REPOS = {
    "liquidslr": "liquidslr/leetcode-company-wise-problems",
    "snehasishroy": "snehasishroy/leetcode-companywise-interview-questions",
    "krishnadey30": "krishnadey30/LeetCode-Questions-CompanyWise",
    "hxu296": "hxu296/leetcode-company-wise-problems-2022",
    "ssavi": "ssavi-ict/LeetCode-Which-Company",
}

# Sources whose Frequency is LeetCode's current 0-100 scale for that company.
CURRENT = ("liquidslr", "snehasishroy")

# Lists curated from on-campus interview experiences: their own ordering beats the upstream one.
# Keep in sync with DSACompany.kjsitRecruiters.
CURATED = {"deloitte", "medianet", "idfcfirstbank", "accenture", "ltimindtree"}

# Upstream spellings that don't normalise to the bundled name: renames, parents that hire through
# one process (LTIMindtree is the LTI + Mindtree merger), and typos in the sources.
COMPANY_ALIASES = {
    "facebook": "meta",
    "tiktok": "bytedance",
    "bytedancetoutiao": "bytedance",
    "lti": "ltimindtree",
    "mindtree": "ltimindtree",
    "larsentoubroinfotech": "ltimindtree",
    "larsentoubroinfotechlti": "ltimindtree",
    "ltilarsentoubroinfotech": "ltimindtree",
    "morganstanely": "morganstanley",
    "zohocorporation": "zoho",
    "quipsalesforce": "salesforce",
}

# How to find a company's interview posts on LeetCode Discuss: search keywords, and the pattern a
# post title must match to count as being about that company. Default: the name itself.
DISCUSS_SEARCH = {
    "idfcfirstbank": (["IDFC"], r"\bidfc\b"),
    "ltimindtree": (["LTIMindtree", "Mindtree", "LTI"], r"ltimindtree|mindtree|\blti\b|l\s*&\s*t\s+infotech"),
    "medianet": (["media.net"], r"media\s*\.?\s*net"),
    "bytedance": (["bytedance", "tiktok"], r"byte\s*dance|tik\s*tok"),
    "morganstanley": (["morgan stanley"], r"morgan\s*stanley"),
    "goldmansachs": (["goldman sachs"], r"goldman"),
}

# Companies below this many problems after the tag merge also get Discuss interview posts mined.
DISCUSS_BELOW = 100

# Company names that are also ordinary words or interview jargon ("CTC: 30 LPA"), so they can't be
# used to spot a post that covers several companies.
AMBIGUOUS_COMPANY_NAMES = {
    "affirm", "attentive", "audible", "aurora", "axon", "block", "bolt", "box", "bp", "cadence", "canonical",
    "chime", "circle", "compass", "cruise", "ctc", "drw", "ey", "fpt", "grab", "harness", "hive", "imc",
    "indeed", "ivp", "kla", "line", "lucid", "millennium", "notion", "rbc", "ripple", "sentry", "sig",
    "slice", "snap", "target", "toast", "trilogy", "ukg", "unity", "upstart", "valve", "vk", "wise", "wish",
    "x",
}

# LeetCode titles that read as technique names in prose ("I used Binary Search"), so a post only
# counts them when it links the problem. Titles that equal a topic tag are added automatically.
PROSE_TITLES = {"Sort an Array", "Merge Sort", "Design"}

# Slugs LeetCode retired whose replacement can't be found by problem id or title.
SLUG_ALIASES = {
    "swap-salary": "swap-sex-of-employees",
    "minimum-number-of-buckets-required-to-collect-rainwater-from-houses":
        "minimum-number-of-food-buckets-to-feed-the-hamsters",
}

HEADER = ["Difficulty", "Title", "Frequency", "Acceptance Rate", "Link", "Topics"]


def company_key(name):
    k = re.sub(r"[^a-z0-9]", "", name.lower())
    return COMPANY_ALIASES.get(k, k)


def title_key(title):
    return re.sub(r"[^a-z0-9]", "", (title or "").lower())


def slug_of(link):
    m = re.search(r"leetcode\.com/problems/([^/?#\s]+)", link or "")
    return m.group(1).strip().lower() if m else None


def number(value):
    try:
        return float(str(value).strip().rstrip("%"))
    except ValueError:
        return 0.0


def read_csv(path):
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


# --- fetching ---------------------------------------------------------------------------------

def clone_sources(cache):
    for name, repo in REPOS.items():
        path = os.path.join(cache, name)
        if os.path.isdir(path):
            continue
        print(f"Cloning {repo} …", file=sys.stderr)
        subprocess.run(["git", "clone", "--depth", "1", "--quiet",
                        f"https://github.com/{repo}.git", path], check=True)


def fetch_catalog(cache):
    path = os.path.join(cache, "leetcode-catalog.json")
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)

    print("Fetching the LeetCode catalog …", file=sys.stderr)
    query = """query q($skip: Int, $limit: Int) {
      questionList(categorySlug: "", limit: $limit, skip: $skip, filters: {}) {
        total: totalNum
        data { questionFrontendId title titleSlug difficulty acRate topicTags { name } }
      }
    }"""
    questions, skip = [], 0
    while True:
        body = json.dumps({"query": query, "variables": {"skip": skip, "limit": 100}}).encode()
        request = urllib.request.Request("https://leetcode.com/graphql", data=body, headers={
            "Content-Type": "application/json",
            "Referer": "https://leetcode.com/problemset/",
            "User-Agent": "Mozilla/5.0",
        })
        with urllib.request.urlopen(request, timeout=60) as response:
            page = json.load(response)["data"]["questionList"]
        questions += page["data"]
        skip += 100
        if skip >= page["total"] or not page["data"]:
            break
        time.sleep(0.3)

    with open(path, "w") as f:
        json.dump(questions, f)
    return questions


def graphql(query, variables, referer="https://leetcode.com/discuss/"):
    body = json.dumps({"query": query, "variables": variables}).encode()
    request = urllib.request.Request("https://leetcode.com/graphql", data=body, headers={
        "Content-Type": "application/json", "Referer": referer, "User-Agent": "Mozilla/5.0",
    })
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)["data"]
        except (OSError, KeyError, ValueError):
            time.sleep(2 * (attempt + 1))
    raise RuntimeError("LeetCode GraphQL kept failing")


DISCUSS_SEARCH_QUERY = """query d($keywords: [String]!, $skip: Int, $first: Int) {
  ugcArticleDiscussionArticles(orderBy: MOST_RELEVANT, keywords: $keywords, tagSlugs: ["interview"],
                               skip: $skip, first: $first) {
    totalNum
    edges { node { title topicId } }
  }
}"""
DISCUSS_ARTICLE_QUERY = """query a($topicId: ID!) {
  ugcArticleDiscussionArticle(topicId: $topicId) { title content createdAt }
}"""


def discuss_posts(keyword, cache):
    """Every interview-tagged Discuss post the search returns for a keyword, bodies cached."""
    posts_dir = os.path.join(cache, "discuss")
    os.makedirs(posts_dir, exist_ok=True)
    hits, skip = [], 0
    while skip < 1000:  # the search stops paging past this
        page = graphql(DISCUSS_SEARCH_QUERY, {"keywords": [keyword], "skip": skip, "first": 50})
        page = page["ugcArticleDiscussionArticles"]
        hits += [edge["node"] for edge in page["edges"]]
        skip += 50
        if skip >= page["totalNum"] or not page["edges"]:
            break
        time.sleep(0.3)

    for hit in hits:
        path = os.path.join(posts_dir, f"{hit['topicId']}.json")
        if not os.path.exists(path):
            post = graphql(DISCUSS_ARTICLE_QUERY, {"topicId": str(hit["topicId"])})
            with open(path, "w") as f:
                json.dump(post["ugcArticleDiscussionArticle"] or {}, f)
            time.sleep(0.25)
        with open(path) as f:
            post = json.load(f)
        if post:
            yield hit["topicId"], post


class TitleMatcher:
    """Finds the LeetCode problems an interview post names, by link or by exact title."""

    def __init__(self, catalog):
        tags = {t["name"] for q in catalog for t in q["topicTags"]}
        self.patterns = []
        for q in catalog:
            title = q["title"]
            words = len(title.split())
            if words < 2 or title in PROSE_TITLES or title in tags or title.startswith("Design "):
                continue
            body = re.escape(title).replace(r"\ ", r"[\s-]+")
            flags = re.IGNORECASE if words >= 4 else 0
            pattern = re.compile(rf"(?<![A-Za-z0-9]){body}(?![A-Za-z0-9])", flags)
            self.patterns.append((q["titleSlug"], pattern))

    def problems(self, text):
        found = set(re.findall(r"leetcode\.(?:com|cn)/problems/([a-z0-9-]+)", text))
        spans = []
        for slug, pattern in self.patterns:
            for m in pattern.finditer(text):
                spans.append((m.end() - m.start(), m.start(), m.end(), slug))
        taken = []
        for _, start, end, slug in sorted(spans, reverse=True):  # longest title wins an overlap
            if any(start < e and s < end for s, e in taken):
                continue
            taken.append((start, end))
            found.add(slug)
        return found


def load_read_posts():
    """company key -> {post id: [slugs]} for posts read by hand (interview-experience-problems.json)."""
    with open(READ_POSTS) as f:
        data = json.load(f)
    return {company_key(name): {int(post): slugs for post, slugs in posts.items()}
            for name, posts in data.items() if not name.startswith("_")}


def mine_discuss(name, cache, matcher, other_companies, read_posts):
    """slug -> number of this company's interview posts that name the problem.

    read_posts: {post id: [slugs]} read by hand, for questions a post describes without naming.
    """
    key = company_key(name)
    keywords, title_pattern = DISCUSS_SEARCH.get(key, ([name], re.escape(name).replace(r"\ ", r"\s*")))
    about = re.compile(title_pattern, re.IGNORECASE)
    others = [re.compile(rf"(?<![a-z0-9]){re.escape(c)}(?![a-z0-9])", re.IGNORECASE)
              for c in other_companies if company_key(c) != key and not about.search(c)]

    mentions, seen, posts = defaultdict(int), set(), 0
    for keyword in keywords:
        for topic_id, post in discuss_posts(keyword, cache):
            title = post.get("title") or ""
            if topic_id in seen or not about.search(title):
                continue
            seen.add(topic_id)
            if topic_id in read_posts:  # already attributed by hand, section by section
                found = matcher.problems(post.get("content") or "") | set(read_posts[topic_id])
            # "Paypal | Razorpay | Nurture.farm" can't say which company asked which question.
            elif any(other.search(about.sub(" ", title)) for other in others):
                continue
            else:
                found = matcher.problems(post.get("content") or "")
            posts += 1
            for slug in found:
                mentions[slug] += 1
    return mentions, posts


READ_POSTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "interview-experience-problems.json")

GFG_API = "https://practiceapi.geeksforgeeks.org/api/vr/problems/"
GFG_EQUIVALENTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gfg-leetcode-equivalents.json")

# GeeksforGeeks company tags that differ from the bundled name.
GFG_TAGS = {"meta": "Facebook"}


def load_gfg_equivalents(catalog):
    """GfG problem slug -> LeetCode slug: hand-checked equivalents, then identical titles."""
    by_title = {title_key(q["title"]): q["titleSlug"] for q in catalog}
    with open(GFG_EQUIVALENTS) as f:
        table = json.load(f)
    return lambda problem: table.get(problem["slug"]) or by_title.get(title_key(problem["problem_name"]))


def gfg_problems(name, cache, equivalent):
    """LeetCode slugs for the GeeksforGeeks problems tagged with this company."""
    path = os.path.join(cache, "gfg", f"{name}.json")
    if not os.path.exists(path):
        tag = GFG_TAGS.get(company_key(name), name)
        problems, page = [], 1
        while True:
            query = urllib.parse.urlencode({"pageMode": "explore", "page": page, "sortBy": "submissions",
                                            "company": tag})
            request = urllib.request.Request(f"{GFG_API}?{query}", headers={"User-Agent": "Mozilla/5.0"})
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    data = json.load(response)
            except urllib.error.HTTPError:  # an unknown tag is a 400
                break
            problems += data.get("results") or []
            if not data.get("results") or len(problems) >= data.get("total", 0):
                break
            page += 1
            time.sleep(0.2)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            json.dump(problems, f)
    with open(path) as f:
        problems = json.load(f)
    return {slug: 1 for slug in map(equivalent, problems) if slug}


# --- loading ----------------------------------------------------------------------------------

class Evidence:
    """Everything the sources say about one company's problems, keyed by raw slug."""

    def __init__(self):
        self.current = {}                # slug -> 0-100 frequency from an all-time current list
        self.recent_only = {}            # slug -> frequency from a shorter window only
        self.sources = defaultdict(set)  # slug -> source names
        self.discuss = defaultdict(float)  # slug -> interview-post mentions (hxu296)
        self.legacy = {}                 # slug -> 2021 frequency (krishnadey30)


def load_sources(cache):
    evidence = defaultdict(Evidence)
    ids, titles = {}, {}

    def windowed(name, company_dirs, all_file, row_slug, row_freq, row_id=None, row_title=None):
        for directory in company_dirs:
            e = evidence[company_key(os.path.basename(directory.rstrip("/")))]
            files = sorted(glob.glob(os.path.join(directory, "*.csv")))
            for path in sorted(files, key=lambda p: os.path.basename(p) != all_file):
                is_all = os.path.basename(path) == all_file
                for row in read_csv(path):
                    slug = row_slug(row)
                    if not slug:
                        continue
                    e.sources[slug].add(name)
                    if row_id:
                        ids.setdefault(slug, row_id(row))
                    if row_title:
                        titles.setdefault(slug, row_title(row))
                    freq = number(row_freq(row))
                    if is_all:
                        e.current[slug] = max(e.current.get(slug, 0), freq)
                    elif slug not in e.current:
                        e.recent_only[slug] = max(e.recent_only.get(slug, 0), freq)

    windowed("liquidslr",
             glob.glob(os.path.join(cache, "liquidslr", "*/")), "5. All.csv",
             lambda r: slug_of(r.get("Link")), lambda r: r.get("Frequency"),
             row_title=lambda r: r.get("Title"))
    windowed("snehasishroy",
             glob.glob(os.path.join(cache, "snehasishroy", "*/")), "all.csv",
             lambda r: slug_of(r.get("URL")), lambda r: r.get("Frequency %"),
             row_id=lambda r: r.get("ID"), row_title=lambda r: r.get("Title"))

    for path in glob.glob(os.path.join(cache, "krishnadey30", "*.csv")):
        company = re.sub(r"_(alltime|1year|2year|6months)$", "", os.path.basename(path)[:-4])
        e = evidence[company_key(company)]
        for row in read_csv(path):
            slug = slug_of(row.get("Leetcode Question Link"))
            if slug:
                e.sources[slug].add("krishnadey30")
                e.legacy[slug] = max(e.legacy.get(slug, 0), number(row.get("Frequency")))
                ids.setdefault(slug, row.get("ID"))
                titles.setdefault(slug, row.get("Title"))

    discuss = os.path.join(cache, "hxu296", "data", "leetcode_problems_and_companies.csv")
    for row in read_csv(discuss):
        slug = slug_of(row["problem_link"])
        if slug:
            e = evidence[company_key(row["company_name"])]
            e.sources[slug].add("hxu296")
            e.discuss[slug] += number(row["num_occur"])
            titles.setdefault(slug, row["problem_name"])

    with open(os.path.join(cache, "ssavi", "data", "company_info.json")) as f:
        index = json.load(f)
    for link, (title, *companies) in index.items():
        slug = slug_of(link)
        if not slug:
            continue
        titles.setdefault(slug, title)
        for company in companies:
            evidence[company_key(company)].sources[slug].add("ssavi")

    return evidence, ids, titles


def build_resolver(catalog, ids, titles):
    by_slug = {q["titleSlug"]: q for q in catalog}
    by_id = {q["questionFrontendId"]: q["titleSlug"] for q in catalog}
    by_title = {title_key(q["title"]): q["titleSlug"] for q in catalog}

    def resolve(slug):
        """The live slug for a possibly-retired one, or None if LeetCode no longer has it."""
        if slug in by_slug:
            return slug
        slug = SLUG_ALIASES.get(slug, slug)
        if slug in by_slug:
            return slug
        return by_id.get(ids.get(slug)) or by_title.get(title_key(titles.get(slug)))

    return by_slug, resolve


# --- merging ----------------------------------------------------------------------------------

def merge(name, rows, evidence, by_slug, resolve, extra=None):
    """extra: {source name: {slug: mentions}} from Discuss posts and GeeksforGeeks tags."""
    key = company_key(name)
    e = evidence.get(key, Evidence())
    curated = key in CURATED

    merged = {}  # live slug -> dict

    def entry(slug):
        return merged.setdefault(slug, {
            "slug": slug, "bundled": None, "order": len(merged),
            "current": None, "recent": None, "sources": set(), "discuss": 0.0, "legacy": 0.0,
            "topics": "",
        })

    dropped = []
    for row in rows:
        live = resolve(slug_of(row.get("Link")))
        if not live:
            dropped.append(row.get("Title"))
            continue
        item = entry(live)
        item["sources"].add("bundled")
        if item["bundled"] is None:
            item["bundled"] = number(row.get("Frequency"))
            item["topics"] = row.get("Topics", "")

    for raw in set(e.sources) | set(e.current) | set(e.recent_only):
        live = resolve(raw)
        if not live:
            continue
        item = entry(live)
        item["sources"] |= e.sources.get(raw, set())
        if raw in e.current:
            item["current"] = max(item["current"] or 0, e.current[raw])
        if raw in e.recent_only:
            item["recent"] = max(item["recent"] or 0, e.recent_only[raw])
        item["discuss"] += e.discuss.get(raw, 0)
        item["legacy"] = max(item["legacy"], e.legacy.get(raw, 0))

    for source, counts in (extra or {}).items():
        for raw, count in counts.items():
            live = resolve(raw)
            if not live:
                continue
            item = entry(live)
            item["sources"].add(source)
            if source == "discuss":
                item["discuss"] += count

    for item in merged.values():
        if curated and item["bundled"] is not None:
            freq = item["bundled"]
        elif item["current"] is not None:
            freq = item["current"]
        elif item["bundled"] is not None:
            freq = item["bundled"]
        else:
            freq = item["recent"] or 0.0
        item["frequency"] = freq

    def rank(item):
        independent = len(item["sources"] - {"bundled"})
        return (-item["frequency"], -independent, -item["discuss"], -item["legacy"], item["order"])

    out = []
    for item in sorted(merged.values(), key=rank):
        q = by_slug[item["slug"]]
        topics = ", ".join(t["name"] for t in q["topicTags"]) or item["topics"]
        out.append({
            "Difficulty": q["difficulty"].upper(),
            "Title": q["title"],
            "Frequency": f"{item['frequency']:.1f}",
            "Acceptance Rate": f"{q['acRate'] / 100:.4f}",
            "Link": f"https://leetcode.com/problems/{item['slug']}",
            "Topics": topics,
        })
    return out, dropped


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("companies", nargs="*", help="bundled company names to rebuild (default: all)")
    parser.add_argument("--cache", help="directory to keep clones and the catalog in between runs")
    parser.add_argument("--dry-run", action="store_true", help="report the changes without writing")
    args = parser.parse_args()

    cache = args.cache or tempfile.mkdtemp(prefix="company-csvs-")
    os.makedirs(cache, exist_ok=True)
    clone_sources(cache)
    catalog = fetch_catalog(cache)
    evidence, ids, titles = load_sources(cache)
    by_slug, resolve = build_resolver(catalog, ids, titles)

    matcher = TitleMatcher(catalog)
    gfg_equivalents = load_gfg_equivalents(catalog)
    read_posts = load_read_posts()
    bundled_names = [os.path.basename(p)[:-4] for p in glob.glob(os.path.join(DEST, "*.csv"))]
    upstream_names = [os.path.basename(d.rstrip("/")) for d in glob.glob(os.path.join(cache, "liquidslr", "*/"))]
    other_companies = sorted({n for n in bundled_names + upstream_names
                              if n.lower() not in AMBIGUOUS_COMPANY_NAMES})

    wanted = {company_key(c) for c in args.companies}
    paths = sorted(glob.glob(os.path.join(DEST, "*.csv")))
    print(f"{'company':<18}{'before':>8}{'after':>8}{'added':>8}{'posts':>8}  dropped")
    for path in paths:
        name = os.path.basename(path)[:-4]
        if wanted and company_key(name) not in wanted:
            continue
        rows = read_csv(path)
        extra = {"gfg": gfg_problems(name, cache, gfg_equivalents)}
        out, dropped = merge(name, rows, evidence, by_slug, resolve, extra)
        posts = ""
        if len(out) < DISCUSS_BELOW or company_key(name) in read_posts:
            extra["discuss"], posts = mine_discuss(name, cache, matcher, other_companies,
                                                   read_posts.get(company_key(name), {}))
            out, dropped = merge(name, rows, evidence, by_slug, resolve, extra)
        print(f"{name:<18}{len(rows):>8}{len(out):>8}{len(out) - len(rows) + len(dropped):>8}{posts:>8}"
              f"  {', '.join(dropped)}")
        if args.dry_run:
            continue
        with open(path, "w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=HEADER, lineterminator="\n")
            writer.writeheader()
            writer.writerows(out)


if __name__ == "__main__":
    main()
