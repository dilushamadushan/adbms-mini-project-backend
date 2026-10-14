import logging
from typing import List
from fastapi import APIRouter, HTTPException
from app.schema.Docter.docter_schema import DoctorAppointmentResponse
from app.services.Docter import docter_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/doctor", tags=["Doctor"])


@router.get("/appointments/{doctor_id}", response_model=List[DoctorAppointmentResponse])
def get_appointments_by_doctor(doctor_id: int):
    try:
        return docter_service.list_appointments_by_doctor(doctor_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to load doctor appointments: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/appointment-count/{doctor_id}" , response_model=int)
def get_appointment_count(doctor_id: int):
    try:
        return docter_service.get_appointment_count(doctor_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to load doctor appointments: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/appointment-history/{doctor_id}", response_model=List[DoctorAppointmentResponse])
def get_appointment_history_by_doctor(doctor_id: int):
    try:
        return docter_service.get_appointment_history_by_doctor(doctor_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to load doctor appointment history: %s", e)
        raise HTTPException(status_code=500, detail=str(e))