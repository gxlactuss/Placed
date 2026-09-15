import sys
from pathlib import Path

_here = Path(__file__).resolve()

for _parent in _here.parents:
    if (_parent / "database" / "__init__.py").exists():
        if str(_parent) not in sys.path:
            sys.path.insert(0, str(_parent))
        break

try:
    from dotenv import load_dotenv

    load_dotenv(_here.parent.parent / ".env")
except ImportError:
    pass
