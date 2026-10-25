from typing import Optional, Any, List
from pydantic import BaseModel, field_validator

class DoctorDepartmentResponse(BaseModel):
    doctor_name: str
    department_name: str

class BookAppointmentRequest(BaseModel):
    doctor_id: int
    dept_id: int
    apt_date: str
    time_slot: str
    patient_id: Optional[int] = None

class BookAppointmentResponse(BaseModel):
    apt_id: int
    patient_id: int
    doctor_id: int
    dept_id: int
    apt_date: str
    time_slot: str
    status: str

    @field_validator("apt_date", mode="before")
    @classmethod
    def serialize_apt_date(cls, value: Any) -> str:
        return str(value) if value is not None else ""


    @field_validator("time_slot", mode="before")
    @classmethod
    def serialize_time_slot(cls, value: Any) -> str:
        return str(value) if value is not None else ""


from datetime import date
from pydantic import EmailStr, model_validator


class PatientProfileUpdate(BaseModel):
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    dob: Optional[date] = None
    emergency_contact: Optional[str] = None
    email: Optional[EmailStr] = None

    @model_validator(mode="before")
    @classmethod
    def check_forbidden_medical_fields(cls, data: Any):
        if isinstance(data, dict):
            # Explicitly disallow patient self-updates of medical/clinical details
            forbidden = [
                k for k in data.keys()
                if "blood" in k.lower() or k.lower() in ("allergies", "medical_record", "medical_notes", "diagnosis")
            ]
            if forbidden:
                raise ValueError(
                    f"Updating medical details ({', '.join(forbidden)}) is not permitted for patient profile self-service. Please consult hospital medical staff."
                )
        return data


class PatientProfileResponse(BaseModel):
    patient_id: int
    user_id: int
    username: str
    email: Optional[str] = None
    first_name: str
    last_name: str
    dob: Optional[date] = None
    blood_group: Optional[str] = None
    emergency_contact: Optional[str] = None
    allergies: Optional[str] = None


class PatientPrescriptionResponse(BaseModel):
    rx_id: int
    record_id: int
    med_name: str
    dosage: str
    duration: Optional[str] = None
    status: str
    created_at: Optional[Any] = None
    updated_at: Optional[Any] = None

    @field_validator("created_at", "updated_at", mode="before")
    @classmethod
    def serialize_datetime(cls, value: Any) -> Optional[str]:
        return str(value) if value is not None else None


class PatientMedicalRecordResponse(BaseModel):
    record_id: int
    patient_id: int
    patient_name: Optional[str] = None
    doctor_id: int
    doctor_name: Optional[str] = None
    doctor_specialty: Optional[str] = None
    apt_id: Optional[int] = None
    apt_date: Optional[str] = None
    diagnosis: Optional[str] = None
    clinical_notes: Optional[str] = None
    created_at: Optional[Any] = None
    updated_at: Optional[Any] = None
    prescriptions: List[PatientPrescriptionResponse] = []

    @field_validator("created_at", "updated_at", "apt_date", mode="before")
    @classmethod
    def serialize_datetime_fields(cls, value: Any) -> Optional[str]:
        return str(value) if value is not None else None






