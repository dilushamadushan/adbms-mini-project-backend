from pydantic import BaseModel
from typing import Optional

class LoginRequest(BaseModel):
    username: str
    password: str

class UserInfo(BaseModel):
    user_id: int
    username: str
    role: str
    is_active: Optional[bool] = None
    active_sessions: Optional[int] = None

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserInfo

class TokenRefreshResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"

class MessageResponse(BaseModel):
    message: str

class LogoutAllResponse(BaseModel):
    message: str
    revoked_sessions: int
