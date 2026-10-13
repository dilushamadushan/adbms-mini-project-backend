from typing import Optional, List
from fastapi import APIRouter, HTTPException, Query, Response, status
from app.schema.report_schema import (
    WorkloadReportResponse,
    DepartmentWorkloadResponse,
    ProviderWorkloadResponse,
    WorkloadRollupItem,
    HospitalKPIOverviewResponse,
)
from app.services import report_service

router = APIRouter(prefix="/reports", tags=["Reports & Analytics"])


@router.get(
    "/workload-summary",
    response_model=WorkloadReportResponse,
    status_code=status.HTTP_200_OK,
    summary="Get Hospital Workload & Provider Performance Summary",
    description="""
    Generates workload analytics report corresponding to the dashboard UI cards:
    - **Department Workload**: Emergency, Cardiology, General Med, Orthopedics with status (Critical, High, Moderate, Low) and progress bar percentages.
    - **Top Provider Workload**: Provider Name (Dr. ...), Pts Seen, Avg Time (e.g. 18m, 22m, 15m), and rank.
    
    **Advanced Database Concepts Employed**:
    - Stored Procedure `sp_generate_workload_report`
    - Common Table Expressions (CTEs)
    - SQL Window Functions: `DENSE_RANK() OVER (...)`, `SUM() OVER ()`
    - Deterministic Functions: `fn_calculate_provider_avg_time`, `fn_get_workload_level`
    """,
)
def get_workload_summary_report(
    start_date: Optional[str] = Query(None, description="Optional start date filter (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="Optional end date filter (YYYY-MM-DD)"),
    top_n: int = Query(5, ge=1, le=50, description="Number of top providers to return"),
):
    try:
        return report_service.generate_workload_report(
            start_date=start_date, end_date=end_date, top_n=top_n
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate workload report: {str(e)}",
        )


@router.get(
    "/departments/workload",
    response_model=DepartmentWorkloadResponse,
    status_code=status.HTTP_200_OK,
    summary="Get Department Workload Breakdown",
    description="Fetches department workload metrics via database view `vw_department_workload` with normalized bar percentages.",
)
def get_department_workload():
    try:
        return report_service.get_department_workload_summary()
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch department workload: {str(e)}",
        )


@router.get(
    "/providers/workload",
    response_model=ProviderWorkloadResponse,
    status_code=status.HTTP_200_OK,
    summary="Get Top Provider Workload Table",
    description="Fetches top ranked providers with Patients Seen, Average Consultation Time, and ranking via database view `vw_top_provider_workload`.",
)
def get_top_providers_workload(
    limit: int = Query(5, ge=1, le=50, description="Maximum providers to return"),
):
    try:
        return report_service.get_top_providers_summary(limit=limit)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch top providers workload: {str(e)}",
        )


@router.get(
    "/analytics/rollup",
    response_model=List[WorkloadRollupItem],
    status_code=status.HTTP_200_OK,
    summary="Get Workload Hierarchy with SQL ROLLUP",
    description="Advanced DB reporting query using MySQL `GROUP BY dept_name, status WITH ROLLUP` for subtotals and grand total.",
)
def get_workload_rollup():
    try:
        return report_service.get_rollup_analytics()
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate rollup analytics: {str(e)}",
        )


@router.get(
    "/export/csv",
    status_code=status.HTTP_200_OK,
    summary="Export Workload Report as CSV",
    description="Generates downloadable CSV containing Department Workload and Provider Workload metrics.",
)
def export_workload_report_csv(
    start_date: Optional[str] = Query(None, description="Optional start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="Optional end date (YYYY-MM-DD)"),
    top_n: int = Query(10, ge=1, le=100),
):
    try:
        csv_data = report_service.export_workload_csv(
            start_date=start_date, end_date=end_date, top_n=top_n
        )
        return Response(
            content=csv_data,
            media_type="text/csv",
            headers={"Content-Disposition": "attachment; filename=hospital_workload_report.csv"},
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to export report CSV: {str(e)}",
        )


@router.get(
    "/kpi-overview",
    response_model=HospitalKPIOverviewResponse,
    status_code=status.HTTP_200_OK,
    summary="Get Hospital Key Metrics (Total Patients, Bed Occupancy, Today's Appointments)",
    description="""
    Fetches real-time hospital executive dashboard metrics:
    - **Total Patients**: Number of registered patients in the hospital system (`Patients`).
    - **Bed Occupancy**: Real-time bed occupancy rate percentage and bed status counts (`Beds`).
    - **Today's Appointments**: Total appointments scheduled and completed for today (`Appointments`).
    
    Accepts an optional `date` query parameter (YYYY-MM-DD), defaulting to `CURDATE()`.
    """,
)
@router.get(
    "/dashboard-stats",
    response_model=HospitalKPIOverviewResponse,
    status_code=status.HTTP_200_OK,
    summary="Get Hospital Dashboard Stats (Alias)",
    description="Alias for `/reports/kpi-overview` providing total patients, bed occupancy, and today's appointments.",
)
@router.get("/overview", response_model=HospitalKPIOverviewResponse, include_in_schema=False)
@router.get("/stats", response_model=HospitalKPIOverviewResponse, include_in_schema=False)
@router.get("/kpis", response_model=HospitalKPIOverviewResponse, include_in_schema=False)
def get_hospital_kpi_overview(
    target_date: Optional[str] = Query(None, alias="date", description="Optional date filter (YYYY-MM-DD), defaults to CURDATE()"),
):
    try:
        resolved_date = target_date if isinstance(target_date, str) else None
        return report_service.get_hospital_kpi_overview(target_date=resolved_date)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch hospital KPI overview: {str(e)}",
        )


