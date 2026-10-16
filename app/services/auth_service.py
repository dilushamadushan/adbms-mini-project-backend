from datetime import datetime, timezone
from typing import Optional
from fastapi import HTTPException, status

from app.core.database import get_db
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_token,
    verify_password,
)
from app.repositories import auth_repo


def login(username: str, password: str) -> dict:
    with get_db() as conn:
        user = auth_repo.get_user_by_username(conn, username)
        if not user or not verify_password(password, user["password_hash"]):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid username or password",
                headers={"WWW-Authenticate": "Bearer"},
            )

        user_id = user["user_id"]
        role = user["role"]

        access_token = create_access_token(
            data={"sub": str(user_id), "username": user["username"], "role": role}
        )

        refresh_token_str, expires_at = create_refresh_token(
            data={"sub": str(user_id)}
        )

        token_hash = hash_token(refresh_token_str)
        naive_expires_at = expires_at.astimezone(timezone.utc).replace(tzinfo=None)
        auth_repo.store_refresh_token(conn, user_id, token_hash, naive_expires_at)

        active_sessions = auth_repo.get_active_session_count_fn(conn, user_id)

        return {
            "access_token": access_token,
            "refresh_token": refresh_token_str,
            "expires_at": expires_at,
            "user": {
                "user_id": user_id,
                "username": user["username"],
                "role": role,
                "is_active": bool(user["is_active"]),
                "active_sessions": active_sessions,
            },
        }


def refresh_access_token(raw_refresh_token: Optional[str]) -> dict:
    if not raw_refresh_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token missing in request cookies",
            headers={"WWW-Authenticate": "Bearer"},
        )

    payload = decode_token(raw_refresh_token)
    if payload.get("type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token type",
            headers={"WWW-Authenticate": "Bearer"},
        )

    sub = payload.get("sub")
    if not sub:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload",
        )

    user_id = int(sub)
    old_token_hash = hash_token(raw_refresh_token)

    with get_db() as conn:
        if not auth_repo.is_token_active_fn(conn, old_token_hash):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Refresh token is invalid, revoked, or expired",
            )

        new_refresh_token_str, new_expires_at = create_refresh_token(
            data={"sub": str(user_id)}
        )
        new_token_hash = hash_token(new_refresh_token_str)
        naive_expires_at = new_expires_at.astimezone(timezone.utc).replace(tzinfo=None)

        user = auth_repo.rotate_refresh_token_sp(
            conn, old_token_hash, new_token_hash, naive_expires_at
        )

        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User associated with token not found",
            )

        new_access_token = create_access_token(
            data={"sub": str(user_id), "username": user["username"], "role": user["role"]}
        )

        return {
            "access_token": new_access_token,
            "refresh_token": new_refresh_token_str,
            "expires_at": new_expires_at,
        }


def logout(raw_refresh_token: Optional[str]) -> None:
    if raw_refresh_token:
        token_hash = hash_token(raw_refresh_token)
        with get_db() as conn:
            auth_repo.delete_refresh_token(conn, token_hash)


def logout_all_sessions(user_id: int) -> int:
    with get_db() as conn:
        return auth_repo.revoke_all_user_tokens_sp(conn, user_id)


def get_current_user_profile(user_id: int) -> dict:
    with get_db() as conn:
        user = auth_repo.get_user_by_id(conn, user_id)
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found",
            )
        user["active_sessions"] = auth_repo.get_active_session_count_fn(conn, user_id)
        return user
