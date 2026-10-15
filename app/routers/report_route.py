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
)
def get_workload_summary_report(
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    top_n: int = Query(5, ge=1, le=50),
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
)
def get_top_providers_workload(
    limit: int = Query(5, ge=1, le=50),
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
)
def export_workload_report_csv(
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
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


@router.get("/kpi-overview", response_model=HospitalKPIOverviewResponse, status_code=status.HTTP_200_OK)
@router.get("/dashboard-stats", response_model=HospitalKPIOverviewResponse, status_code=status.HTTP_200_OK)
@router.get("/overview", response_model=HospitalKPIOverviewResponse, include_in_schema=False)
@router.get("/stats", response_model=HospitalKPIOverviewResponse, include_in_schema=False)
@router.get("/kpis", response_model=HospitalKPIOverviewResponse, include_in_schema=False)
def get_hospital_kpi_overview(
    target_date: Optional[str] = None,
):
    try:
        resolved_date = target_date if isinstance(target_date, str) else None
        return report_service.get_hospital_kpi_overview(target_date=resolved_date)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch hospital KPI overview: {str(e)}",
        )


