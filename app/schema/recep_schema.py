from datetime import date, datetime, time
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, Field


class ReceptionistOverview(BaseModel):
    total_patients: int
    active_admissions: int
    appointments_today: int
    appointments: list[dict]


class AvailableBed(BaseModel):
    bed_id: int
    bed_number: str
    ward_id: int
    ward_name: str


class WardResponse(BaseModel):
    ward_id: int
    ward_name: str


class AdmissionCreate(BaseModel):
    patient_id: int
    ward_id: int
    admitted_doctor_id: int
    admission_reason: str = Field(min_length=1, max_length=4000)
    guardian_name: str = Field(min_length=1, max_length=200)
    guardian_relationship: str = Field(min_length=1, max_length=100)
    guardian_contact: str = Field(min_length=1, max_length=20)
    gender: str = Field(pattern="^(Female|Male)$")


class AdmissionGuardianUpdate(BaseModel):
    guardian_name: str = Field(min_length=1, max_length=200)
    guardian_relationship: str = Field(min_length=1, max_length=100)
    guardian_contact: str = Field(min_length=1, max_length=20)


class AdmissionBedAssignment(BaseModel):
    bed_id: int


class AdmissionResponse(BaseModel):
    admission_id: int
    patient_id: int
    patient_name: str
    ward_id: int
    ward_name: str
    admitted_doctor_id: int
    admitted_doctor_name: str
    guardian_name: str
    guardian_relationship: str
    guardian_contact: str
    gender: Optional[str] = None
    bed_id: Optional[int] = None
    bed_number: Optional[str] = None
    admitted_at: datetime
    admission_reason: str
    status: str
    discharge_authorized_by: Optional[int] = None
    discharge_authorized_at: Optional[datetime] = None
    discharge_notes: Optional[str] = None
    bill_id: Optional[int] = None
    room_charges: Optional[Decimal] = None
    treatment_charges: Optional[Decimal] = None
    other_charges: Optional[Decimal] = None
    total_amount: Optional[Decimal] = None
    amount_paid: Optional[Decimal] = None
    payment_method: Optional[str] = None
    payment_status: Optional[str] = None


class DischargeAuthorization(BaseModel):
    discharge_notes: str = Field(min_length=1, max_length=4000)


class DischargeBillCreate(BaseModel):
    room_charges: Decimal = Field(ge=0, max_digits=10, decimal_places=2)
    treatment_charges: Decimal = Field(ge=0, max_digits=10, decimal_places=2)
    other_charges: Decimal = Field(default=Decimal("0.00"), ge=0, max_digits=10, decimal_places=2)
    amount_paid: Decimal = Field(default=Decimal("0.00"), ge=0, max_digits=10, decimal_places=2)
    payment_method: Optional[str] = Field(default=None, max_length=40)


class BillPayment(BaseModel):
    amount: Decimal = Field(gt=0, max_digits=10, decimal_places=2)
    payment_method: str = Field(min_length=1, max_length=40)


class AdmissionActionResponse(BaseModel):
    message: str
    admission: AdmissionResponse


class RecepPatientCreate(BaseModel):
    first_name: str = Field(min_length=1, max_length=100)
    last_name: str = Field(min_length=1, max_length=100)
    email: str
    dob: date
    blood_group: Optional[str] = None
    emergency_contact: str = Field(min_length=1, max_length=20)
    allergies: Optional[str] = Field(default="Unknown", max_length=2000)


class RecepPatientResponse(BaseModel):
    patient_id: int
    user_id: int
    username: str
    email: str
    first_name: str
    last_name: str
    dob: Optional[date] = None
    blood_group: Optional[str] = None
    emergency_contact: Optional[str] = None
    allergies: Optional[str] = None
    raw_password: Optional[str] = None


class RecepAppointmentCreate(BaseModel):
    patient_id: int
    doctor_id: int
    dept_id: int
    apt_date: date
    time_slot: time


class RecepAppointmentUpdate(BaseModel):
    apt_date: date
    time_slot: time


class RecepAppointmentStatus(BaseModel):
    status: str


class RecepAppointmentResponse(BaseModel):
    apt_id: int
    patient_id: int
    patient_name: str
    doctor_id: int
    doctor_name: str
    dept_id: int
    dept_name: str
    apt_date: date
    time_slot: str
    status: str
