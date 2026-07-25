import logging

import httpx

from app.core.config import settings

logger = logging.getLogger("email")


def send_verification_email(to_email: str, code: str) -> None:
    """Sends the 6-digit verification code.

    With no RESEND_API_KEY configured, runs in dev mode: logs the code to the
    server console so sign-up is fully testable without any provider. With a key,
    sends via Resend. Failures are logged, never raised — sign-up shouldn't fail
    because email is down, and the client can trigger a resend.
    """
    subject = "Your Placement Prep verification code"

    if not settings.resend_api_key:
        logger.warning("[email dev] Verification code for %s: %s", to_email, code)
        print(f"[email dev] Verification code for {to_email}: {code}", flush=True)
        return

    try:
        response = httpx.post(
            "https://api.resend.com/emails",
            headers={"Authorization": f"Bearer {settings.resend_api_key}"},
            json={
                "from": settings.email_from,
                "to": [to_email],
                "subject": subject,
                "html": (
                    f"<p>Your Placement Prep verification code is "
                    f"<strong style='font-size:20px'>{code}</strong>.</p>"
                    f"<p>It expires in {settings.verification_code_ttl_minutes} minutes.</p>"
                ),
            },
            timeout=10.0,
        )
        response.raise_for_status()
    except Exception as exc:  # noqa: BLE001 — never let email break sign-up
        logger.error("[email] failed to send to %s: %s", to_email, exc)
