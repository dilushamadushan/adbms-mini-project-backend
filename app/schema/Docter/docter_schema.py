from datetime import date
from typing import Any, Optional, Union
from pydantic import BaseModel, field_validator

class DoctorAppointmentResponse(BaseModel):
    apt_id: int
    patient_id: int
    patient_name: str
    dob: Optional[date] = None
    blood_group: Optional[str] = None
    allergies: Optional[str] = None
    dept_id: int
    dept_name: str
    apt_date: date
    time_slot: str
    status: str

    @field_validator('time_slot', mode='before')
    @classmethod
    def serialize_time_slot(cls, v: Any) -> str:
        if v is None:
            return ""
        return str(v)


class DoctorUpcomingAppointmentResponse(BaseModel):
    apt_id: int
    patient_id: int
    patient_name: str
    age: Optional[Union[int, str]] = None
    apt_date: Union[date, str]
    time_slot: str
    status: str
    reason: Optional[str] = None

    @field_validator('time_slot', mode='before')
    @classmethod
    def serialize_time_slot(cls, v: Any) -> str:
        if v is None:
            return ""
        return str(v)

    @field_validator('patient_name', mode='before')
    @classmethod
    def serialize_patient_name(cls, v: Any) -> str:
        if isinstance(v, (bytes, bytearray)):
            return v.decode('utf-8', errors='replace')
        return str(v)

    @field_validator('reason', mode='before')
    @classmethod
    def serialize_reason(cls, v: Any) -> Optional[str]:
        if v is None:
            return None
        if isinstance(v, (bytes, bytearray)):
            return v.decode('utf-8', errors='replace')
        return str(v)

