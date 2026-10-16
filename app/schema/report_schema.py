from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field


class DepartmentWorkloadItem(BaseModel):
    dept_id: int
    dept_name: str
    doctor_count: int = 0
    total_appointments: int = 0
    pts_seen: int = 0
    workload_percentage: float = Field(..., description="Percentage of total hospital appointments")
    progress_bar_pct: float = Field(..., description="Normalized 0-100% value for UI workload bar rendering")
    dept_rank: int
    workload_level: str = Field(..., description="Critical, High, Moderate, or Low")


class ProviderWorkloadItem(BaseModel):
    staff_id: int
    provider_name: str
    specialty: Optional[str] = None
    dept_name: Optional[str] = None
    pts_seen: int = Field(..., description="Patients seen count")
    avg_time_minutes: int = Field(..., description="Average consultation duration in minutes")
    avg_time: str = Field(..., description="Formatted duration e.g. 18m")
    workload_rank: int
    share_percentage: float


class WorkloadSummaryKPIs(BaseModel):
    total_departments: int
    total_appointments: int
    total_pts_seen: int
    busiest_department: Optional[str] = None
    top_provider: Optional[str] = None
    hospital_avg_consult_time: str


class WorkloadReportResponse(BaseModel):
    report_title: str = "Hospital Workload & Provider Performance Report"
    generated_at: str
    period_start: Optional[str] = None
    period_end: Optional[str] = None
    summary_kpis: WorkloadSummaryKPIs
    department_workload: List[DepartmentWorkloadItem]
    top_providers: List[ProviderWorkloadItem]
    db_concepts_used: List[str] = Field(
        default=[
            "Stored Procedure (sp_generate_workload_report)",
            "Window Functions (DENSE_RANK, SUM OVER, PERCENT_RANK)",
            "Common Table Expressions (CTEs)",
            "Database Views (vw_department_workload, vw_top_provider_workload)",
            "Deterministic Stored Functions (fn_calculate_provider_avg_time, fn_get_workload_level)",
        ]
    )


class DepartmentWorkloadResponse(BaseModel):
    departments: List[DepartmentWorkloadItem]
    total_departments: int


class ProviderWorkloadResponse(BaseModel):
    providers: List[ProviderWorkloadItem]
    total_providers_ranked: int


class WorkloadRollupItem(BaseModel):
    dept_name: Optional[str] = None
    status: Optional[str] = None
    appointment_count: int


class BedOccupancyDetails(BaseModel):
    total_beds: int = Field(..., description="Total hospital beds")
    occupied_beds: int = Field(..., description="Number of currently occupied beds")
    available_beds: int = Field(..., description="Number of available beds")
    cleaning_beds: int = Field(0, description="Number of beds undergoing cleaning/turnover")
    occupancy_rate: float = Field(..., description="Bed occupancy percentage")
    formatted_occupancy: str = Field(..., description="Formatted bed occupancy rate (e.g. 33.33%)")


class TodayAppointmentsDetails(BaseModel):
    total_today: int = Field(..., description="Total appointments on this date")
    scheduled: int = Field(0, description="Scheduled appointments")
    completed: int = Field(0, description="Completed appointments")
    cancelled: int = Field(0, description="Cancelled appointments")
    no_show: int = Field(0, description="No-show appointments")


class HospitalKPIOverviewResponse(BaseModel):
    total_patients: int = Field(..., description="Total registered patients")
    total_patient: int = Field(..., description="Alias for total_patients")
    bed_occupancy: float = Field(..., description="Hospital bed occupancy percentage (e.g. 33.33)")
    bed_occupancy_pct: float = Field(..., description="Hospital bed occupancy percentage")
    bed_occupancy_formatted: str = Field(..., description="Formatted bed occupancy rate (e.g. 33.3%)")
    total_beds: int = Field(..., description="Total beds capacity")
    occupied_beds: int = Field(..., description="Total occupied beds")
    available_beds: int = Field(..., description="Total available beds")
    todays_appointments: int = Field(..., description="Total appointments for today")
    today_appointments: int = Field(..., description="Alias for todays_appointments")
    today_appts: int = Field(..., description="Alias for todays_appointments")
    target_date: str = Field(..., description="Date corresponding to appointment counts (YYYY-MM-DD)")
    bed_details: Optional[BedOccupancyDetails] = None
    appointment_details: Optional[TodayAppointmentsDetails] = None

