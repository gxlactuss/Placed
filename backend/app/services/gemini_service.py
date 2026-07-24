import google.generativeai as genai
from fastapi import HTTPException

from app.core.config import settings

genai.configure(api_key=settings.gemini_api_key)


def _generate(prompt: str) -> str:
    """Single point where we call Gemini, so error handling lives in one place.

    Surfaces a clean 502 to the client instead of a bare 500 when the model
    call fails (bad/absent API key, retired model name, quota, transport).
    """
    if not settings.gemini_api_key:
        raise HTTPException(status_code=503, detail="Interview service is not configured.")
    try:
        model = genai.GenerativeModel(settings.gemini_model)
        response = model.generate_content(prompt)
        return response.text.strip()
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001 — any SDK/transport failure maps to 502
        raise HTTPException(status_code=502, detail=f"Interview model error: {exc}") from exc


def generate_first_question(target_role: str) -> str:
    """Kicks off a mock interview with a role-specific opening question."""
    prompt = (
        f"You are a technical interviewer conducting a mock interview for a "
        f"'{target_role}' position. Ask a single, focused opening interview question. "
        f"Do not include any preamble, just the question."
    )
    return _generate(prompt)


def generate_follow_up(target_role: str, transcript: list[dict], latest_answer: str) -> tuple[str, bool]:
    """
    Given the running transcript and the candidate's latest spoken answer,
    returns (next_ai_message, interview_complete).
    """
    history_text = "\n".join(f"{turn['speaker']}: {turn['text']}" for turn in transcript)
    prompt = (
        f"You are interviewing a candidate for a '{target_role}' role.\n"
        f"Conversation so far:\n{history_text}\n"
        f"Candidate's latest answer: {latest_answer}\n\n"
        f"Respond with either a relevant follow-up question, or, if enough ground has "
        f"been covered, a closing remark. Keep it concise and conversational."
    )
    # TODO: parse a structured signal (e.g. JSON with `complete: bool`) instead of
    # inferring completion from response text. For now the client caps the round
    # count, so this always reports the interview as still in progress.
    ai_message = _generate(prompt)
    interview_complete = False
    return ai_message, interview_complete
