import logging
import os
from contextlib import contextmanager
from typing import Generator

import mysql.connector
from dotenv import load_dotenv
from mysql.connector import Error, pooling
from mysql.connector.connection import MySQLConnection

logger = logging.getLogger(__name__)

load_dotenv()

_REQUIRED_ENV = ("DB_HOST", "DB_USER", "DB_NAME")

def _build_config() -> dict:
    missing = [key for key in _REQUIRED_ENV if not os.getenv(key)]
    if missing:
        raise EnvironmentError(
            f"Missing required environment variable(s): {', '.join(missing)}. "
            "Please set them in your .env file."
        )

    return {
        "host":             os.getenv("DB_HOST", "localhost"),
        "port":             int(os.getenv("DB_PORT", "3306")),
        "user":             os.getenv("DB_USER"),
        "password":         os.getenv("DB_PASSWORD", ""),
        "database":         os.getenv("DB_NAME"),
        "charset":          "utf8mb4",
        "collation":        "utf8mb4_unicode_ci",
        "autocommit":       False,
        "connection_timeout": int(os.getenv("DB_CONNECT_TIMEOUT", "10")),
    }

_POOL_NAME = "app_pool"
_POOL_SIZE  = int(os.getenv("DB_POOL_SIZE", "10"))

_pool: pooling.MySQLConnectionPool | None = None


def init_connection_pool() -> None:
    global _pool

    if _pool is not None:
        logger.warning("Connection pool already initialised – skipping.")
        return

    db_config = _build_config()

    try:
        _pool = pooling.MySQLConnectionPool(
            pool_name=_POOL_NAME,
            pool_size=_POOL_SIZE,
            pool_reset_session=True,
            **db_config,
        )
        logger.info(
            "MySQL connection pool '%s' created  (host=%s  db=%s  pool_size=%d)",
            _POOL_NAME,
            db_config["host"],
            db_config["database"],
            _POOL_SIZE,
        )
    except Error as exc:
        logger.critical("Failed to create MySQL connection pool: %s", exc)
        raise RuntimeError(f"Database initialisation failed: {exc}") from exc


def close_connection_pool() -> None:
    global _pool
    if _pool is not None:
        _pool = None
        logger.info("MySQL connection pool '%s' released.", _POOL_NAME)


@contextmanager
def get_db() -> Generator[MySQLConnection, None, None]:
    if _pool is None:
        raise RuntimeError(
            "Database connection pool is not initialised. "
            "Ensure init_connection_pool() is called at startup."
        )

    conn: MySQLConnection = _pool.get_connection()
    try:
        yield conn
        conn.commit()          
    except Exception:
        conn.rollback()         
        raise
    finally:
        conn.close()            


def ping_db() -> bool:
    try:
        with get_db() as conn:
            conn.ping(reconnect=False, attempts=1, delay=0)
        return True
    except Exception as exc:
        logger.warning("DB health check failed: %s", exc)
        return False