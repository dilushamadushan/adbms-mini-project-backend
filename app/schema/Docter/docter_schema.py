from datetime import date, datetime
from typing import Any, Optional, Union
from pydantic import BaseModel, field_validator

class DoctorAppointmentResponse(BaseModel):
    apt_id: int
    patient_id: int
    patient_name: str
    dob: Optional[date] = None
    blood_group: Optional[str] = None
    allergies: Optional[str] = None
    dept_id: int
    dept_name: str
    apt_date: date
    time_slot: str
    status: str

    @field_validator('time_slot', mode='before')
    @classmethod
    def serialize_time_slot(cls, v: Any) -> str:
        if v is None:
            return ""
        return str(v)


class DoctorUpcomingAppointmentResponse(BaseModel):
    apt_id: int
    patient_id: int
    patient_name: str
    age: Optional[Union[int, str]] = None
    apt_date: Union[date, str]
    time_slot: str
    status: str
    reason: Optional[str] = None

    @field_validator('time_slot', mode='before')
    @classmethod
    def serialize_time_slot(cls, v: Any) -> str:
        if v is None:
            return ""
        return str(v)

    @field_validator('patient_name', mode='before')
    @classmethod
    def serialize_patient_name(cls, v: Any) -> str:
        if isinstance(v, (bytes, bytearray)):
            return v.decode('utf-8', errors='replace')
        return str(v)

    @field_validator('reason', mode='before')
    @classmethod
    def serialize_reason(cls, v: Any) -> Optional[str]:
        if v is None:
            return None
        if isinstance(v, (bytes, bytearray)):
            return v.decode('utf-8', errors='replace')
        return str(v)


class DoctorAppointmentGroupedResponse(BaseModel):
    apt_id: int
    patient_id: int
    patient_name: str
    apt_date: Union[date, str]
    appointment_time: str
    status: str
    day_group: str

    @field_validator('patient_name', mode='before')
    @classmethod
    def serialize_patient_name(cls, v: Any) -> str:
        if isinstance(v, (bytes, bytearray)):
            return v.decode('utf-8', errors='replace')
        return str(v) if v is not None else ""

    @field_validator('appointment_time', mode='before')
    @classmethod
    def serialize_appointment_time(cls, v: Any) -> str:
        if isinstance(v, (bytes, bytearray)):
            return v.decode('utf-8', errors='replace')
        return str(v) if v is not None else ""

    @field_validator('status', mode='before')
    @classmethod
    def serialize_status(cls, v: Any) -> str:
        if isinstance(v, (bytes, bytearray)):
            return v.decode('utf-8', errors='replace')
        return str(v) if v is not None else ""

    @field_validator('day_group', mode='before')
    @classmethod
    def serialize_day_group(cls, v: Any) -> str:
        if isinstance(v, (bytes, bytearray)):
            return v.decode('utf-8', errors='replace')
        return str(v) if v is not None else ""


class PatientDetailsResponse(BaseModel):
    patient_id: int
    patient_name: str
    gender: Optional[str] = None
    age: Optional[int] = None
    dob: Optional[str] = None
    phone: Optional[str] = None
    blood_group: Optional[str] = None
    allergies: Optional[str] = None


class PatientAppointmentDetailsResponse(BaseModel):
    apt_date: str
    apt_time: str
    reason: str


class LabOrderPatientDetailsResponse(BaseModel):
    patient_id: int
    patient_name: str
    age: Optional[int] = None
    gender: Optional[str] = None
    blood_group: Optional[str] = None
    allergies: Optional[str] = None
    appointment_id: int
    appointment_date: date
    appointment_status: str


class CreateLabOrderRequest(BaseModel):
    patient_id: int
    doctor_user_id: int
    test_type: str


class CreateLabOrderResponse(BaseModel):
    lab_id: int
    patient_id: int
    doctor_id: int
    test_type: str
    status: str
    results_text: str


class PatientLabResultResponse(BaseModel):
    lab_id: int
    patient_id: int
    patient_name: str
    age: Optional[int] = None
    blood_group: Optional[str] = None
    allergies: Optional[str] = None
    doctor_id: Optional[int] = None
    doctor_name: Optional[str] = None
    test_type: str
    status: str
    result: str
    ordered_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class AdmissionStatusResponse(BaseModel):
    is_admitted: bool
    admission: Optional[dict[str, Any]] = None


class CreateAdmissionRequest(BaseModel):
    patient_id: int
    gender: str
    ward_id: int
    reason: str
    doctor_id: int
    user_id: int


class AdmissionRequestResponse(BaseModel):
    message: str
    admission_id: int


class DischargeRequest(BaseModel):
    admission_id: int
    doctor_id: int
    notes: str


class DischargeRequestResponse(BaseModel):
    message: str


class CompleteAppointmentRequest(BaseModel):
    appointment_id: int
    doctor_id: int


class CompleteAppointmentResponse(BaseModel):
    message: str


class DoctorMedicineResponse(BaseModel):
    medicine_id: int
    med_name: str
    generic_name: Optional[str] = None


class PrescriptionMedicineRequest(BaseModel):
    medicine_id: int
    dose: str
    frequency: str
    duration: str


class CreatePrescriptionRequest(BaseModel):
    patient_id: int
    apt_id: int
    doctor_id: int
    diagnosis: str
    clinical_notes: Optional[str] = None
    medicines: list[PrescriptionMedicineRequest]


class CreatePrescriptionResponse(BaseModel):
    message: str
    record_id: int


class AdmittedPrescriptionMedicineRequest(BaseModel):
    medicine_id: int
    dose: str
    frequency: str
    duration: str
    first_dose: str
    notes: str | None = None


class NurseOrderRequest(BaseModel):
    order_type: str
    instruction: str


class CreateAdmittedPrescriptionRequest(BaseModel):
    patient_id: int
    apt_id: int
    doctor_id: int
    diagnosis: str
    clinical_notes: str | None = None
    medicines: list[AdmittedPrescriptionMedicineRequest]
    nurse_orders: list[NurseOrderRequest] = []
