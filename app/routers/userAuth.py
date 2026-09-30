from fastapi import APIRouter, HTTPException, Depends
import mysql.connector

from app.schema.user import UserCreate, UserResponse
from app.core.database import get_db
from app.services.auth_service import AuthService
from typing import List

router = APIRouter(prefix="/auth", tags=["auth"])

@router.post("/register", response_model=UserResponse)
def register_user(user: UserCreate):
    try:
        with get_db() as db:
            auth_service = AuthService(db)
            return auth_service.register_user(user)
    except mysql.connector.Error as err:
        raise HTTPException(status_code=500, detail=f"Database error occurred: {err}")

@router.get("/getdata", response_model=List[UserResponse])
def get_all_user_data():
    try:
        with get_db() as db:
            auth_service = AuthService(db)
            return auth_service.get_all_user_data()
    except mysql.connector.Error as err:
        raise HTTPException(status_code=500, detail=f"Database error occurred: {err}")