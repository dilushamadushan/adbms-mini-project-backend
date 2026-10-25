import logging
from typing import List
from fastapi import APIRouter, HTTPException
from app.schema.Docter.docter_schema import (
    DoctorAppointmentResponse,
    DoctorUpcomingAppointmentResponse,
    DoctorAppointmentGroupedResponse,
    PatientDetailsResponse,
    PatientAppointmentDetailsResponse,
    AdmissionStatusResponse,
    CreateAdmissionRequest,
    AdmissionRequestResponse,
    DischargeRequest,
    DischargeRequestResponse,
    CompleteAppointmentRequest,
    CompleteAppointmentResponse,
    DoctorMedicineResponse,
    CreatePrescriptionRequest,
    CreatePrescriptionResponse,
    CreateAdmittedPrescriptionRequest,
    LabOrderPatientDetailsResponse,
    CreateLabOrderRequest,
    CreateLabOrderResponse,
    PatientLabResultResponse,
    DoctorCurrentScheduleResponse,
)
from app.services.Docter import docter_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/doctor", tags=["Doctor"])

@router.get("/medicines", response_model=List[DoctorMedicineResponse])
def get_doctor_medicines():
    """Return the medicine list used by the doctor prescription workflow."""
    return docter_service.get_doctor_medicine_list()


@router.get(
    "/lab-order-patients",
    response_model=List[LabOrderPatientDetailsResponse],
)
def get_lab_order_patients():
    """Return patient and appointment details exposed by the lab-order view."""
    try:
        return docter_service.get_lab_order_patient_details()
    except Exception as e:
        logger.exception("Failed to load lab-order patients: %s", e)
        raise HTTPException(status_code=500, detail="Failed to load lab-order patients")


@router.post("/lab-orders", response_model=CreateLabOrderResponse, status_code=201)
def create_lab_order(payload: CreateLabOrderRequest):
    try:
        return docter_service.create_lab_order(
            payload.patient_id,
            payload.doctor_user_id,
            payload.test_type,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception:
        logger.exception("Failed to save lab order")
        raise HTTPException(status_code=500, detail="Failed to save lab order")


@router.get(
    "/lab-orders/patient/{patient_id}",
    response_model=List[PatientLabResultResponse],
)
def get_patient_lab_results(patient_id: int):
    try:
        return docter_service.get_patient_lab_results(patient_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception:
        logger.exception("Failed to load patient lab results")
        raise HTTPException(status_code=500, detail="Failed to load patient lab results")


@router.post("/prescriptions", response_model=CreatePrescriptionResponse)
def create_prescription(payload: CreatePrescriptionRequest):
    try:
        return docter_service.create_prescription(
            payload.patient_id,
            payload.apt_id,
            payload.doctor_id,
            payload.diagnosis,
            payload.clinical_notes,
            [medicine.model_dump() for medicine in payload.medicines],
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception("Failed to save prescription: %s", e)
        raise HTTPException(status_code=500, detail="Failed to save prescription")


@router.post("/admitted-prescriptions", response_model=CreatePrescriptionResponse)
def create_admitted_prescription(payload: CreateAdmittedPrescriptionRequest):
    try:
        return docter_service.create_admitted_prescription(
            payload.patient_id,
            payload.apt_id,
            payload.doctor_id,
            payload.diagnosis,
            payload.clinical_notes,
            [medicine.model_dump() for medicine in payload.medicines],
            [order.model_dump() for order in payload.nurse_orders],
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception:
        logger.exception("Failed to save admitted prescription")
        raise HTTPException(status_code=500, detail="Failed to save admitted prescription")


@router.post("/appointments/complete", response_model=CompleteAppointmentResponse)
def complete_appointment(payload: CompleteAppointmentRequest):
    try:
        return docter_service.complete_appointment(
            payload.appointment_id,
            payload.doctor_id,
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to complete appointment: %s", e)
        raise HTTPException(status_code=500, detail="Failed to complete appointment")




@router.get("/appointments/{doctor_id}", response_model=List[DoctorAppointmentResponse])
def get_appointments_by_doctor(doctor_id: int):
    try:
        return docter_service.list_appointments_by_doctor(doctor_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to load doctor appointments: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get(
    "/current-schedule/{doctor_id}",
    response_model=List[DoctorCurrentScheduleResponse],
)
def get_doctor_current_schedule(doctor_id: int):
    try:
        return docter_service.get_doctor_current_schedule(doctor_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to load current doctor schedule: %s", e)
        raise HTTPException(status_code=500, detail="Failed to load current doctor schedule")


@router.get(
    "/current-schedule-by-user/{user_id}",
    response_model=List[DoctorCurrentScheduleResponse],
)
def get_doctor_current_schedule_by_user(user_id: int):
    try:
        return docter_service.get_doctor_current_schedule_by_user(user_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception:
        logger.exception("Failed to load current doctor schedule by user")
        raise HTTPException(status_code=500, detail="Failed to load current doctor schedule")


@router.get("/appointment-count/{doctor_id}" , response_model=int)
def get_appointment_count(doctor_id: int):
    try:
        return docter_service.get_appointment_count(doctor_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to load doctor appointments: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/appointment-count-completed/{doctor_id}", response_model=int)
def get_completed_appointment_count(doctor_id: int):
    try:
        return docter_service.get_completed_appointment_count(doctor_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to load completed doctor appointment count: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/patients-count/{doctor_id}", response_model=int)
def get_total_patients_count(doctor_id: int):
    try:
        return docter_service.get_total_patients_count(doctor_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to load doctor patients count: %s", e)
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


@router.get("/upcoming-appointments/{doctor_id}", response_model=List[DoctorUpcomingAppointmentResponse])
def get_upcoming_appointments_by_doctor(doctor_id: int):
    try:
        return docter_service.get_upcoming_appointments_by_doctor(doctor_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to load doctor upcoming appointments: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/appointments-by-user/{user_id}", response_model=List[DoctorAppointmentGroupedResponse])
def get_doctor_appointments_by_user(user_id: int):
    try:
        return docter_service.get_doctor_appointments_by_user(user_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to load doctor appointments by user: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/patient-details/{patient_id}", response_model=PatientDetailsResponse)
def get_patient_details(patient_id: int):
    try:
        return docter_service.get_patient_details(patient_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to load patient details: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get(
    "/patient-appointment-details/{appointment_id}",
    response_model=PatientAppointmentDetailsResponse,
)
def get_patient_appointment_details(appointment_id: int):
    try:
        return docter_service.get_patient_appointment_details(appointment_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to load patient appointment details: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/wards")
def get_ward_names():
    try:
        return docter_service.get_ward_names()
    except Exception as e:
        logger.exception("Failed to load ward names: %s", e)
        raise HTTPException(status_code=500, detail="Failed to load ward names")


@router.post("/admissions", response_model=AdmissionRequestResponse)
def create_admission_request(payload: CreateAdmissionRequest):
    try:
        return docter_service.create_admission_request(
            payload.patient_id,
            payload.gender,
            payload.ward_id,
            payload.reason,
            payload.doctor_id,
            payload.user_id,
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to create admission request: %s", e)
        raise HTTPException(status_code=500, detail="Failed to create admission request")


@router.post("/discharge", response_model=DischargeRequestResponse)
def request_discharge(payload: DischargeRequest):
    try:
        return docter_service.request_discharge(
            payload.admission_id,
            payload.doctor_id,
            payload.notes,
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to request discharge: %s", e)
        raise HTTPException(status_code=500, detail="Failed to request discharge")


@router.get("/admission-status/{patient_id}", response_model=AdmissionStatusResponse)
def get_admission_status(patient_id: int):
    try:
        admission = docter_service.get_active_admission_by_patient(patient_id)
        return {"is_admitted": admission is not None, "admission": admission}
    except Exception as e:
        logger.exception("Failed to load admission status: %s", e)
        raise HTTPException(status_code=500, detail="Failed to load admission status")