import random
import string
import hashlib
from app.core.database import get_db
from app.repositories.user_repo import create_staff_user, create_patient_user, update_is_active, get_user_by_username, get_all_patients, get_all_staff
from app.schema.user_schema import StaffUserCreate, StaffUserResponse, PatientUserCreate, PatientUserResponse

def generate_username(first_name: str, last_name: str) -> str:
    num = random.randint(100, 999)
    return f"{first_name.lower()}.{last_name.lower()}{num}"

def generate_password(first_name: str) -> str:
    chars = "".join(random.choices(string.ascii_letters + string.digits, k=4))
    return f"{first_name.capitalize()}@{chars}"

def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

def create_new_staff_user(data: StaffUserCreate) -> StaffUserResponse:
    username = generate_username(data.first_name, data.last_name)
    raw_password = generate_password(data.first_name)
    password_hash = hash_password(raw_password)
    
    user_data = {
        "username": username,
        "password_hash": password_hash,
        "role": data.role
    }
    
    staff_data = {
        "dept_id": data.dept_id,
        "first_name": data.first_name,
        "last_name": data.last_name,
        "specialty": data.specialty
    }
    
    with get_db() as conn:
        ids = create_staff_user(conn, user_data, staff_data)
        
    return StaffUserResponse(
        user_id=ids["user_id"],
        staff_id=ids["staff_id"],
        username=username,
        role=data.role,
        first_name=data.first_name,
        last_name=data.last_name,
        dept_id=data.dept_id,
        specialty=data.specialty,
        raw_password=raw_password
    )

def create_new_patient_user(data: PatientUserCreate) -> PatientUserResponse:
    username = generate_username(data.first_name, data.last_name)
    raw_password = generate_password(data.first_name)
    password_hash = hash_password(raw_password)
    
    user_data = {
        "username": username,
        "password_hash": password_hash,
        "role": "patient"
    }
    
    patient_data = {
        "first_name": data.first_name,
        "last_name": data.last_name,
        "dob": data.dob,
        "blood_group": data.blood_group,
        "emergency_contact": data.emergency_contact,
        "allergies": data.allergies
    }
    
    with get_db() as conn:
        ids = create_patient_user(conn, user_data, patient_data)
        
    return PatientUserResponse(
        user_id=ids["user_id"],
        patient_id=ids["patient_id"],
        username=username,
        role="patient",
        first_name=data.first_name,
        last_name=data.last_name,
        raw_password=raw_password
    )

def update_user_status(user_id: int, is_active: bool) -> bool:
    with get_db() as conn:
        rows_affected = update_is_active(conn, user_id, is_active)
        if rows_affected == 0:
            raise ValueError(f"User with id {user_id} not found")
        return True

def loging_user(username:str, password:str) -> str:
    with get_db() as conn:
        user = get_user_by_username(conn, username)
        if not user:
            raise ValueError(f"User with username {username} not found")
        if user["password_hash"] != hash_password(password):
            raise ValueError(f"Invalid password for user {username}")
        return user["role"]

def GetAllPatients() -> list:
    with get_db() as conn:
        return get_all_patients(conn)

def GetAllStaff() -> list:
    with get_db() as conn:
        return get_all_staff(conn)