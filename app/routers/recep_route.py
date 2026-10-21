from datetime import date

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, status

from app.core.security import get_current_user_payload
from app.services import recep_service
from app.schema.recep_schema import (
    AdmissionActionResponse,
    AdmissionBedAssignment,
    AdmissionCreate,
    AdmissionResponse,
    AvailableBed,
    BillPayment,
    DischargeAuthorization,
    DischargeBillCreate,
    RecepAppointmentCreate,
    RecepAppointmentResponse,
    RecepAppointmentStatus,
    RecepAppointmentUpdate,
    RecepPatientCreate,
    RecepPatientResponse,
    ReceptionistOverview,
    WardResponse,
)

router = APIRouter(prefix="/receptionist", tags=["Receptionist"])


def _identity(payload: dict) -> tuple[int, str]:
    try:
        return int(payload["sub"]), str(payload.get("role", "")).lower()
    except (KeyError, TypeError, ValueError) as exc:
        raise HTTPException(status_code=401, detail="Invalid authentication identity") from exc


@router.get("/overview", response_model=ReceptionistOverview)
def get_overview(payload: dict = Depends(get_current_user_payload)):
    user_id, role = _identity(payload)
    return recep_service.get_overview(user_id, role)


@router.get("/wards", response_model=list[WardResponse])
def get_wards(payload: dict = Depends(get_current_user_payload)):
    user_id, role = _identity(payload)
    return recep_service.get_wards(user_id, role)


@router.get("/beds/available", response_model=list[AvailableBed])
def get_available_beds(
    ward_id: int | None = None,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    return recep_service.get_available_beds(user_id, role, ward_id)


@router.get("/admissions", response_model=list[AdmissionResponse])
def get_admissions(
    active_only: bool = True,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    return recep_service.list_admissions(user_id, role, active_only)


@router.post("/admissions", response_model=AdmissionResponse, status_code=status.HTTP_201_CREATED)
def admit_patient(
    admission: AdmissionCreate,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    return recep_service.admit_patient(
        user_id,
        role,
        admission.patient_id,
        admission.ward_id,
        admission.admitted_doctor_id,
        admission.admission_reason,
        admission.guardian_name,
        admission.guardian_relationship,
        admission.guardian_contact,
        admission.gender,
    )


@router.patch("/admissions/{admission_id}/bed", response_model=AdmissionResponse)
def assign_admission_bed(
    admission_id: int,
    assignment: AdmissionBedAssignment,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    return recep_service.assign_admission_bed(
        user_id, role, admission_id, assignment.bed_id
    )


@router.patch(
    "/admissions/{admission_id}/authorize-discharge",
    response_model=AdmissionResponse,
)
def authorize_discharge(
    admission_id: int,
    authorization: DischargeAuthorization,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    return recep_service.authorize_discharge(
        user_id, role, admission_id, authorization.discharge_notes
    )


@router.post(
    "/admissions/{admission_id}/discharge",
    response_model=AdmissionActionResponse,
)
def discharge_authorized_patient(
    admission_id: int,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    admission = recep_service.discharge_authorized_patient(
        user_id, role, admission_id
    )
    return {
        "message": f"{admission['patient_name']} discharged successfully.",
        "admission": admission,
    }


@router.post(
    "/admissions/{admission_id}/discharge-bill",
    response_model=AdmissionActionResponse,
)
def calculate_discharge_bill(
    admission_id: int,
    bill: DischargeBillCreate,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    admission = recep_service.calculate_discharge_bill(
        user_id,
        role,
        admission_id,
        bill.room_charges,
        bill.treatment_charges,
        bill.other_charges,
        bill.amount_paid,
        bill.payment_method,
    )
    message = (
        "Bill paid; patient discharged."
        if admission["status"] == "Discharged"
        else "Bill calculated. Record the remaining payment before discharge."
    )
    return {"message": message, "admission": admission}


@router.post(
    "/admissions/{admission_id}/payments",
    response_model=AdmissionActionResponse,
)
def pay_discharge_balance(
    admission_id: int,
    payment: BillPayment,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    admission = recep_service.pay_discharge_balance(
        user_id, role, admission_id, payment.amount, payment.payment_method
    )
    message = (
        "Payment complete; patient discharged."
        if admission["status"] == "Discharged"
        else "Payment recorded; balance remains outstanding."
    )
    return {"message": message, "admission": admission}


@router.post("/patients", response_model=RecepPatientResponse, status_code=status.HTTP_201_CREATED)
def register_patient(
    patient: RecepPatientCreate,
    background_tasks: BackgroundTasks,
    payload: dict = Depends(get_current_user_payload),
):
    _, role = _identity(payload)
    if role not in {"receptionist", "admin"}:
        raise HTTPException(status_code=403, detail="Receptionist access required")
    return recep_service.register_patient(patient.model_dump(), background_tasks)


@router.get("/patients", response_model=list[RecepPatientResponse])
def get_patient_records(
    search: str | None = None,
    payload: dict = Depends(get_current_user_payload),
):
    _, role = _identity(payload)
    return recep_service.search_patients(role, search)


@router.get("/appointments", response_model=list[RecepAppointmentResponse])
def get_appointments(
    patient_id: int | None = None,
    appointment_date: date | None = Query(default=None, alias="date"),
    patient_name: str | None = None,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    return recep_service.get_appointments(user_id, role, patient_id, appointment_date, patient_name)


@router.post("/appointments", response_model=RecepAppointmentResponse, status_code=status.HTTP_201_CREATED)
def create_appointment(
    appointment: RecepAppointmentCreate,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    return recep_service.create_appointment(
        user_id, role, appointment.patient_id, appointment.doctor_id, appointment.dept_id,
        appointment.apt_date, appointment.time_slot,
    )


@router.patch("/appointments/{appointment_id}/schedule", response_model=RecepAppointmentResponse)
def update_appointment(
    appointment_id: int,
    schedule: RecepAppointmentUpdate,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    return recep_service.update_appointment(
        user_id, role, appointment_id, schedule.apt_date, schedule.time_slot
    )


@router.patch("/appointments/{appointment_id}/status", response_model=RecepAppointmentResponse)
def update_appointment_status(
    appointment_id: int,
    update: RecepAppointmentStatus,
    payload: dict = Depends(get_current_user_payload),
):
    user_id, role = _identity(payload)
    return recep_service.change_appointment_status(user_id, role, appointment_id, update.status)
