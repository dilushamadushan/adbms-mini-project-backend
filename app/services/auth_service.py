import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional
from fastapi import BackgroundTasks, HTTPException, status

from app.core.database import get_db
from app.core.email import send_password_reset_otp_email
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


def generate_otp() -> str:
    return f"{secrets.randbelow(900000) + 100000:06d}"


def request_password_reset_otp(
    email: str,
    background_tasks: Optional[BackgroundTasks] = None
) -> dict:
    email_clean = email.strip().lower()

    with get_db() as conn:
        user = auth_repo.get_user_by_email(conn, email_clean)
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No account found with this email address",
            )

        if not user.get("is_active", True):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Account is deactivated. Please contact an administrator.",
            )

        otp_code = generate_otp()
        expire_minutes = 10
        expires_at = datetime.now() + timedelta(minutes=expire_minutes)

        auth_repo.create_password_reset_otp(
            conn=conn,
            user_id=user["user_id"],
            email=email_clean,
            otp_code=otp_code,
            expires_at=expires_at,
        )

        username = user["username"]

    if background_tasks is not None:
        background_tasks.add_task(
            send_password_reset_otp_email,
            email_clean,
            username,
            otp_code,
            expire_minutes,
        )
    else:
        send_password_reset_otp_email(
            email_clean,
            username,
            otp_code,
            expire_minutes,
        )

    return {
        "message": f"A 6-digit verification code has been sent to {email_clean}. It will expire in {expire_minutes} minutes."
    }


def verify_password_reset_otp(email: str, otp_code: str) -> dict:
    email_clean = email.strip().lower()
    otp_code_clean = otp_code.strip()

    with get_db() as conn:
        otp_record = auth_repo.get_latest_valid_otp(conn, email_clean)
        if not otp_record or otp_record["otp_code"].strip() != otp_code_clean:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid or expired verification code",
            )

        now = datetime.now()
        expires_at = otp_record["expires_at"]
        if hasattr(expires_at, "tzinfo") and expires_at.tzinfo is not None:
            now = datetime.now(timezone.utc)

        if now > expires_at:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Verification code has expired. Please request a new one.",
            )

        return {
            "valid": True,
            "message": "OTP verified successfully. You may now set a new password.",
        }


def reset_password_with_otp(
    email: str,
    otp_code: str,
    new_password: str,
    confirm_password: Optional[str] = None,
) -> dict:
    email_clean = email.strip().lower()
    otp_code_clean = otp_code.strip()

    if confirm_password is not None and confirm_password != new_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Passwords do not match",
        )

    if len(new_password) < 6:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must be at least 6 characters long",
        )

    with get_db() as conn:
        user = auth_repo.get_user_by_email(conn, email_clean)
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found",
            )

        otp_record = auth_repo.get_latest_valid_otp(conn, email_clean)
        if not otp_record or otp_record["otp_code"].strip() != otp_code_clean:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid or expired verification code",
            )

        now = datetime.now()
        expires_at = otp_record["expires_at"]
        if hasattr(expires_at, "tzinfo") and expires_at.tzinfo is not None:
            now = datetime.now(timezone.utc)

        if now > expires_at:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Verification code has expired. Please request a new one.",
            )

        auth_repo.mark_otp_as_used(conn, otp_record["otp_id"])

        new_password_hash = hashlib.sha256(new_password.encode("utf-8")).hexdigest()
        auth_repo.update_user_password(conn, user["user_id"], new_password_hash)

        auth_repo.revoke_all_user_tokens_sp(conn, user["user_id"])

        return {
            "message": "Password has been successfully reset. Please log in with your new password."
        }
