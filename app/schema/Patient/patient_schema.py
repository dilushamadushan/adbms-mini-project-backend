from typing import Optional, Any
from pydantic import BaseModel, field_validator

class DoctorDepartmentResponse(BaseModel):
    doctor_name: str
    department_name: str

class BookAppointmentRequest(BaseModel):
    doctor_id: int
    dept_id: int
    apt_date: str
    time_slot: str
    patient_id: Optional[int] = None

class BookAppointmentResponse(BaseModel):
    apt_id: int
    patient_id: int
    doctor_id: int
    dept_id: int
    apt_date: str
    time_slot: str
    status: str

    @field_validator("apt_date", mode="before")
    @classmethod
    def serialize_apt_date(cls, value: Any) -> str:
        return str(value) if value is not None else ""

    @field_validator("time_slot", mode="before")
    @classmethod
    def serialize_time_slot(cls, value: Any) -> str:
        return str(value) if value is not None else ""


