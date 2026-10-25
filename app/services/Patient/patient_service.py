from datetime import datetime
from typing import List, Optional
from app.core.database import get_db
from app.repositories.Patient import patient_repo

def _to_24h_time(time_str: str) -> str:
    time_str = str(time_str).strip()
    if not time_str:
        return time_str
    upper_time = time_str.upper()
    if "AM" in upper_time or "PM" in upper_time:
        for fmt in ("%I:%M %p", "%I:%M:%S %p", "%I:%M%p", "%I:%M:%S%p"):
            try:
                return datetime.strptime(upper_time, fmt).strftime("%H:%M:%S")
            except ValueError:
                pass
    for fmt in ("%H:%M:%S", "%H:%M"):
        try:
            return datetime.strptime(time_str, fmt).strftime("%H:%M:%S")
        except ValueError:
            pass
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


def update_patient_profile(user_id: int, data) -> dict:
    from app.repositories.user_repo import check_email_exists_excluding_user, get_patient_profile_by_user_id
    from datetime import date

    with get_db() as conn:
        existing = get_patient_profile_by_user_id(conn, user_id)
        if not existing:
            raise ValueError(f"Patient profile for user ID {user_id} not found")

        patient_updates = {}
        user_updates = {}

        if data.first_name is not None:
            first_name = data.first_name.strip()
            if not first_name:
                raise ValueError("First name cannot be empty")
            patient_updates["first_name"] = first_name

        if data.last_name is not None:
            last_name = data.last_name.strip()
            if not last_name:
                raise ValueError("Last name cannot be empty")
            patient_updates["last_name"] = last_name

        if data.dob is not None:
            if data.dob > date.today():
                raise ValueError("Date of birth cannot be in the future")
            patient_updates["dob"] = data.dob

        if data.emergency_contact is not None:
            patient_updates["emergency_contact"] = data.emergency_contact.strip()

        if data.email is not None:
            email_clean = str(data.email).strip().lower()
            if not email_clean:
                raise ValueError("Email cannot be empty")
            if check_email_exists_excluding_user(conn, email_clean, user_id):
                raise ValueError(f"Email '{email_clean}' is already in use by another account")
            user_updates["email"] = email_clean

        if patient_updates or user_updates:
            patient_repo.update_patient_profile(conn, user_id, patient_updates, user_updates)

        updated_profile = get_patient_profile_by_user_id(conn, user_id)
        return updated_profile


def get_patient_prescriptions(
    patient_id: int,
    status_filter: Optional[str] = None,
) -> List[dict]:
    with get_db() as conn:
        return patient_repo.get_patient_prescriptions(conn, patient_id, status_filter)


def get_patient_medical_records(patient_id: int) -> List[dict]:
    with get_db() as conn:
        return patient_repo.get_patient_medical_records(conn, patient_id)






