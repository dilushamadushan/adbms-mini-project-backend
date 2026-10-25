from datetime import date, time
from typing import Optional

from pydantic import BaseModel, field_validator


class AppointmentCreate(BaseModel):
    doctor_id: int
    dept_id: int
    apt_date: date
    time_slot: time


class AppointmentReschedule(BaseModel):
    apt_date: date
    time_slot: time


class AppointmentStatusUpdate(BaseModel):
    status: str


class AppointmentResponse(BaseModel):
    apt_id: int
    patient_id: int
    patient_user_id: int
    patient_name: str
    doctor_id: int
    doctor_name: str
    dept_id: int
    dept_name: str
    apt_date: date
    time_slot: str
    status: str
    reason: Optional[str] = None

    @field_validator("time_slot", mode="before")
    @classmethod
    def serialize_time_slot(cls, value: time) -> str:
        return str(value) if value is not None else ""
