from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import date

class StaffUserCreate(BaseModel):
    first_name: str
    last_name: str
    email: EmailStr
    dept_id: Optional[int] = None
    specialty: Optional[str] = None
    role: str

class StaffUserResponse(BaseModel):
    user_id: int
    staff_id: int
    username: str
    email: Optional[str] = None
    role: str
    first_name: str
    last_name: str
    dept_id: Optional[int] = None
    specialty: Optional[str] = None
    raw_password: Optional[str] = None
    is_active: Optional[bool] = None

class PatientUserCreate(BaseModel):
    first_name: str
    last_name: str
    email: EmailStr
    dob: Optional[date] = None
    blood_group: Optional[str] = None
    emergency_contact: Optional[str] = None
    allergies: Optional[str] = None

class PatientUserResponse(BaseModel):
    user_id: int
    patient_id: int
    username: str
    email: Optional[str] = None
    role: str
    first_name: str
    last_name: str
    raw_password: Optional[str] = None


class PatientProfileResponse(BaseModel):
    patient_id: int
    user_id: int
    username: str
    email: Optional[str] = None
    first_name: str
    last_name: str
    dob: Optional[date] = None
    blood_group: Optional[str] = None
    emergency_contact: Optional[str] = None
    allergies: Optional[str] = None


class UserStatusUpdate(BaseModel):
    is_active: bool


class StaffUserUpdate(BaseModel):
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    email: Optional[EmailStr] = None
    dept_id: Optional[int] = None
    specialty: Optional[str] = None
    role: Optional[str] = None
    is_active: Optional[bool] = None
    username: Optional[str] = None


class StaffDeleteResponse(BaseModel):
    message: str
    staff_id: int
    user_id: int
    is_active: Optional[bool] = None
