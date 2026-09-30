from pydantic import BaseModel
from typing import Optional

class UserCreate(BaseModel):
    username: str
    password: str
    full_name: str
    last_name: str
    age: Optional[int] = None

class UserResponse(BaseModel):
    user_id: int
    username: str
    full_name: str
    last_name: str
    age: Optional[int] = None

    class Config:
        from_attributes = True
