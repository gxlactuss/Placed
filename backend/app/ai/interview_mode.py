from __future__ import annotations

from enum import Enum


class InterviewMode(str, Enum):
    HR = "hr"
    TECH_STACK = "tech_stack"
    CORE_CS = "core_cs"
    PROJECTS = "projects"
    PANEL_DEBATE = "panel_debate"
    DSA_APPROACH = "dsa_approach"

    @classmethod
    def parse(cls, raw: str | None) -> "InterviewMode":
        try:
            return cls(raw or "")
        except ValueError:
            return cls.CORE_CS
