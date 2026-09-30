"""Server-side redaction of contact details from resume text.

The iOS app already strips these before upload (ResumeParser.swift); this is
defence in depth so a modified or buggy client can't leak them to the LLM.
The patterns are copied character-for-character from
frontend/PlacementPrep/Services/ResumeParser.swift (emailPattern, phonePattern)
so both sides agree on what counts as an email or phone number. If you change
one, change the other and the shared sample strings in
backend/tests/test_resume_privacy.py and
frontend/PlacementPrepTests/ResumeParserTests.swift.
"""

import re

REDACTED = "[redacted]"

# ResumeParser.emailPattern
_EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")

# ResumeParser.phonePattern. Pieces, in order:
#   (?<![\w.,/+])                 not glued to a word, decimal, 1,50,000-style
#                                 group, date/URL slash or another "+"
#   (?:(?:\+|00)\d{1,3}SEP?|0)?   optional +CC / 00CC country code, or a
#                                 leading 0 trunk prefix
#   \d{10,12}                     contiguous 10-12 digits, or
#   \d{5}SEP?\d{5}                Indian 5-5 grouping, or
#   (?:\(\d{3}\)|\d{3})SEP?\d{3}SEP?\d{4}
#                                 3-3-4, area code optionally in parentheses
#   (?![\w%]|[.,/-]\d)            not followed by a word, "%" or more number
# where SEP is one space, tab, no-break space, dot or dash. Years, ranges,
# CGPAs, percentages, versions, PIN codes and dates never reach 10 digits in
# one of these groupings, so they survive.
_PHONE = re.compile(
    r"(?<![\w.,/+])(?:(?:\+|00)\d{1,3}[ \t .-]?|0)?"
    r"(?:\d{10,12}|\d{5}[ \t .-]?\d{5}|(?:\(\d{3}\)|\d{3})[ \t .-]?\d{3}[ \t .-]?\d{4})"
    r"(?![\w%]|[.,/-]\d)"
)


def redact_contact_details(text: str) -> str:
    """Replace email addresses and phone numbers with "[redacted]"."""
    for pattern in (_EMAIL, _PHONE):
        text = pattern.sub(REDACTED, text)
    return text
