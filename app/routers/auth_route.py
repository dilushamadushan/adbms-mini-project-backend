from typing import Optional
from fastapi import APIRouter, Cookie, Depends, HTTPException, Response, status

from app.core.security import REFRESH_TOKEN_EXPIRE_DAYS, get_current_user_payload
from app.schema.auth_schema import (
    LoginRequest,
    LogoutAllResponse,
    MessageResponse,
    TokenRefreshResponse,
    TokenResponse,
    UserInfo,
)
from app.services import auth_service

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/login", response_model=TokenResponse, status_code=status.HTTP_200_OK)
def login(payload: LoginRequest, response: Response):
    result = auth_service.login(payload.username, payload.password)

    max_age_seconds = REFRESH_TOKEN_EXPIRE_DAYS * 24 * 60 * 60
    response.set_cookie(
        key="refresh_token",
        value=result["refresh_token"],
        httponly=True,
        samesite="lax",
        secure=False,
        max_age=max_age_seconds,
        path="/",
    )

    return TokenResponse(
        access_token=result["access_token"],
        token_type="bearer",
        user=UserInfo(**result["user"]),
    )


@router.post("/refresh", response_model=TokenRefreshResponse, status_code=status.HTTP_200_OK)
def refresh_token(
    response: Response,
    refresh_token: Optional[str] = Cookie(default=None)
):

    result = auth_service.refresh_access_token(refresh_token)

    max_age_seconds = REFRESH_TOKEN_EXPIRE_DAYS * 24 * 60 * 60
    response.set_cookie(
        key="refresh_token",
        value=result["refresh_token"],
        httponly=True,
        samesite="lax",
        secure=False,
        max_age=max_age_seconds,
        path="/",
    )

    return TokenRefreshResponse(
        access_token=result["access_token"],
        token_type="bearer",
    )


@router.post("/logout", response_model=MessageResponse, status_code=status.HTTP_200_OK)
def logout(
    response: Response,
    refresh_token: Optional[str] = Cookie(default=None)
):

    auth_service.logout(refresh_token)
    response.delete_cookie(key="refresh_token", path="/")
    return MessageResponse(message="Successfully logged out")


@router.post("/logout-all", response_model=LogoutAllResponse, status_code=status.HTTP_200_OK)
def logout_all_sessions(
    response: Response,
    token_payload: dict = Depends(get_current_user_payload)
):

    user_id = int(token_payload.get("sub"))
    revoked_count = auth_service.logout_all_sessions(user_id)
    response.delete_cookie(key="refresh_token", path="/")
    return LogoutAllResponse(
        message=f"Successfully logged out of all {revoked_count} active sessions",
        revoked_sessions=revoked_count,
    )


@router.get("/me", response_model=UserInfo, status_code=status.HTTP_200_OK)
def get_current_user(token_payload: dict = Depends(get_current_user_payload)):

    user_id = int(token_payload.get("sub"))
    user = auth_service.get_current_user_profile(user_id)
    return UserInfo(
        user_id=user["user_id"],
        username=user["username"],
        role=user["role"],
        is_active=bool(user["is_active"]),
        active_sessions=user.get("active_sessions"),
    )
