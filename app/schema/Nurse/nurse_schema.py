from typing import List, Optional
from pydantic import BaseModel, Field


class WardBedItem(BaseModel):
    bed_id: int
    bed_number: str
    ward_id: int
    bed_status: str
    current_patient_id: Optional[int] = None
    patient_name: Optional[str] = None
    gender: Optional[str] = None
    dob: Optional[str] = None
    blood_group: Optional[str] = None
    allergies: Optional[str] = None
    admission_id: Optional[int] = None
    admitted_at: Optional[str] = None
    admission_reason: Optional[str] = None
    attending_doctor_name: Optional[str] = None
    discharge_id: Optional[int] = None
    discharge_status: Optional[str] = None
    vitals_status: Optional[str] = None
    latest_bp: Optional[str] = None
    latest_pulse: Optional[int] = None
    latest_temperature: Optional[float] = None
    latest_spo2: Optional[int] = None
    latest_resp_rate: Optional[int] = None
    latest_vitals_summary: Optional[str] = None
    latest_vitals_time: Optional[str] = None


class WardOverviewResponse(BaseModel):
    ward_id: int
    ward_name: str
    total_beds: int
    occupied_beds: int
    available_beds: int
    cleaning_beds: int
    occupancy_rate: float
    beds: List[WardBedItem] = []
    assigned_wards: List[dict] = []


class AssignBedRequest(BaseModel):
    admission_id: int


class UnassignedAdmissionItem(BaseModel):
    admission_id: int
    patient_id: int
    patient_name: str
    gender: Optional[str] = None
    dob: Optional[str] = None
    blood_group: Optional[str] = None
    allergies: Optional[str] = None
    admission_reason: Optional[str] = None
    admitted_at: Optional[str] = None
    guardian_name: Optional[str] = None
    guardian_contact: Optional[str] = None
    attending_doctor_name: Optional[str] = None
    target_ward_id: Optional[int] = None


class DashboardStatsResponse(BaseModel):
    ward_id: int
    ward_name: str
    total_beds: int
    occupied_beds: int
    available_beds: int
    cleaning_beds: int
    active_shift: str
    critical_patients_count: int
    medications_due_count: int
    pending_orders_count: int


class VitalsLogItem(BaseModel):
    vital_id: int
    patient_id: int
    bp: Optional[str] = None
    pulse: Optional[int] = None
    temperature: Optional[float] = None
    spo2: Optional[int] = None
    resp_rate: Optional[int] = None
    blood_sugar: Optional[float] = None
    weight: Optional[float] = None
    recorded_at: Optional[str] = None
    recorded_by_name: Optional[str] = None


class VitalsLogCreate(BaseModel):
    bp: str = Field(..., description="Blood Pressure in format 120/80")
    pulse: int = Field(..., ge=30, le=250, description="Heart pulse in bpm")
    temperature: float = Field(..., ge=90.0, le=110.0, description="Temperature in Fahrenheit")
    spo2: Optional[int] = Field(98, ge=50, le=100, description="Oxygen Saturation SpO2 (%)")
    resp_rate: Optional[int] = Field(16, ge=4, le=60, description="Respiratory Rate (breaths/min)")
    blood_sugar: Optional[float] = Field(None, ge=20.0, le=600.0, description="Blood Sugar mg/dL")
    weight: Optional[float] = Field(None, ge=1.0, le=300.0, description="Weight in kg")


class VitalsLogResponse(BaseModel):
    vital_id: int
    patient_id: int
    bp: str
    pulse: int
    temperature: float
    spo2: Optional[int] = None
    resp_rate: Optional[int] = None
    blood_sugar: Optional[float] = None
    weight: Optional[float] = None
    recorded_at: str
    recorded_by_name: Optional[str] = None
    current_status: Optional[str] = "STABLE"


class BedDetailResponse(BaseModel):
    bed_id: int
    bed_number: str
    ward_id: int
    ward_name: str
    bed_status: str
    patient_id: Optional[int] = None
    patient_name: Optional[str] = None
    dob: Optional[str] = None
    age: Optional[int] = None
    blood_group: Optional[str] = None
    emergency_contact: Optional[str] = None
    allergies: Optional[str] = None
    admission_id: Optional[int] = None
    admitted_at: Optional[str] = None
    admission_reason: Optional[str] = None
    attending_doctor: Optional[str] = None
    discharge_id: Optional[int] = None
    discharge_status: Optional[str] = None
    discharge_notes: Optional[str] = None
    recent_vitals: List[VitalsLogItem] = []


class BedStatusUpdate(BaseModel):
    status: str = Field(..., description="'Available' or 'Cleaning'")


class WardPatientItem(BaseModel):
    patient_id: int
    patient_name: str
    dob: Optional[str] = None
    age: Optional[int] = None
    blood_group: Optional[str] = None
    emergency_contact: Optional[str] = None
    allergies: Optional[str] = None
    admission_id: int
    admitted_at: Optional[str] = None
    admission_reason: Optional[str] = None
    admission_status: str
    ward_id: int
    ward_name: str
    bed_id: Optional[int] = None
    bed_number: Optional[str] = None
    bed_status: Optional[str] = None
    attending_doctor: Optional[str] = None
    discharge_id: Optional[int] = None
    discharge_status: Optional[str] = None
    vitals_status: Optional[str] = "STABLE"


class DischargeCompleteResponse(BaseModel):
    discharge_id: int
    admission_id: int
    status: str
    freed_bed_id: Optional[int] = None
    message: str


class MarPrescriptionItem(BaseModel):
    rx_id: int
    med_name: str
    dosage: str
    duration: Optional[str] = None
    rx_status: str
    doctor_name: Optional[str] = None
    has_allergy_conflict: bool = False
    patient_allergies: Optional[str] = None
    last_status: Optional[str] = None
    last_administered_at: Optional[str] = None


class MarHistoryItem(BaseModel):
    mar_id: int
    rx_id: int
    med_name: str
    dosage: str
    status: str
    reason: Optional[str] = None
    notes: Optional[str] = None
    administered_at: str
    administered_by_name: Optional[str] = None


class MarOverviewResponse(BaseModel):
    prescriptions: List[MarPrescriptionItem] = []
    history: List[MarHistoryItem] = []


class MarAdministerRequest(BaseModel):
    rx_id: int
    status: str = Field(..., description="'Given', 'Not Given', 'Refused', 'Held'")
    reason: Optional[str] = Field(None, description="Reason if not given, refused or held")
    notes: Optional[str] = None


class MarAdministerResponse(BaseModel):
    mar_id: int
    rx_id: int
    patient_id: int
    status: str
    reason: Optional[str] = None
    notes: Optional[str] = None
    administered_at: str
    administered_by_name: Optional[str] = None


class DoctorOrderItem(BaseModel):
    order_id: int
    patient_id: int
    order_type: str
    instruction: str
    status: str
    doctor_name: Optional[str] = None
    acknowledged_by: Optional[int] = None
    acknowledged_by_name: Optional[str] = None
    acknowledged_at: Optional[str] = None
    completed_by: Optional[int] = None
    completed_at: Optional[str] = None
    created_at: str


class DoctorOrderStatusUpdate(BaseModel):
    status: str = Field(..., description="'Acknowledged' or 'Done'")


class NursingNoteItem(BaseModel):
    note_id: int
    patient_id: int
    note_type: str
    subjective: Optional[str] = None
    objective: Optional[str] = None
    assessment: Optional[str] = None
    plan: Optional[str] = None
    content: str
    created_at: str
    nurse_name: Optional[str] = None


class NursingNoteCreate(BaseModel):
    note_type: str = Field("SOAP", description="'SOAP', 'CarePlan', 'WoundCare', 'General'")
    subjective: Optional[str] = None
    objective: Optional[str] = None
    assessment: Optional[str] = None
    plan: Optional[str] = None
    content: str = Field(..., description="Full note content or summary")


class IntakeOutputItem(BaseModel):
    io_id: int
    io_type: str
    category: str
    volume_ml: int
    notes: Optional[str] = None
    entry_time: str
    recorded_by_name: Optional[str] = None


class IntakeOutputSummaryResponse(BaseModel):
    summary_date: str
    total_intake_ml: int
    total_output_ml: int
    net_balance_ml: int
    entries: List[IntakeOutputItem] = []


class IntakeOutputCreate(BaseModel):
    io_type: str = Field(..., description="'Intake' or 'Output'")
    category: str = Field(..., description="'Oral', 'IV Fluids', 'Urine', 'Drain', 'NG Tube'")
    volume_ml: int = Field(..., ge=1, description="Volume in milliliters")
    notes: Optional[str] = None



class NurseStaffItem(BaseModel):
    staff_id: int
    user_id: int
    nurse_name: str
    username: str
    specialty: Optional[str] = None



