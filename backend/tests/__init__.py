"""Test package setup; runs before any test module imports app.core.config.

Settings refuses to start without a real JWT_SECRET_KEY, and CI has no
backend/.env, so the tests supply their own throwaway secret. This file only
runs when tests/ is imported as a package, i.e. when discovery's top-level
directory is backend/ (``-t .``), not tests/ itself:

    PYTHONPATH=..:. python -m unittest discover -s tests -t .
"""

import os

# Always override, so tests never sign tokens with a developer's real secret
# (app/__init__.py's load_dotenv does not overwrite variables already set).
os.environ["JWT_SECRET_KEY"] = "test-only-jwt-secret-not-for-real-use-0123456789"
