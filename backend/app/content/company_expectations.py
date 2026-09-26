from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

DATA_FILE = Path(__file__).resolve().parent / "data" / "expected_qualities.json"


@dataclass(frozen=True)
class Quality:
    name: str
    description: str


@dataclass(frozen=True)
class CompanyExpectations:
    name: str
    values_label: str | None
    values: tuple[Quality, ...]
    interview_expectations: tuple[Quality, ...]
    workplace_qualities: tuple[Quality, ...]

    @property
    def principles(self) -> tuple[Quality, ...]:
        """The company's official values when published, otherwise the culture it hires for."""
        return self.values or self.workplace_qualities

    @property
    def principles_label(self) -> str:
        return self.values_label or "values"


def _qualities(items: list[dict], key: str) -> tuple[Quality, ...]:
    return tuple(Quality(item[key].strip(), item["description"].strip()) for item in items)


def _key(name: str) -> str:
    return name.strip().casefold()


@lru_cache(maxsize=1)
def _companies() -> dict[str, CompanyExpectations]:
    raw = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    companies: dict[str, CompanyExpectations] = {}
    for entry in raw["companies"]:
        company = CompanyExpectations(
            name=entry["company"].strip(),
            values_label=entry.get("values_label"),
            values=_qualities(entry.get("values", []), "name"),
            interview_expectations=_qualities(entry["interview_expectations"], "quality"),
            workplace_qualities=_qualities(entry["workplace_qualities"], "quality"),
        )
        companies[_key(company.name)] = company
    return companies


def find_company(name: str | None) -> CompanyExpectations | None:
    if not name or not name.strip():
        return None
    return _companies().get(_key(name))


def company_names() -> list[str]:
    return sorted((c.name for c in _companies().values()), key=str.casefold)
