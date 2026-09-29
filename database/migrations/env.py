from logging.config import fileConfig

from alembic import context
from sqlalchemy import create_engine
from sqlmodel import SQLModel

import database.models  # noqa: F401  (registers every table on SQLModel.metadata)

config = context.config

# init_db() hands us its own connection; only configure logging for CLI runs so
# we don't clobber uvicorn's loggers at app startup.
_external_connection = config.attributes.get("connection")
if _external_connection is None and config.config_file_name is not None:
    fileConfig(config.config_file_name, disable_existing_loggers=False)

target_metadata = SQLModel.metadata

_CONFIGURE_KWARGS = dict(
    target_metadata=target_metadata,
    render_as_batch=True,  # SQLite can't ALTER most things in place
    compare_type=True,
)


def _database_url() -> str:
    from database import db

    return config.get_main_option("sqlalchemy.url") or db.DATABASE_URL


def run_migrations_offline() -> None:
    context.configure(
        url=_database_url(),
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        **_CONFIGURE_KWARGS,
    )
    with context.begin_transaction():
        context.run_migrations()


def _run_with_connection(connection) -> None:
    context.configure(connection=connection, **_CONFIGURE_KWARGS)
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    if _external_connection is not None:
        _run_with_connection(_external_connection)
        return

    engine = create_engine(_database_url())
    try:
        with engine.connect() as connection:
            _run_with_connection(connection)
    finally:
        engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
