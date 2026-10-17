from datetime import datetime
from typing import List, Optional
from app.core.database import get_db
from app.repositories.Patient import patient_repo

def _to_24h_time(time_str: str) -> str:
    time_str = str(time_str).strip()
    if "AM" in time_str.upper() or "PM" in time_str.upper():
        try:
            return datetime.strptime(time_str, "%I:%M %p").strftime("%H:%M:00")
        except ValueError:
            pass
    if len(time_str) == 5:
        return f"{time_str}:00"
    return time_str

def get_doctor_departments():
    with get_db() as conn:
        return patient_repo.get_doctor_departments_view(conn)

def get_available_slots(doctor_name: str, department_name: str, apt_date: str) -> List[str]:
    with get_db() as conn:
        return patient_repo.get_available_slots_proc(conn, doctor_name, department_name, apt_date)

def book_appointment(
    user_id: int,
    doctor_id: int,
    dept_id: int,
    apt_date: str,
    time_slot: str,
    patient_id: Optional[int] = None
) -> dict:
    with get_db() as conn:
        resolved_patient_id = patient_id
        if resolved_patient_id is None:
            resolved_patient_id = patient_repo.get_patient_id_by_user_id(conn, user_id)
        if not resolved_patient_id:
            resolved_patient_id = user_id

        normalized_time = _to_24h_time(time_slot)
        return patient_repo.book_appointment_proc(
            conn,
            patient_id=resolved_patient_id,
            doctor_id=doctor_id,
            dept_id=dept_id,
            apt_date=apt_date,
            time_slot=normalized_time
        )


