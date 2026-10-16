from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status

from app.core.security import get_current_user_payload
from app.schema.appointment_schema import (
    AppointmentCreate,
    AppointmentResponse,
    AppointmentReschedule,
    AppointmentStatusUpdate,
)
from app.services import appointment_service

router = APIRouter(prefix="/appointments", tags=["Appointments"])


def _identity(payload: dict) -> tuple[int, str]:
    try:
        return int(payload["sub"]), str(payload.get("role", "")).lower()
    except (KeyError, TypeError, ValueError) as exc:
        raise HTTPException(status_code=401, detail="Invalid authentication identity") from exc


@router.get("", response_model=list[AppointmentResponse])
def get_appointments(
    date_filter: date | None = Query(default=None, alias="date"),
    doctor_id: int | None = None,
    patient_user_id: int | None = None,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    return appointment_service.list_appointments(
        user_id, role, patient_user_id=patient_user_id, doctor_id=doctor_id, apt_date=date_filter
    )


@router.get("/availability", response_model=list[str])
def get_booked_slots(
    doctor_id: int,
    date_filter: date = Query(alias="date"),
    exclude_apt_id: int | None = None,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    return appointment_service.list_booked_slots(
        user_id, role, doctor_id, date_filter, exclude_apt_id
    )


@router.patch("/{apt_id}/schedule", response_model=AppointmentResponse)
def reschedule_appointment(
    apt_id: int,
    schedule: AppointmentReschedule,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    return appointment_service.reschedule_appointment(
        apt_id, user_id, role, schedule.apt_date, schedule.time_slot
    )


@router.get("/{apt_id}", response_model=AppointmentResponse)
def get_appointment(
    apt_id: int, payload: dict = Depends(get_current_user_payload)
):
    user_id, role = _identity(payload)
    return appointment_service.get_appointment(apt_id, user_id, role)


@router.post("", response_model=AppointmentResponse, status_code=status.HTTP_201_CREATED)
def create_appointment(
    appointment: AppointmentCreate,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    return appointment_service.create_appointment(
        user_id,
        role,
        appointment.doctor_id,
        appointment.dept_id,
        appointment.apt_date,
        appointment.time_slot,
    )


@router.patch("/{apt_id}/status", response_model=AppointmentResponse)
def change_appointment_status(
    apt_id: int,
    update: AppointmentStatusUpdate,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    return appointment_service.update_appointment_status(
        apt_id, user_id, role, update.status
    )


@router.delete("/{apt_id}", status_code=status.HTTP_204_NO_CONTENT)
def cancel_appointment(
    apt_id: int, payload: dict = Depends(get_current_user_payload)
):
    user_id, role = _identity(payload)
    appointment_service.cancel_appointment(apt_id, user_id, role)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
