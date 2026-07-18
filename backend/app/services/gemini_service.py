import google.generativeai as genai

from app.core.config import settings

genai.configure(api_key=settings.gemini_api_key)

_MODEL_NAME = "gemini-1.5-flash"


def generate_first_question(target_role: str) -> str:
    """Kicks off a mock interview with a role-specific opening question."""
    model = genai.GenerativeModel(_MODEL_NAME)
    prompt = (
        f"You are a technical interviewer conducting a mock interview for a "
        f"'{target_role}' position. Ask a single, focused opening interview question. "
        f"Do not include any preamble, just the question."
    )
    # TODO: add retry/error handling and response safety checks for production use
    response = model.generate_content(prompt)
    return response.text.strip()


def generate_follow_up(target_role: str, transcript: list[dict], latest_answer: str) -> tuple[str, bool]:
    """
    Given the running transcript and the candidate's latest spoken answer,
    returns (next_ai_message, interview_complete).
    """
    model = genai.GenerativeModel(_MODEL_NAME)
    history_text = "\n".join(f"{turn['speaker']}: {turn['text']}" for turn in transcript)
    prompt = (
        f"You are interviewing a candidate for a '{target_role}' role.\n"
        f"Conversation so far:\n{history_text}\n"
        f"Candidate's latest answer: {latest_answer}\n\n"
        f"Respond with either a relevant follow-up question, or, if enough ground has "
        f"been covered, a closing remark. Keep it concise and conversational."
    )
    # TODO: parse a structured signal (e.g. JSON with `complete: bool`) instead of
    # inferring completion from response text.
    response = model.generate_content(prompt)
    ai_message = response.text.strip()
    interview_complete = False
    return ai_message, interview_complete
