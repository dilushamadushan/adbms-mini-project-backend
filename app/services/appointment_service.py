from datetime import date, datetime, time, timedelta

from fastapi import HTTPException

from app.core.database import get_db
from app.repositories import appointment_repo


def list_appointments(
    user_id: int,
    role: str,
    patient_user_id: int | None = None,
    doctor_id: int | None = None,
    apt_date: date | None = None,
) -> list[dict]:
    if role not in {"patient", "doctor", "admin", "receptionist"}:
        raise HTTPException(status_code=403, detail="You are not allowed to view appointments")
    with get_db() as conn:
        if role == "patient":
            patient_user_id = user_id
            if not appointment_repo.get_patient_by_user_id(conn, user_id):
                raise HTTPException(status_code=404, detail="Patient profile not found")
        elif role == "doctor":
            doctor_id = appointment_repo.get_staff_id_by_user_id(conn, user_id)
            if doctor_id is None:
                raise HTTPException(status_code=404, detail="Doctor profile not found")

        return appointment_repo.list_appointments(
            conn, patient_user_id=patient_user_id, doctor_id=doctor_id, apt_date=apt_date
        )


def list_booked_slots(
    user_id: int,
    role: str,
    doctor_id: int,
    apt_date: date,
    exclude_apt_id: int | None = None,
) -> list[str]:
    if role != "patient":
        raise HTTPException(status_code=403, detail="Only patients can check appointment availability")
    with get_db() as conn:
        if not appointment_repo.get_patient_by_user_id(conn, user_id):
            raise HTTPException(status_code=404, detail="Patient profile not found")
        if not appointment_repo.get_active_doctor(conn, doctor_id):
            raise HTTPException(status_code=404, detail="Doctor not found")
        if exclude_apt_id is not None:
            appointments = appointment_repo.list_appointments(conn, apt_id=exclude_apt_id)
            if (
                not appointments
                or appointments[0]["patient_user_id"] != user_id
                or appointments[0]["doctor_id"] != doctor_id
            ):
                raise HTTPException(status_code=404, detail="Appointment not found")
        return appointment_repo.list_booked_slots(conn, doctor_id, apt_date)


def reschedule_appointment(
    apt_id: int, user_id: int, role: str, apt_date: date, time_slot: time
) -> dict:
    if role != "patient":
        raise HTTPException(status_code=403, detail="Only patients can reschedule appointments")
    _validate_schedule(apt_date, time_slot)

    with get_db() as conn:
        appointments = appointment_repo.list_appointments(conn, apt_id=apt_id)
        if not appointments or appointments[0]["patient_user_id"] != user_id:
            raise HTTPException(status_code=404, detail="Appointment not found")
        appointment = appointments[0]
        if appointment["status"] != "Scheduled":
            raise HTTPException(status_code=400, detail="Only scheduled appointments can be rescheduled")
        if not appointment_repo.is_time_slot_available(
            conn, appointment["doctor_id"], apt_date, time_slot, exclude_apt_id=apt_id
        ):
            raise HTTPException(status_code=409, detail="This appointment time has already been booked")
        appointment_repo.update_appointment_schedule(conn, apt_id, apt_date, time_slot)
        return appointment_repo.list_appointments(conn, apt_id=apt_id)[0]


def _validate_schedule(apt_date: date, time_slot: time) -> None:
    if datetime.combine(apt_date, time_slot) <= datetime.now():
        raise HTTPException(status_code=400, detail="Appointment date and time must be in the future")
    if apt_date.weekday() >= 5:
        raise HTTPException(status_code=400, detail="Appointments are only available on weekdays")
    if (
        time_slot.hour < 9
        or time_slot.hour >= 17
        or time_slot.minute % 15 != 0
        or time_slot.second != 0
    ):
        raise HTTPException(status_code=400, detail="Choose a valid clinic time slot")


def get_appointment(
    apt_id: int, user_id: int, role: str
) -> dict:
    if role not in {"patient", "doctor", "admin", "receptionist"}:
        raise HTTPException(status_code=403, detail="You are not allowed to view appointments")
    with get_db() as conn:
        appointments = appointment_repo.list_appointments(conn, apt_id=apt_id)
        if not appointments:
            raise HTTPException(status_code=404, detail="Appointment not found")
        appointment = appointments[0]
        if role == "patient" and appointment["patient_user_id"] != user_id:
            raise HTTPException(status_code=404, detail="Appointment not found")
        if role == "doctor":
            staff_id = appointment_repo.get_staff_id_by_user_id(conn, user_id)
            if appointment["doctor_id"] != staff_id:
                raise HTTPException(status_code=404, detail="Appointment not found")
        return appointment


def create_appointment(
    user_id: int,
    role: str,
    doctor_id: int,
    dept_id: int,
    apt_date: date,
    time_slot: time,
) -> dict:
    if role != "patient":
        raise HTTPException(status_code=403, detail="Only patients can book appointments")
    _validate_schedule(apt_date, time_slot)

    with get_db() as conn:
        patient = appointment_repo.get_patient_by_user_id(conn, user_id)
        if not patient:
            raise HTTPException(status_code=404, detail="Patient profile not found")
        doctor = appointment_repo.get_doctor_for_department(conn, doctor_id, dept_id)
        if not doctor:
            raise HTTPException(
                status_code=400, detail="The selected doctor is not active in this department"
            )
        if not appointment_repo.is_time_slot_available(conn, doctor_id, apt_date, time_slot):
            raise HTTPException(status_code=409, detail="This appointment time has already been booked")

        apt_id = appointment_repo.create_appointment(
            conn, patient["patient_id"], doctor_id, dept_id, apt_date, time_slot
        )
        return appointment_repo.list_appointments(conn, apt_id=apt_id)[0]


def cancel_appointment(apt_id: int, user_id: int, role: str) -> None:
    appointment = get_appointment(apt_id, user_id, role)
    if role not in {"patient", "admin", "receptionist"}:
        raise HTTPException(status_code=403, detail="You are not allowed to cancel this appointment")
    if role == "patient" and appointment["status"] != "Scheduled":
        raise HTTPException(status_code=400, detail="Only scheduled appointments can be cancelled")
    if role == "patient":
        appointment_time = datetime.combine(
            appointment["apt_date"], time.fromisoformat(appointment["time_slot"])
        )
        if appointment_time - datetime.now() <= timedelta(hours=1):
            raise HTTPException(
                status_code=400, detail="Appointments can only be cancelled at least one hour in advance"
            )

    with get_db() as conn:
        if appointment_repo.update_appointment_status(conn, apt_id, "Cancelled") == 0:
            raise HTTPException(status_code=404, detail="Appointment not found")


def update_appointment_status(
    apt_id: int, user_id: int, role: str, requested_status: str
) -> dict:
    status_value = requested_status.strip().lower()
    status_map = {
        "pending": "Scheduled",
        "confirmed": "Scheduled",
        "scheduled": "Scheduled",
        "completed": "Completed",
        "cancelled": "Cancelled",
        "no-show": "No-Show",
    }
    db_status = status_map.get(status_value)
    if db_status is None:
        raise HTTPException(status_code=400, detail="Invalid appointment status")

    appointment = get_appointment(apt_id, user_id, role)
    if role == "patient" and db_status != "Cancelled":
        raise HTTPException(status_code=403, detail="Patients may only cancel appointments")
    if role == "doctor" and db_status not in {"Completed", "No-Show"}:
        raise HTTPException(status_code=403, detail="Doctors may only complete appointments")
    if role not in {"patient", "doctor", "admin", "receptionist"}:
        raise HTTPException(status_code=403, detail="You are not allowed to update this appointment")

    with get_db() as conn:
        appointment_repo.update_appointment_status(conn, apt_id, db_status)
        return appointment_repo.list_appointments(conn, apt_id=apt_id)[0]
