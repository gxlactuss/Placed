"""The app's one door to a language model.

Groq is primary and Gemini is the fallback, but nothing outside this module
knows that: routes call `generate_first_question` / `generate_follow_up` /
`summarize_projects` and never see a provider. Swapping or reordering providers
is a change to `settings.llm_chain` and the two `_call_*` functions below.

Groq speaks the OpenAI chat-completions API, so it needs no SDK — just the
`httpx` we already depend on for the OAuth exchange.
"""

import logging
import re

import google.generativeai as genai
import httpx
from fastapi import HTTPException

from app.core.config import settings
from app.services.interview_prompts import (
    END_INTERVIEW_SENTINEL,
    InterviewMode,
    follow_up_prompt,
    opening_prompt,
)

genai.configure(api_key=settings.gemini_api_key)

logger = logging.getLogger(__name__)

_TIMEOUT = 60.0

#: Some open-weight models (qwen3.6 among them) emit their chain of thought
#: inside `content` rather than a separate field. Left alone it gets asked to
#: the candidate as the interview question. Such models are kept out of the
#: default chain, but this strips the block defensively in case one is
#: configured — an unclosed tag means the whole reply was reasoning.
_THINK_BLOCK = re.compile(r"<think>.*?</think>", re.DOTALL | re.IGNORECASE)
_UNCLOSED_THINK = re.compile(r"<think>.*", re.DOTALL | re.IGNORECASE)


def _strip_reasoning(text: str) -> str:
    return _UNCLOSED_THINK.sub("", _THINK_BLOCK.sub("", text)).strip()


class _QuotaExhausted(Exception):
    """Provider refused this model on rate/quota grounds — try the next one."""


class _AuthRejected(Exception):
    """The provider rejected our key. Trying more of its models is pointless."""


# ---- Providers -------------------------------------------------------------


def _call_groq(model: str, prompt: str) -> str:
    response = httpx.post(
        f"{settings.groq_base_url}/chat/completions",
        headers={"Authorization": f"Bearer {settings.groq_api_key}"},
        json={"model": model, "messages": [{"role": "user", "content": prompt}]},
        timeout=_TIMEOUT,
    )
    if response.status_code == 429:
        raise _QuotaExhausted(response.text[:200])
    if response.status_code in (401, 403):
        raise _AuthRejected(response.text[:200])
    # A retired model id comes back as 404 — treat it like an exhausted one so
    # the chain moves on rather than taking the whole interview down.
    if response.status_code == 404:
        raise _QuotaExhausted(f"unknown model {model}")
    response.raise_for_status()
    return _strip_reasoning(response.json()["choices"][0]["message"]["content"])


def transcribe_audio(data: bytes, filename: str, content_type: str | None) -> str:
    """Speech-to-text via Groq Whisper — how every spoken answer becomes text.

    Unlike `_generate` there's no provider chain: Gemini's audio support is a
    different API shape, and maintaining a second one isn't worth it until this
    actually falls over.
    """
    if not settings.groq_api_key:
        raise HTTPException(status_code=503, detail="Voice transcription is not configured.")

    try:
        response = httpx.post(
            f"{settings.groq_base_url}/audio/transcriptions",
            headers={"Authorization": f"Bearer {settings.groq_api_key}"},
            files={"file": (filename, data, content_type or "application/octet-stream")},
            data={"model": settings.groq_transcription_model, "response_format": "json"},
            timeout=120.0,  # generous: upload + transcode + transcribe
        )
    except httpx.HTTPError as exc:
        logger.exception("Transcription transport failure")
        raise HTTPException(
            status_code=502, detail="Couldn't reach the transcription service."
        ) from exc

    if response.status_code == 429:
        raise HTTPException(
            status_code=503,
            detail="Voice transcription has hit its usage limit for now. Try again shortly.",
        )
    if response.status_code in (401, 403):
        logger.error("Groq rejected our key for transcription")
        raise HTTPException(status_code=503, detail="Voice transcription is not configured.")
    if response.status_code >= 400:
        logger.error("Transcription failed (%s): %s", response.status_code, response.text[:300])
        raise HTTPException(status_code=502, detail="Couldn't transcribe that recording.")

    return response.json().get("text", "").strip()


def _call_gemini(model: str, prompt: str) -> str:
    try:
        return genai.GenerativeModel(model).generate_content(prompt).text.strip()
    except Exception as exc:  # noqa: BLE001 — the SDK's failures are all opaque
        # Matched on message, not exception class: the SDK raises
        # `ResourceExhausted` on some paths and a plain `GoogleAPIError` on
        # others, and the class has moved between versions.
        text = str(exc)
        if "429" in text or "RESOURCE_EXHAUSTED" in text or "exceeded your current quota" in text:
            raise _QuotaExhausted(text[:200]) from exc
        raise


_PROVIDERS = {"groq": _call_groq, "gemini": _call_gemini}


# ---- The one funnel --------------------------------------------------------


def _generate(prompt: str) -> str:
    """Calls the first provider/model in the chain that will answer.

    Free-tier caps are per model *and* per project, so the chain spans providers
    as well as models — one exhausted account can't take the feature offline for
    the rest of the day.

    Provider errors are never passed through verbatim: Gemini's 429 body is a
    ~40-line quota dump that used to land in the student's face mid-interview.
    """
    chain = settings.llm_chain
    if not chain:
        raise HTTPException(status_code=503, detail="Interview service is not configured.")

    exhausted: list[str] = []
    # A provider whose key was rejected — its remaining models are pointless to
    # try. Tracked in a set because rebinding `chain` mid-loop would not affect
    # the iteration already in flight.
    dead_providers: set[str] = set()

    for provider, model in chain:
        if provider in dead_providers:
            continue
        try:
            return _PROVIDERS[provider](model, prompt)
        except _QuotaExhausted as exc:
            exhausted.append(f"{provider}/{model}")
            logger.warning("LLM quota exhausted for %s/%s (%s), trying next", provider, model, exc)
            continue
        except _AuthRejected as exc:
            dead_providers.add(provider)
            exhausted.append(f"{provider}/* (auth rejected)")
            logger.error("LLM provider %s rejected our key: %s", provider, exc)
            continue
        except Exception as exc:  # noqa: BLE001
            logger.exception("LLM call failed on %s/%s", provider, model)
            raise HTTPException(
                status_code=502,
                detail="The interview service is having trouble right now. Please try again.",
            ) from exc

    logger.error("Every LLM provider/model exhausted: %s", ", ".join(exhausted))
    raise HTTPException(
        status_code=503,
        detail=(
            "The interview service has hit its usage limit for now. "
            "Please try again in a few minutes."
        ),
    )


def generate_first_question(
    target_role: str, mode: InterviewMode, context: dict | None = None
) -> str:
    """Opens a round. The prompt is entirely mode-dependent — see
    `interview_prompts`, which owns the wording."""
    return _generate(opening_prompt(target_role, mode, context or {}))


#: Sentinel the model returns when the extracted text holds no recognisable
#: projects. A sentinel rather than an empty reply so "no projects" is
#: distinguishable from a failed generation.
NO_PROJECTS_SENTINEL = "NO_PROJECTS_FOUND"


def summarize_projects(target_role: str, projects_text: str) -> tuple[str, bool]:
    """Turns the resume's projects section into an interviewer's brief.

    One call, by design: the client does OCR and section extraction on-device,
    so this is the single round trip the whole resume flow costs. That matters —
    the free tier allows only 5 requests per minute across the entire project.

    Returns (summary, no_projects_found).
    """
    prompt = (
        f"You are preparing to interview a candidate for a '{target_role}' role.\n"
        f"Below is the projects section of their resume, extracted on-device by "
        f"OCR — expect noisy line breaks and the occasional misread character.\n\n"
        f"---\n{projects_text}\n---\n\n"
        f"Summarise every project you can identify. For each, give the project "
        f"name, one sentence on what it does, and the main technologies used. "
        f"Reply as a short bulleted list, one bullet per project, no preamble.\n"
        f"If the text contains no recognisable projects, reply with exactly: "
        f"{NO_PROJECTS_SENTINEL}"
    )
    summary = _generate(prompt)
    if NO_PROJECTS_SENTINEL in summary:
        return "", True
    return summary, False


def generate_follow_up(
    target_role: str,
    mode: InterviewMode,
    context: dict | None,
    transcript: list[dict],
    latest_answer: str,
) -> tuple[str, bool]:
    """Given the running transcript and the candidate's latest spoken answer,
    returns (next_ai_message, ended_early).

    `ended_early` is the interviewer walking out — today the only reason is a
    candidate acting in bad faith (see `_CONDUCT_RULES`). It is *not* the round
    finishing normally: the model is never asked to judge when enough ground has
    been covered, because it has no idea how many rounds the client allows. The
    client still caps the count for that.
    """
    prompt = follow_up_prompt(target_role, mode, context or {}, transcript, latest_answer)
    reply = _generate(prompt)

    if END_INTERVIEW_SENTINEL not in reply:
        return reply, False

    cleaned = reply.replace(END_INTERVIEW_SENTINEL, "").strip()
    # A reply that was *only* the marker would render as an empty bubble at the
    # one moment the student most needs to be told what just happened.
    return cleaned or "I'm going to stop the interview here. Let's try again another time.", True
