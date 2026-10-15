from typing import Optional, List
from fastapi import APIRouter, HTTPException, Query, Response, status
from app.schema.audit_schema import (
    AuditLogItem,
    AuditLogListResponse,
    AuditLogDetailResponse,
)
from app.services import audit_service

router = APIRouter(prefix="/audit-logs", tags=["Audit Logs"])

@router.get("/recent",response_model=List[AuditLogItem],status_code=status.HTTP_200_OK)
def get_recent_audit_logs(limit: int = Query(4, ge=1, le=50)):
    try:
        return audit_service.get_recent_audit_logs(limit=limit)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch recent audit logs: {str(e)}",
        )


@router.get("/export",status_code=status.HTTP_200_OK)
def export_audit_logs(actor: Optional[str] = None,
    action: Optional[str] = None,
    risk: Optional[str] = None,
    date: Optional[str] = None,
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


@router.get("",response_model=AuditLogListResponse,status_code=status.HTTP_200_OK)
@router.get("/",response_model=AuditLogListResponse,status_code=status.HTTP_200_OK,include_in_schema=False,)
def get_audit_logs(
    page: int = Query(1, ge=1),
    limit: int = Query(10, ge=1, le=100),
    actor: Optional[str] = Query(None),
    action: Optional[str] = Query(None),
    risk: Optional[str] = Query(None),
    date: Optional[str] = Query(None),
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


@router.get("/{log_id}",response_model=AuditLogDetailResponse,status_code=status.HTTP_200_OK)
def get_single_audit_log(log_id: int):
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
