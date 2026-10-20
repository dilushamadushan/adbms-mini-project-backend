from datetime import date, datetime, time
from decimal import Decimal
import re
from typing import Any

import mysql.connector
from fastapi import BackgroundTasks, HTTPException

from app.core.database import get_db
from app.core.email import send_patient_welcome_email
from app.repositories import recep_repo


def get_overview(user_id: int, role: str) -> dict[str, Any]:
    _require_receptionist(role)
    with get_db() as conn:
        return recep_repo.get_overview(conn, date.today())


def get_wards(user_id: int, role: str) -> list[dict[str, Any]]:
    if role not in {"receptionist", "admin", "nurse"}:
        raise HTTPException(status_code=403, detail="Ward access required")
    with get_db() as conn:
        return recep_repo.list_wards(conn)


def get_available_beds(
    user_id: int, role: str, ward_id: int | None = None
) -> list[dict[str, Any]]:
    if role not in {"receptionist", "admin", "nurse"}:
        raise HTTPException(status_code=403, detail="Bed access required")
    with get_db() as conn:
        return recep_repo.list_available_beds(conn, ward_id)


def admit_patient(
    user_id: int,
    role: str,
    patient_id: int,
    ward_id: int,
    admitted_doctor_id: int,
    reason: str,
    guardian_name: str,
    guardian_relationship: str,
    guardian_contact: str,
    gender: str,
) -> dict[str, Any]:
    _require_receptionist(role)
    if not reason.strip():
        raise HTTPException(status_code=400, detail="Admission reason is required")
    if not guardian_name.strip():
        raise HTTPException(status_code=400, detail="Guardian name is required")
    if not guardian_relationship.strip():
        raise HTTPException(status_code=400, detail="Guardian relationship is required")
    if not re.fullmatch(r"\+?[0-9\s().-]{7,20}", guardian_contact.strip()):
        raise HTTPException(status_code=400, detail="Enter a valid guardian contact number")
    if gender not in {"Female", "Male"}:
        raise HTTPException(status_code=400, detail="Select Female or Male")
    with get_db() as conn:
        if not recep_repo.get_patient_id(conn, patient_id):
            raise HTTPException(status_code=404, detail="Patient not found")
        if not any(ward["ward_id"] == ward_id for ward in recep_repo.list_wards(conn)):
            raise HTTPException(status_code=404, detail="Ward not found")
        if not recep_repo.is_active_doctor(conn, admitted_doctor_id):
            raise HTTPException(status_code=404, detail="Active admitting doctor not found")
        admission_id = recep_repo.create_admission(
            conn,
            patient_id,
            ward_id,
            admitted_doctor_id,
            user_id,
            reason.strip(),
            guardian_name.strip(),
            guardian_relationship.strip(),
            guardian_contact.strip(),
            gender,
        )
        return recep_repo.get_admission(conn, admission_id)


def assign_admission_bed(
    user_id: int, role: str, admission_id: int, bed_id: int
) -> dict[str, Any]:
    if role != "nurse":
        raise HTTPException(status_code=403, detail="Only a nurse can assign an admission bed")
    with get_db() as conn:
        if not recep_repo.assign_admission_bed(conn, admission_id, bed_id):
            raise HTTPException(
                status_code=409,
                detail="The admission or bed is no longer available for assignment in the selected ward",
            )
        return recep_repo.get_admission(conn, admission_id)


def list_admissions(user_id: int, role: str, active_only: bool = False) -> list[dict[str, Any]]:
    if role not in {"receptionist", "doctor", "admin", "nurse"}:
        raise HTTPException(status_code=403, detail="Admission access required")
    with get_db() as conn:
        return recep_repo.list_admissions(conn, active_only)


def authorize_discharge(
    user_id: int, role: str, admission_id: int, notes: str
) -> dict[str, Any]:
    if role != "doctor":
        raise HTTPException(status_code=403, detail="Only a doctor can authorize discharge")
    with get_db() as conn:
        doctor_staff_id = recep_repo.get_doctor_staff_id(conn, user_id)
        if doctor_staff_id is None:
            raise HTTPException(status_code=404, detail="Doctor profile not found")
        admission = recep_repo.get_admission(conn, admission_id, lock=True)
        if not admission:
            raise HTTPException(status_code=404, detail="Admission not found")
        if admission["status"] != "Admitted":
            raise HTTPException(status_code=409, detail="Admission is not awaiting discharge authorization")
        if admission["bed_id"] is None:
            raise HTTPException(status_code=409, detail="A nurse must assign a bed before discharge authorization")
        if recep_repo.authorize_discharge(
            conn, admission_id, doctor_staff_id, notes.strip()
        ) == 0:
            raise HTTPException(status_code=409, detail="Discharge authorization could not be recorded")
        return recep_repo.get_admission(conn, admission_id)


def calculate_discharge_bill(
    user_id: int,
    role: str,
    admission_id: int,
    room_charges: Decimal,
    treatment_charges: Decimal,
    other_charges: Decimal,
    amount_paid: Decimal,
    payment_method: str | None,
) -> dict[str, Any]:
    _require_receptionist(role)
    if amount_paid > 0 and not payment_method:
        raise HTTPException(status_code=400, detail="Payment method is required when recording a payment")
    if amount_paid > room_charges + treatment_charges + other_charges:
        raise HTTPException(status_code=400, detail="Payment exceeds the calculated bill total")
    with get_db() as conn:
        admission = recep_repo.get_admission(conn, admission_id, lock=True)
        if not admission:
            raise HTTPException(status_code=404, detail="Admission not found")
        if admission["status"] != "Discharge Authorized":
            raise HTTPException(
                status_code=409, detail="Doctor discharge authorization is required before billing"
            )
        try:
            fully_paid = recep_repo.save_discharge_bill(
                conn,
                admission_id,
                room_charges,
                treatment_charges,
                other_charges,
                amount_paid,
                payment_method,
            )
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

        if fully_paid:
            recep_repo.complete_discharge(conn, admission_id, user_id)
        return recep_repo.get_admission(conn, admission_id)


def pay_discharge_balance(
    user_id: int,
    role: str,
    admission_id: int,
    amount: Decimal,
    payment_method: str,
) -> dict[str, Any]:
    _require_receptionist(role)
    with get_db() as conn:
        admission = recep_repo.get_admission(conn, admission_id, lock=True)
        if not admission:
            raise HTTPException(status_code=404, detail="Admission not found")
        if admission["status"] != "Discharge Authorized":
            raise HTTPException(status_code=409, detail="This admission is not awaiting payment")
        try:
            fully_paid = recep_repo.add_bill_payment(
                conn, admission_id, amount, payment_method
            )
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        if fully_paid:
            recep_repo.complete_discharge(conn, admission_id, user_id)
        return recep_repo.get_admission(conn, admission_id)


def _require_receptionist(role: str) -> None:
    if role not in {"receptionist", "admin"}:
        raise HTTPException(status_code=403, detail="Receptionist access required")


def register_patient(data: dict[str, Any], background_tasks: BackgroundTasks) -> dict[str, Any]:
    if data["dob"] > date.today():
        raise HTTPException(status_code=400, detail="Date of birth cannot be in the future")
    data["first_name"] = data["first_name"].strip()
    data["last_name"] = data["last_name"].strip()
    data["email"] = str(data["email"]).strip()
    data["emergency_contact"] = data["emergency_contact"].strip()
    data["allergies"] = (data.get("allergies") or "").strip() or "Unknown"
    try:
        with get_db() as conn:
            patient = recep_repo.create_patient(conn, data)
    except mysql.connector.IntegrityError as exc:
        raise HTTPException(status_code=409, detail="Email or username already exists") from exc
    background_tasks.add_task(
        send_patient_welcome_email, patient["email"], patient["first_name"],
        patient["last_name"], patient["username"], patient["raw_password"],
    )
    return patient


def search_patients(role: str, search: str | None) -> list[dict[str, Any]]:
    _require_receptionist(role)
    with get_db() as conn:
        return recep_repo.get_patient_records(conn, search)


def _validate_appointment(apt_date: date, time_slot: time) -> None:
    if datetime.combine(apt_date, time_slot) <= datetime.now():
        raise HTTPException(status_code=400, detail="Appointment must be in the future")
    if apt_date.weekday() > 4:
        raise HTTPException(status_code=400, detail="Appointments are only available on weekdays")
    if time_slot.hour < 9 or time_slot.hour >= 17 or time_slot.minute % 15 or time_slot.second:
        raise HTTPException(status_code=400, detail="Choose a valid clinic time slot")


def create_appointment(
    user_id: int, role: str, patient_id: int, doctor_id: int, dept_id: int,
    apt_date: date, time_slot: time,
) -> dict[str, Any]:
    _require_receptionist(role)
    _validate_appointment(apt_date, time_slot)
    with get_db() as conn:
        if not recep_repo.get_patient_id(conn, patient_id):
            raise HTTPException(status_code=404, detail="Patient not found")
        if not recep_repo.is_doctor_in_department(conn, doctor_id, dept_id):
            raise HTTPException(status_code=400, detail="Doctor is not active in the selected department")
        if not recep_repo.is_slot_available(conn, doctor_id, apt_date, time_slot):
            raise HTTPException(status_code=409, detail="This appointment time is already booked")
        appointment_id = recep_repo.create_appointment(
            conn, patient_id, doctor_id, dept_id, apt_date, time_slot
        )
        return recep_repo.list_appointments(conn, appointment_id=appointment_id)[0]


def update_appointment(
    user_id: int, role: str, appointment_id: int, apt_date: date, time_slot: time,
) -> dict[str, Any]:
    _require_receptionist(role)
    _validate_appointment(apt_date, time_slot)
    with get_db() as conn:
        appointment = recep_repo.list_appointments(conn, appointment_id=appointment_id)
        if not appointment:
            raise HTTPException(status_code=404, detail="Appointment not found")
        if appointment[0]["status"] != "Scheduled":
            raise HTTPException(status_code=409, detail="Only scheduled appointments can be rescheduled")
        if not recep_repo.is_slot_available(
            conn, appointment[0]["doctor_id"], apt_date, time_slot, appointment_id
        ):
            raise HTTPException(status_code=409, detail="This appointment time is already booked")
        recep_repo.update_appointment_schedule(conn, appointment_id, apt_date, time_slot)
        return recep_repo.list_appointments(conn, appointment_id=appointment_id)[0]


def change_appointment_status(
    user_id: int, role: str, appointment_id: int, requested_status: str,
) -> dict[str, Any]:
    _require_receptionist(role)
    status_map = {"scheduled": "Scheduled", "cancelled": "Cancelled"}
    new_status = status_map.get(requested_status.strip().lower())
    if not new_status:
        raise HTTPException(status_code=400, detail="Receptionists can only schedule or cancel appointments")
    with get_db() as conn:
        appointments = recep_repo.list_appointments(conn, appointment_id=appointment_id)
        if not appointments:
            raise HTTPException(status_code=404, detail="Appointment not found")
        current_status = appointments[0]["status"]
        if new_status == "Cancelled" and current_status != "Scheduled":
            raise HTTPException(status_code=409, detail="Only scheduled appointments can be cancelled")
        if new_status == "Scheduled" and current_status != "Cancelled":
            raise HTTPException(status_code=409, detail="Only cancelled appointments can be restored to scheduled")
        recep_repo.update_appointment_status(conn, appointment_id, new_status)
        return recep_repo.list_appointments(conn, appointment_id=appointment_id)[0]


def get_appointments(
    user_id: int,
    role: str,
    patient_id: int | None,
    appointment_date: date | None,
    patient_name: str | None = None,
) -> list[dict[str, Any]]:
    _require_receptionist(role)
    with get_db() as conn:
        return recep_repo.list_appointments(
            conn,
            patient_id=patient_id,
            appointment_date=appointment_date,
            patient_name=patient_name,
        )
