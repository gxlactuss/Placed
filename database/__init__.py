"""Top-level database package: SQLModel table models and the engine/session.

Kept independent of the backend app so the schema and connection live in one
place. The backend imports `database.db` (engine, `get_session`, `init_db`) and
`database.models.*` (the tables).
"""
