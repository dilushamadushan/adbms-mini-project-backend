import random
import string
import hashlib
from typing import Optional
from fastapi import BackgroundTasks
from app.core.database import get_db
from app.core.email import send_staff_welcome_email, send_patient_welcome_email
from app.repositories.user_repo import (
    create_staff_user,
    create_patient_user,
    update_is_active,
    get_user_by_username,
    get_all_patients,
    get_all_staff,
    get_patient_profile_by_user_id,
    get_staff_by_id,
    update_staff_user,
    check_staff_dependencies,
    delete_staff_user,
    check_email_exists_excluding_user,
    check_username_exists_excluding_user,
    check_department_exists,
)
from app.schema.user_schema import (
    StaffUserCreate,
    StaffUserResponse,
    StaffUserUpdate,
    StaffDeleteResponse,
    PatientUserCreate,
    PatientUserResponse,
    PatientProfileResponse,
)

def generate_username(first_name: str, last_name: str) -> str:
    num = random.randint(100, 999)
    return f"{first_name.lower()}.{last_name.lower()}{num}"

def generate_password(first_name: str) -> str:
    chars = "".join(random.choices(string.ascii_letters + string.digits, k=4))
    return f"{first_name.capitalize()}@{chars}"

def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

def create_new_staff_user(data: StaffUserCreate, background_tasks: Optional[BackgroundTasks] = None) -> StaffUserResponse:
    username = generate_username(data.first_name, data.last_name)
    raw_password = generate_password(data.first_name)
    password_hash = hash_password(raw_password)
    
    user_data = {
        "username": username,
        "email": str(data.email),
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
        
    if background_tasks is not None:
        background_tasks.add_task(
            send_staff_welcome_email,
            str(data.email),
            data.first_name,
            data.last_name,
            username,
            raw_password,
            data.role
        )
    else:
        send_staff_welcome_email(
            str(data.email),
            data.first_name,
            data.last_name,
            username,
            raw_password,
            data.role
        )

    return StaffUserResponse(
        user_id=ids["user_id"],
        staff_id=ids["staff_id"],
        username=username,
        email=str(data.email),
        role=data.role,
        first_name=data.first_name,
        last_name=data.last_name,
        dept_id=data.dept_id,
        specialty=data.specialty,
        raw_password=raw_password
    )

def create_new_patient_user(data: PatientUserCreate, background_tasks: Optional[BackgroundTasks] = None) -> PatientUserResponse:
    username = generate_username(data.first_name, data.last_name)
    raw_password = generate_password(data.first_name)
    password_hash = hash_password(raw_password)
    
    user_data = {
        "username": username,
        "email": str(data.email),
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

    if background_tasks is not None:
        background_tasks.add_task(
            send_patient_welcome_email,
            str(data.email),
            data.first_name,
            data.last_name,
            username,
            raw_password
        )
    else:
        send_patient_welcome_email(
            str(data.email),
            data.first_name,
            data.last_name,
            username,
            raw_password
        )

    return PatientUserResponse(
        user_id=ids["user_id"],
        patient_id=ids["patient_id"],
        username=username,
        email=str(data.email),
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

def GetAllPatients() -> list:
    with get_db() as conn:
        return get_all_patients(conn)


def get_patient_profile(user_id: int) -> PatientProfileResponse:
    with get_db() as conn:
        profile = get_patient_profile_by_user_id(conn, user_id)
        if not profile:
            raise ValueError("Patient profile not found")
        return PatientProfileResponse(**profile)


def GetAllStaff() -> list:
    with get_db() as conn:
        return get_all_staff(conn)


def get_staff_member(staff_id: int) -> StaffUserResponse:
    with get_db() as conn:
        staff = get_staff_by_id(conn, staff_id)
        if not staff:
            raise ValueError(f"Staff member with ID {staff_id} not found")
        return StaffUserResponse(**staff)


def update_staff_member(staff_id: int, data: StaffUserUpdate) -> StaffUserResponse:
    with get_db() as conn:
        existing = get_staff_by_id(conn, staff_id)
        if not existing:
            raise ValueError(f"Staff member with ID {staff_id} not found")

        target_staff_id = existing["staff_id"]
        target_user_id = existing["user_id"]

        staff_updates = {}
        user_updates = {}

        if data.first_name is not None:
            first_name = data.first_name.strip()
            if not first_name:
                raise ValueError("First name cannot be empty")
            staff_updates["first_name"] = first_name

        if data.last_name is not None:
            last_name = data.last_name.strip()
            if not last_name:
                raise ValueError("Last name cannot be empty")
            staff_updates["last_name"] = last_name

        if data.dept_id is not None:
            if not check_department_exists(conn, data.dept_id):
                raise ValueError(f"Department with ID {data.dept_id} does not exist")
            staff_updates["dept_id"] = data.dept_id

        if data.specialty is not None:
            staff_updates["specialty"] = data.specialty.strip()

        if data.email is not None:
            email_str = str(data.email).strip().lower()
            if check_email_exists_excluding_user(conn, email_str, target_user_id):
                raise ValueError(f"Email '{email_str}' is already in use by another user")
            user_updates["email"] = email_str

        if data.username is not None:
            username_str = data.username.strip().lower()
            if not username_str:
                raise ValueError("Username cannot be empty")
            if check_username_exists_excluding_user(conn, username_str, target_user_id):
                raise ValueError(f"Username '{username_str}' is already taken")
            user_updates["username"] = username_str

        if data.role is not None:
            role_clean = data.role.strip().lower()
            valid_roles = {"doctor", "nurse", "receptionist", "pharmacist", "admin", "patient"}
            if role_clean not in valid_roles:
                raise ValueError(f"Invalid role '{data.role}'. Must be one of {sorted(list(valid_roles))}")
            user_updates["role"] = role_clean

        if data.is_active is not None:
            user_updates["is_active"] = data.is_active

        if staff_updates or user_updates:
            update_staff_user(conn, target_staff_id, target_user_id, staff_updates, user_updates)

        updated = get_staff_by_id(conn, target_staff_id)
        return StaffUserResponse(**updated)


def delete_staff_member(staff_id: int, soft: bool = False) -> dict:
    with get_db() as conn:
        existing = get_staff_by_id(conn, staff_id)
        if not existing:
            raise ValueError(f"Staff member with ID {staff_id} not found")

        target_staff_id = existing["staff_id"]
        target_user_id = existing["user_id"]

        if soft:
            update_is_active(conn, target_user_id, False)
            return {
                "message": "Staff member deactivated successfully",
                "staff_id": target_staff_id,
                "user_id": target_user_id,
                "is_active": False,
            }

        dependencies = check_staff_dependencies(conn, target_staff_id, target_user_id)
        if dependencies:
            dep_msg = ", ".join(dependencies)
            raise ValueError(
                f"Cannot delete staff member: They have associated {dep_msg}. "
                "Deactivate their account instead (or set ?soft=true)."
            )

        delete_staff_user(conn, target_staff_id, target_user_id)
        return {
            "message": "Staff member deleted successfully",
            "staff_id": target_staff_id,
            "user_id": target_user_id,
            "is_active": None,
        }