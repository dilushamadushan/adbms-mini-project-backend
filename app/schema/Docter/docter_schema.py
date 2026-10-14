from datetime import date
from typing import Optional
from pydantic import BaseModel

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