import logging

import httpx

from app.core.config import settings
from app.core.logging import email_fingerprint

logger = logging.getLogger(__name__)


def send_verification_email(to_email: str, code: str) -> None:
    subject = "Your Placement Prep verification code"

    if not settings.resend_api_key:
        # Local dev only: with no RESEND_API_KEY there is no email to read the
        # code from, so print it. This branch never runs once a key is set.
        logger.warning(
            "dev_email RESEND_API_KEY unset, not sending; verification code for %s: %s",
            to_email,
            code,
        )
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
        logger.error(
            "verification_email_failed email_hash=%s error=%s detail=%s",
            email_fingerprint(to_email),
            type(exc).__name__,
            exc,
        )
