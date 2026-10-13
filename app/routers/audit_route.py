from typing import Optional, List
from fastapi import APIRouter, HTTPException, Query, Response, status
from app.schema.audit_schema import (
    AuditLogItem,
    AuditLogListResponse,
    AuditLogDetailResponse,
)
from app.services import audit_service

router = APIRouter(prefix="/audit-logs", tags=["Audit Logs"])


@router.get(
    "/recent",
    response_model=List[AuditLogItem],
    status_code=status.HTTP_200_OK,
    summary="Get Recent Audit Logs Widget Data",
    description="Returns the most recent audit logs for the admin dashboard widget (defaults to 4 items).",
)
def get_recent_audit_logs(
    limit: int = Query(4, ge=1, le=50, description="Number of recent logs to return"),
):
    try:
        return audit_service.get_recent_audit_logs(limit=limit)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch recent audit logs: {str(e)}",
        )


@router.get(
    "/export",
    status_code=status.HTTP_200_OK,
    summary="Export Audit Logs as CSV",
    description="Downloads filtered audit logs as a CSV file.",
)
def export_audit_logs(
    actor: Optional[str] = Query(None, description="Filter by actor name or username"),
    action: Optional[str] = Query(None, description="Filter by action type"),
    risk: Optional[str] = Query(None, description="Filter by risk level (LOW, MEDIUM, HIGH)"),
    date: Optional[str] = Query(None, description="Filter by date (YYYY-MM-DD)"),
):
    try:
        csv_data = audit_service.export_audit_logs_to_csv(
            actor=actor,
            action=action,
            risk=risk,
            date=date,
        )
        return Response(
            content=csv_data,
            media_type="text/csv",
            headers={
                "Content-Disposition": "attachment; filename=audit_logs.csv",
                "Cache-Control": "no-cache",
            },
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to export audit logs: {str(e)}",
        )


@router.get(
    "",
    response_model=AuditLogListResponse,
    status_code=status.HTTP_200_OK,
    summary="Get Full Audit Logs Table (Paginated)",
    description="""
    Retrieves paginated audit log entries for the Admin Audit Logs table.
    
    Supports filtering by:
    - `page`: Page index (1-based, default 1)
    - `limit`: Items per page (default 10)
    - `actor`: Actor name or username (e.g. Dr. Sarah Jenkins or admin)
    - `action`: Action type (e.g. LOGIN_SESSION_CREATED, DEPARTMENT_DELETED)
    - `risk`: Risk level ('LOW', 'MEDIUM', 'HIGH')
    - `date`: Specific date filter (YYYY-MM-DD)
    
    Employs MySQL Stored Procedure `sp_get_audit_logs`, Enriched View `vw_audit_logs_enriched`,
    and deterministic risk function `fn_get_audit_risk`.
    """,
)
@router.get(
    "/",
    response_model=AuditLogListResponse,
    status_code=status.HTTP_200_OK,
    include_in_schema=False,
)
def get_audit_logs(
    page: int = Query(1, ge=1, description="Page number (1-based)"),
    limit: int = Query(10, ge=1, le=100, description="Items per page"),
    actor: Optional[str] = Query(None, description="Filter by actor name or username"),
    action: Optional[str] = Query(None, description="Filter by action type"),
    risk: Optional[str] = Query(None, description="Filter by risk level (LOW, MEDIUM, HIGH)"),
    date: Optional[str] = Query(None, description="Filter by date (YYYY-MM-DD)"),
):
    try:
        return audit_service.list_audit_logs(
            page=page,
            limit=limit,
            actor=actor,
            action=action,
            risk=risk,
            date=date,
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch audit logs: {str(e)}",
        )


@router.get(
    "/{log_id}",
    response_model=AuditLogDetailResponse,
    status_code=status.HTTP_200_OK,
    summary="Get Single Audit Log Details",
    description="Retrieves complete information and full JSON details for a single audit log entry by ID.",
)
def get_single_audit_log(
    log_id: int,
):
    try:
        log = audit_service.get_audit_log_by_id(log_id=log_id)
        if not log:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Audit log with ID {log_id} not found",
            )
        return log
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch audit log #{log_id}: {str(e)}",
        )
