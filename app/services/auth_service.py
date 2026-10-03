from fastapi import HTTPException
from mysql.connector.connection import MySQLConnection

from app.repositories.user_repository import UserRepository
from app.schema.user import UserCreate
from app.core.security import hash_password, verify_password, create_access_token
from app.schema.user import UserLogin

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

    def login_user(self, user_login: UserLogin):
        user = self.repo.get_user_for_login(user_login.username)
        if not user or not verify_password(user_login.password, user['hashed_password']):
            raise HTTPException(status_code=401, detail="Invalid username or password")
            
        access_token = create_access_token(data={"sub": user["username"]})
        return {"access_token": access_token, "token_type": "bearer"}