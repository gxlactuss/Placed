import logging

import httpx

from app.core.config import settings

logger = logging.getLogger("email")


def send_verification_email(to_email: str, code: str) -> None:
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
    except Exception as exc:
        logger.error("[email] failed to send to %s: %s", to_email, exc)
