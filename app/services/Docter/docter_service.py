from logging import error
from app.core.database import get_db
from app.repositories.Docter import docter_repo

def list_appointments_by_doctor(doctor_id: int):
    with get_db() as conn:
        if not docter_repo.doctor_exists(conn, doctor_id):
            raise ValueError("Doctor not found")
        return docter_repo.get_appointments_by_doctor(conn, doctor_id)

def get_appointment_count(doctor_id: int):
    with get_db() as conn:
        if not docter_repo.doctor_exists(conn, doctor_id):
            raise ValueError("Doctor not found")
        return docter_repo.get_appointment_count(conn, doctor_id)

def get_appointment_history_by_doctor(doctor_id: int):
    with get_db() as conn:
        if not docter_repo.doctor_exists(conn, doctor_id):
            raise ValueError("Doctor not found")
        return docter_repo.get_appointment_history_by_doctor(conn, doctor_id)

def get_upcoming_appointments_by_doctor(doctor_id: int):
    with get_db() as conn:
        if not docter_repo.doctor_exists(conn, doctor_id):
            raise ValueError("error: ",error)
        return docter_repo.get_upcoming_appointments_by_doctor(conn, doctor_id)

