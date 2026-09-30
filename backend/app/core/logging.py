"""Application logging: one stdout handler on the "app" logger namespace.

Uvicorn configures only its own loggers, so without this every ``app.*``
INFO line is dropped and WARNING+ falls through to Python's bare
last-resort handler. Uvicorn's loggers are deliberately left alone.
"""

import hashlib
import hmac
import json
import logging
import sys
from datetime import datetime, timezone

from app.core.config import settings

APP_LOGGER = "app"
_HANDLER_NAME = "app-stdout"


class KeyValueFormatter(logging.Formatter):
    """One line per record: ts=... level=... logger=... msg="..." [exc="..."].

    ``msg`` and ``exc`` are JSON-quoted, so newlines or quotes in a message
    (or in user-controlled values interpolated into it) can't split a line.
    """

    def format(self, record: logging.LogRecord) -> str:
        ts = datetime.fromtimestamp(record.created, tz=timezone.utc)
        line = (
            f"ts={ts.strftime('%Y-%m-%dT%H:%M:%S')}.{int(record.msecs):03d}Z "
            f"level={record.levelname} logger={record.name} "
            f"msg={json.dumps(record.getMessage())}"
        )
        if record.exc_info:
            line += f" exc={json.dumps(self.formatException(record.exc_info))}"
        return line


def configure_logging(level: str | None = None) -> None:
    """Attach the stdout handler to the "app" logger. Safe to call more than once."""
    logger = logging.getLogger(APP_LOGGER)
    logger.setLevel((level or settings.log_level).upper())
    # Own the output for this namespace so a root handler added elsewhere
    # doesn't print every line twice.
    logger.propagate = False
    if any(h.get_name() == _HANDLER_NAME for h in logger.handlers):
        return
    handler = logging.StreamHandler(sys.stdout)
    handler.set_name(_HANDLER_NAME)
    handler.setFormatter(KeyValueFormatter())
    logger.addHandler(handler)


def email_fingerprint(email: str) -> str:
    """Stable, non-reversible tag for correlating log lines about one address.

    Keyed with the JWT secret so the tag can't be reversed by hashing a list
    of candidate addresses.
    """
    normalized = email.strip().lower().encode()
    digest = hmac.new(settings.jwt_secret_key.encode(), normalized, hashlib.sha256)
    return digest.hexdigest()[:12]
