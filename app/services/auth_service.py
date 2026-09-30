from fastapi import HTTPException
from mysql.connector.connection import MySQLConnection

from app.repositories.user_repository import UserRepository
from app.schema.user import UserCreate
from app.core.security import hash_password

class AuthService:
    def __init__(self, db: MySQLConnection):
        self.repo = UserRepository(db)
        
    def register_user(self, user: UserCreate):
        existing_user = self.repo.get_by_username(user.username)
        if existing_user:
            raise HTTPException(status_code=400, detail="Username is already registered")
            
        hashed_pw = hash_password(user.password)
        new_user = self.repo.create(
            username=user.username, 
            hashed_password=hashed_pw,
            full_name=user.full_name,
            last_name=user.last_name,
            age=user.age
        )
        return new_user

    def get_all_user_data(self):
        return self.repo.get_by_all()