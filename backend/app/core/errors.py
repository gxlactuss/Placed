"""App-wide error handlers so every error response is JSON with a string ``detail``.

The iOS client decodes ``{"detail": String}`` from any non-2xx response.
HTTPException already produces that shape and the rate-limit handler lives in
``app.core.rate_limit``; this module covers the other two cases:

* request validation errors (422), whose default ``detail`` is a list, and
* unhandled exceptions, which Starlette otherwise returns as plain text.
"""

import logging
from typing import Any

from fastapi import FastAPI, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

logger = logging.getLogger("app.errors")

GENERIC_SERVER_ERROR = "Something went wrong on our side. Please try again."
GENERIC_VALIDATION_ERROR = "The request was invalid."

# Where the value came from, not part of the field name.
_LOCATION_PREFIXES = {"body", "query", "path", "header", "cookie"}


def _field_name(loc: tuple | list) -> str:
    parts = [str(part) for part in loc]
    if len(parts) > 1 and parts[0] in _LOCATION_PREFIXES:
        parts = parts[1:]
    if parts == ["body"]:
        return "Request body"
    return ".".join(parts)


def validation_message(errors: list[dict[str, Any]]) -> str:
    """A short sentence from the first error, e.g. 'password: String should have at least 8 characters'."""
    if not errors:
        return GENERIC_VALIDATION_ERROR
    first = errors[0]
    message = str(first.get("msg") or "is invalid")
    field = _field_name(first.get("loc") or ())
    return f"{field}: {message}" if field else message


async def validation_exception_handler(
    request: Request, exc: RequestValidationError
) -> JSONResponse:
    errors = exc.errors()
    # Drop the rejected input so values like passwords are not echoed back.
    safe_errors = [{k: v for k, v in error.items() if k != "input"} for error in errors]
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "detail": validation_message(errors),
            "errors": jsonable_encoder(safe_errors),
        },
    )


async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception(
        "Unhandled error on %s %s", request.method, request.url.path, exc_info=exc
    )
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": GENERIC_SERVER_ERROR},
    )


def register_error_handlers(app: FastAPI) -> None:
    """Install the handlers. HTTPException and RateLimitExceeded keep their own."""
    app.add_exception_handler(RequestValidationError, validation_exception_handler)
    app.add_exception_handler(Exception, unhandled_exception_handler)
