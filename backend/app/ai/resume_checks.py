from __future__ import annotations

import re
from dataclasses import dataclass

_SECTIONS: dict[str, tuple[str, ...]] = {
    "education": ("education", "academics", "academic background", "academic qualifications"),
    "skills": (
        "skills", "technical skills", "technologies", "tech stack", "skills and tools",
        "tools and technologies", "technical proficiencies", "core competencies",
    ),
    "projects": (
        "projects", "project", "personal projects", "academic projects", "key projects",
        "selected projects", "project experience", "project work",
    ),
    "experience": (
        "experience", "work experience", "professional experience", "employment",
        "internship", "internships",
    ),
    "achievements": (
        "achievements", "accomplishments", "awards", "honors", "honours",
        "certifications", "certificates",
    ),
}

_OTHER_HEADINGS = (
    "summary", "objective", "career objective", "profile", "about me", "interests", "hobbies",
    "activities", "extracurricular", "extracurricular activities", "positions of responsibility",
    "publications", "coursework", "relevant coursework", "references", "volunteer",
    "leadership", "languages", "declaration",
)

_OTHER = "other"

_HEADING_TO_SECTION = {
    **{heading: _OTHER for heading in _OTHER_HEADINGS},
    **{heading: key for key, headings in _SECTIONS.items() for heading in headings},
}

_BULLET_GLYPHS = "•●▪◦·‣∙-–—*"

_ACTION_VERBS = frozenset("""
achieved analysed analyzed architected automated benchmarked built collaborated competed
configured conducted contributed coordinated created cut debugged decreased defined delivered
deployed designed developed devised directed documented doubled drove engineered enhanced
established evaluated expanded implemented improved increased initiated integrated introduced
launched led maintained managed mentored migrated modelled modeled monitored optimised optimized
organised organized overhauled owned participated pioneered presented profiled programmed
prototyped published rebuilt redesigned reduced refactored released researched resolved
restructured revamped scaled scripted secured shipped simplified solved spearheaded streamlined
taught tested trained transformed tuned upgraded validated visualised visualized won wrote
""".split())

_NUMBER = re.compile(r"(?<![\w.])(\d+(?:[.,]\d+)?)")
_YEAR = re.compile(r"^(?:19|20)\d{2}$")
_FIRST_PERSON = re.compile(r"\b(?:I|me|my|mine|myself|we|our|us)\b", re.IGNORECASE)


@dataclass(frozen=True)
class DeviceFacts:
    has_email: bool
    has_phone: bool
    has_links: bool
    page_count: int
    has_text_layer: bool


@dataclass(frozen=True)
class ResumeSignals:
    word_count: int
    sections: tuple[str, ...]
    bullets: tuple[str, ...]
    quantified_bullets: int
    action_verb_bullets: int
    first_person_count: int

    @property
    def missing_core_sections(self) -> list[str]:
        return [s for s in ("education", "skills", "projects") if s not in self.sections]


def _heading(line: str) -> str | None:
    cleaned = line.strip(" \t:•·-–—_*#|").lower()
    if not cleaned or len(cleaned) > 40:
        return None
    return _HEADING_TO_SECTION.get(cleaned)


def _has_metric(text: str) -> bool:
    return any(not _YEAR.match(number) for number in _NUMBER.findall(text))


def _opens_with_action_verb(text: str) -> bool:
    words = text.split()
    if not words:
        return False
    return words[0].strip(".,:;()").lower() in _ACTION_VERBS


def _bullets(lines: list[str]) -> list[str]:
    glyph: list[str] = []
    in_body: list[str] = []
    section: str | None = None

    for line in lines:
        key = _heading(line)
        if key is not None:
            section = key
            continue
        if not line:
            continue
        if line[0] in _BULLET_GLYPHS and len(line) > 1:
            glyph.append(line.lstrip(_BULLET_GLYPHS).strip())
        elif glyph and line[0].islower():
            glyph[-1] = f"{glyph[-1]} {line}"
        if section in ("projects", "experience"):
            if in_body and line[0].islower():
                in_body[-1] = f"{in_body[-1]} {line}"
            elif len(line.split()) >= 6:
                in_body.append(line.lstrip(_BULLET_GLYPHS).strip())

    # PDF text layers often drop the bullet glyph, so fall back to the sentences
    # under Projects and Experience when too few glyph bullets survived.
    return glyph if len(glyph) >= 3 else in_body


def analyse(text: str) -> ResumeSignals:
    lines = [line.strip() for line in text.splitlines()]
    sections = sorted({key for line in lines if (key := _heading(line)) and key != _OTHER})
    bullets = _bullets(lines)
    return ResumeSignals(
        word_count=len(text.split()),
        sections=tuple(sections),
        bullets=tuple(bullets),
        quantified_bullets=sum(1 for b in bullets if _has_metric(b)),
        action_verb_bullets=sum(1 for b in bullets if _opens_with_action_verb(b)),
        first_person_count=len(_FIRST_PERSON.findall(text)),
    )


@dataclass(frozen=True)
class Check:
    key: str
    label: str
    passed: bool
    detail: str


def checks(signals: ResumeSignals, device: DeviceFacts) -> list[Check]:
    bullets = len(signals.bullets)
    missing = signals.missing_core_sections
    return [
        Check(
            "ats_readable",
            "Readable by applicant-tracking software",
            device.has_text_layer,
            "The file has a text layer, so screening software can read it."
            if device.has_text_layer
            else "This file is an image or a scan. We read it with OCR, but most screening "
                 "software won't, and will see a blank page.",
        ),
        Check(
            "email",
            "Email address",
            device.has_email,
            "Found. We removed it before sending anything."
            if device.has_email
            else "No email address found. Recruiters need one to reach you.",
        ),
        Check(
            "phone",
            "Phone number",
            device.has_phone,
            "Found. We removed it before sending anything."
            if device.has_phone
            else "No phone number found.",
        ),
        Check(
            "links",
            "LinkedIn or GitHub link",
            device.has_links,
            "Found."
            if device.has_links
            else "Add a GitHub or LinkedIn link so reviewers can see your work.",
        ),
        Check(
            "length",
            "One page",
            device.page_count <= 1,
            "Fits on one page."
            if device.page_count <= 1
            else f"Runs to {device.page_count} pages. A campus resume should fit on one.",
        ),
        Check(
            "sections",
            "Education, Skills and Projects sections",
            not missing,
            "All three are there."
            if not missing
            else f"Couldn't find a {', '.join(s.capitalize() for s in missing)} heading.",
        ),
        Check(
            "metrics",
            "Bullets show numbers",
            bullets > 0 and signals.quantified_bullets / bullets >= 0.3,
            f"{signals.quantified_bullets} of {bullets} bullets include a number."
            if bullets
            else "Couldn't find any bullet points to check.",
        ),
        Check(
            "action_verbs",
            "Bullets open with action verbs",
            bullets > 0 and signals.action_verb_bullets / bullets >= 0.6,
            f"{signals.action_verb_bullets} of {bullets} bullets open with one."
            if bullets
            else "Couldn't find any bullet points to check.",
        ),
        Check(
            "first_person",
            "No first-person pronouns",
            signals.first_person_count == 0,
            "None found."
            if signals.first_person_count == 0
            else f"Found {signals.first_person_count}. Drop \"I\" and \"my\" and start with the verb.",
        ),
    ]


def hard_failures(signals: ResumeSignals, device: DeviceFacts) -> list[dict]:
    failures = []
    if not device.has_text_layer:
        failures.append({
            "factor": "format",
            "section": "Whole resume",
            "issue": "Your resume is an image, so applicant-tracking software can't read any of it.",
            "fix": "Export it as a PDF straight from Word, Google Docs or LaTeX instead of scanning or screenshotting it.",
        })
    if not device.has_email:
        failures.append({
            "factor": "format",
            "section": "Header",
            "issue": "There is no email address, so a recruiter has no way to contact you.",
            "fix": "Add a professional email address to the header, next to your phone number.",
        })
    for section in ("education", "skills"):
        if section in signals.missing_core_sections:
            failures.append({
                "factor": "format",
                "section": section.capitalize(),
                "issue": f"There is no {section.capitalize()} section that screening software can find.",
                "fix": f"Add a section headed exactly \"{section.capitalize()}\" so it is picked up.",
            })
    return [{**failure, "priority": "high"} for failure in failures]


_REPEATS = {
    "Whole resume": re.compile(r"\b(?:image|scan(?:ned)?|ocr|ats|applicant[- ]tracking)\b", re.IGNORECASE),
    "Header": re.compile(r"\be-?mail\b", re.IGNORECASE),
    "Education": re.compile(r"\beducation\b", re.IGNORECASE),
    "Skills": re.compile(r"\bskills? (?:section|list|heading)\b", re.IGNORECASE),
}


def drop_repeats(improvements: list[dict], failures: list[dict]) -> list[dict]:
    """The model is told which hard failures are already reported but often restates them."""
    patterns = [_REPEATS[failure["section"]] for failure in failures]
    return [
        item
        for item in improvements
        if not any(
            pattern.search(f"{item['section']} {item['issue']} {item['fix']}")
            for pattern in patterns
        )
    ]
