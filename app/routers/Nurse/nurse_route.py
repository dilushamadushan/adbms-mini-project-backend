import logging
from typing import List, Optional
from fastapi import APIRouter, HTTPException, Depends, Query, status
import mysql.connector

from app.core.security import security_bearer, decode_token
from app.schema.Nurse.nurse_schema import (
    WardOverviewResponse,
    DashboardStatsResponse,
    BedDetailResponse,
    VitalsLogCreate,
    VitalsLogResponse,
    BedStatusUpdate,
    DischargeCompleteResponse,
    WardPatientItem,
    MarOverviewResponse,
    MarAdministerRequest,
    MarAdministerResponse,
    DoctorOrderItem,
    DoctorOrderStatusUpdate,
    NursingNoteItem,
    NursingNoteCreate,
    IntakeOutputSummaryResponse,
    IntakeOutputCreate,
    AssignBedRequest,
    UnassignedAdmissionItem,
    NurseStaffItem,
    NurseLabOrderItem,
    LabOrderCompleteRequest,
)
from app.services.Nurse import nurse_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/nurse", tags=["Nurse"])


def _get_current_nurse_id(credentials=Depends(security_bearer)) -> int:
    if credentials:
        try:
            payload = decode_token(credentials.credentials)
            return int(payload.get("sub", 4))
        except Exception:
            pass
    return 4


@router.get("/ward-overview", response_model=WardOverviewResponse)
def get_ward_overview(
    ward_id: Optional[int] = Query(None),
    nurse_user_id: int = Depends(_get_current_nurse_id),
):
    try:
        return nurse_service.get_ward_overview(nurse_user_id, ward_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to get ward overview: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/dashboard/stats", response_model=DashboardStatsResponse)
def get_dashboard_stats(
    ward_id: Optional[int] = Query(None),
    nurse_user_id: int = Depends(_get_current_nurse_id),
):
    try:
        return nurse_service.get_dashboard_stats(nurse_user_id, ward_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to get dashboard stats: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/ward/{ward_id}/unassigned-patients", response_model=List[UnassignedAdmissionItem])
def get_unassigned_patients(
    ward_id: int,
    nurse_user_id: int = Depends(_get_current_nurse_id),
):
    try:
        return nurse_service.get_unassigned_admissions(ward_id)
    except Exception as e:
        logger.exception("Failed to get unassigned admissions: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/bed/{bed_id}/assign-patient")
def assign_patient_to_bed(
    bed_id: int,
    payload: AssignBedRequest,
    nurse_user_id: int = Depends(_get_current_nurse_id),
):
    try:
        return nurse_service.assign_patient_to_bed(payload.admission_id, bed_id, nurse_user_id)
    except mysql.connector.Error as e:
        raise HTTPException(status_code=400, detail=e.msg)
    except Exception as e:
        logger.exception("Failed to assign patient to bed: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/bed/{bed_id}", response_model=BedDetailResponse)
def get_bed_details(bed_id: int):
    try:
        return nurse_service.get_bed_details(bed_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.exception("Failed to get bed details for bed %s: %s", bed_id, e)
        raise HTTPException(status_code=500, detail=str(e))


@router.post(
    "/bed/{bed_id}/vitals",
    response_model=VitalsLogResponse,
    status_code=status.HTTP_201_CREATED,
)
def record_vitals(
    bed_id: int,
    payload: VitalsLogCreate,
    nurse_user_id: int = Depends(_get_current_nurse_id),
):
    try:
        return nurse_service.record_vitals(
            bed_id=bed_id,
            nurse_user_id=nurse_user_id,
            bp=payload.bp,
            pulse=payload.pulse,
            temperature=payload.temperature,
            spo2=payload.spo2,
            resp_rate=payload.resp_rate,
            blood_sugar=payload.blood_sugar,
            weight=payload.weight,
        )
    except mysql.connector.Error as err:
        logger.warning("Database error recording vitals: %s", err)
        error_msg = err.msg if hasattr(err, "msg") and err.msg else str(err)
        raise HTTPException(status_code=400, detail=error_msg)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception("Failed to record vitals: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.patch("/bed/{bed_id}/status")
def update_bed_status(
    bed_id: int,
    payload: BedStatusUpdate,
    nurse_user_id: int = Depends(_get_current_nurse_id),
):
    try:
        return nurse_service.update_bed_status(
            bed_id=bed_id, status=payload.status, nurse_user_id=nurse_user_id
        )
    except mysql.connector.Error as err:
        logger.warning("Database error updating bed status: %s", err)
        error_msg = err.msg if hasattr(err, "msg") and err.msg else str(err)
        raise HTTPException(status_code=400, detail=error_msg)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception("Failed to update bed status: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.post(
    "/discharge/{admission_id}/complete", response_model=DischargeCompleteResponse
)
def complete_discharge(
    admission_id: int, nurse_user_id: int = Depends(_get_current_nurse_id)
):
    try:
        return nurse_service.complete_discharge(admission_id, nurse_user_id)
    except mysql.connector.Error as err:
        logger.warning("Database error completing discharge: %s", err)
        error_msg = err.msg if hasattr(err, "msg") and err.msg else str(err)
        raise HTTPException(status_code=400, detail=error_msg)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception("Failed to complete discharge: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/patients", response_model=List[WardPatientItem])
def list_ward_patients(nurse_user_id: int = Depends(_get_current_nurse_id)):
    try:
        return nurse_service.list_ward_patients(nurse_user_id)
    except Exception as e:
        logger.exception("Failed to list ward patients: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/patient/{patient_id}/mar", response_model=MarOverviewResponse)
def get_patient_mar(patient_id: int):
    try:
        return nurse_service.get_patient_mar(patient_id)
    except Exception as e:
        logger.exception("Failed to get MAR for patient %s: %s", patient_id, e)
        raise HTTPException(status_code=500, detail=str(e))


@router.post(
    "/patient/{patient_id}/mar/administer",
    response_model=MarAdministerResponse,
    status_code=status.HTTP_201_CREATED,
)
def administer_medication(
    patient_id: int,
    payload: MarAdministerRequest,
    nurse_user_id: int = Depends(_get_current_nurse_id),
):
    try:
        return nurse_service.administer_medication(
            rx_id=payload.rx_id,
            patient_id=patient_id,
            nurse_user_id=nurse_user_id,
            status=payload.status,
            reason=payload.reason,
            notes=payload.notes,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception("Failed to administer medication: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/patient/{patient_id}/orders", response_model=List[DoctorOrderItem])
def get_doctor_orders(patient_id: int):
    try:
        return nurse_service.get_doctor_orders(patient_id)
    except Exception as e:
        logger.exception("Failed to get doctor orders: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.patch("/orders/{order_id}/status")
def update_doctor_order_status(
    order_id: int,
    payload: DoctorOrderStatusUpdate,
    nurse_user_id: int = Depends(_get_current_nurse_id),
):
    try:
        return nurse_service.acknowledge_doctor_order(order_id, nurse_user_id, payload.status)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception("Failed to update doctor order status: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/patient/{patient_id}/notes", response_model=List[NursingNoteItem])
def get_nursing_notes(patient_id: int):
    try:
        return nurse_service.get_nursing_notes(patient_id)
    except Exception as e:
        logger.exception("Failed to get nursing notes: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.post(
    "/patient/{patient_id}/notes",
    response_model=NursingNoteItem,
    status_code=status.HTTP_201_CREATED,
)
def add_nursing_note(
    patient_id: int,
    payload: NursingNoteCreate,
    nurse_user_id: int = Depends(_get_current_nurse_id),
):
    try:
        return nurse_service.add_nursing_note(
            patient_id=patient_id,
            nurse_user_id=nurse_user_id,
            note_type=payload.note_type,
            subjective=payload.subjective,
            objective=payload.objective,
            assessment=payload.assessment,
            plan=payload.plan,
            content=payload.content,
        )
    except Exception as e:
        logger.exception("Failed to add nursing note: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/patient/{patient_id}/io", response_model=IntakeOutputSummaryResponse)
def get_patient_io(patient_id: int, date: Optional[str] = Query(None, description="YYYY-MM-DD")):
    try:
        return nurse_service.get_patient_io_summary(patient_id, date)
    except Exception as e:
        logger.exception("Failed to get I/O summary: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/patient/{patient_id}/io", status_code=status.HTTP_201_CREATED)
def log_intake_output(
    patient_id: int,
    payload: IntakeOutputCreate,
    nurse_user_id: int = Depends(_get_current_nurse_id),
):
    try:
        return nurse_service.log_intake_output(
            patient_id=patient_id,
            nurse_user_id=nurse_user_id,
            io_type=payload.io_type,
            category=payload.category,
            volume_ml=payload.volume_ml,
            notes=payload.notes,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception("Failed to log intake/output: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/ward-nurses", response_model=List[NurseStaffItem])
def get_ward_nurses():
    try:
        return nurse_service.get_ward_nurses()
    except Exception as e:
        logger.exception("Failed to get ward nurses: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/ward-orders")
def get_ward_doctor_orders():
    try:
        return nurse_service.get_ward_doctor_orders()
    except Exception as e:
        logger.exception("Failed to get ward doctor orders: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/ward-mar")
def get_ward_mar():
    try:
        return nurse_service.get_ward_mar()
    except Exception as e:
        logger.exception("Failed to get ward MAR: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/ward-notes")
def get_ward_nursing_notes():
    try:
        return nurse_service.get_ward_nursing_notes()
    except Exception as e:
        logger.exception("Failed to get ward nursing notes: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/lab-orders", response_model=List[NurseLabOrderItem])
def get_nurse_lab_orders(status: Optional[str] = Query(None)):
    try:
        return nurse_service.get_nurse_lab_orders(status)
    except Exception as e:
        logger.exception("Failed to get lab orders: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/lab-orders/pending-count")
def get_pending_lab_count():
    try:
        count = nurse_service.get_pending_lab_count()
        return {"count": count}
    except Exception as e:
        logger.exception("Failed to get pending lab count: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/lab-orders/{lab_id}/complete")
def complete_lab_order(
    lab_id: int,
    payload: LabOrderCompleteRequest,
    nurse_user_id: int = Depends(_get_current_nurse_id),
):
    try:
        return nurse_service.complete_lab_order(lab_id, nurse_user_id, payload.results_text)
    except Exception as e:
        logger.exception("Failed to complete lab order: %s", e)
        raise HTTPException(status_code=500, detail=str(e))



