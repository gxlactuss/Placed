"""Backend application package.

Bootstraps two things before anything else imports, so the backend works no
matter which directory uvicorn is launched from:

1. Puts the repo root (which contains the sibling top-level `database` package)
   on `sys.path`, by walking up until the package is found.
2. Loads `backend/.env` into the environment, so the standalone `database`
   package — which reads `DATABASE_URL` from `os.environ` — sees local config.
   A no-op in production, where env vars are set directly (e.g. Fly secrets).
"""

import sys
from pathlib import Path

_here = Path(__file__).resolve()

# 1. Make the `database` package importable.
for _parent in _here.parents:
    if (_parent / "database" / "__init__.py").exists():
        if str(_parent) not in sys.path:
            sys.path.insert(0, str(_parent))
        break

# 2. Load backend/.env (this file lives at backend/app/__init__.py).
try:
    from dotenv import load_dotenv

    load_dotenv(_here.parent.parent / ".env")
except ImportError:
    pass
