import logging
from typing import List, Optional
from fastapi import APIRouter, HTTPException, Query, Depends, status
import mysql.connector
from app.core.security import security_bearer, decode_token
from app.schema.Patient.patient_schema import (
    DoctorDepartmentResponse,
    BookAppointmentRequest,
    BookAppointmentResponse,
)
from app.services.Patient import patient_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/patient", tags=["Patient"])


@router.get("/doctor-departments", response_model=List[DoctorDepartmentResponse])
def get_doctor_departments():
    try:
        return patient_service.get_doctor_departments()
    except Exception as e:
        logger.exception("Failed to get doctor departments: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/available-slots", response_model=List[str])
def get_available_slots(
    doctor_name: str = Query(..., description="Doctor name (e.g., 'John Smith' or 'Dr. John Smith')"),
    department_name: str = Query(..., description="Department name (e.g., 'Cardiology')"),
    apt_date: str = Query(..., description="Appointment date in YYYY-MM-DD format")
):
    try:
        return patient_service.get_available_slots(
            doctor_name=doctor_name,
            department_name=department_name,
            apt_date=apt_date
        )
    except mysql.connector.Error as err:
        logger.warning("Database validation error for available slots: %s", err)
        error_msg = err.msg if hasattr(err, "msg") and err.msg else str(err)
        raise HTTPException(status_code=400, detail=error_msg)
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to get available slots: %s", e)
        error_msg = getattr(e, "msg", str(e))
        is_val_err = any(k in error_msg for k in ("Appointment", "Doctor", "Department", "Patient"))
        raise HTTPException(status_code=400 if is_val_err else 500, detail=error_msg)


@router.post("/book-appointment", response_model=BookAppointmentResponse, status_code=status.HTTP_201_CREATED)
def book_appointment(
    request: BookAppointmentRequest,
    credentials = Depends(security_bearer)
):
    user_id = 1
    if credentials:
        try:
            payload = decode_token(credentials.credentials)
            user_id = int(payload.get("sub", 1))
        except Exception:
            pass
    if request.patient_id:
        user_id = request.patient_id

    try:
        result = patient_service.book_appointment(
            user_id=user_id,
            doctor_id=request.doctor_id,
            dept_id=request.dept_id,
            apt_date=request.apt_date,
            time_slot=request.time_slot,
            patient_id=request.patient_id
        )
        if not result:
            raise HTTPException(status_code=400, detail="Failed to create appointment.")
        return result
    except mysql.connector.Error as err:
        logger.warning("Database error booking appointment: %s", err)
        error_msg = err.msg if hasattr(err, "msg") and err.msg else str(err)
        raise HTTPException(status_code=400, detail=error_msg)
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to book appointment: %s", e)
        error_msg = getattr(e, "msg", str(e))
        is_val_err = any(k in error_msg for k in ("Appointment", "Doctor", "Department", "Patient"))
        raise HTTPException(status_code=400 if is_val_err else 500, detail=error_msg)


