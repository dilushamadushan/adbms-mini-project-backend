from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field


class AuditLogItem(BaseModel):
    log_id: int = Field(..., description="Unique ID of the audit log record")
    timestamp: str = Field(..., description="Formatted timestamp e.g. 2026-10-13 14:02:11")
    actor: str = Field(..., description="User or actor name e.g. Dr. Sarah Jenkins or admin")
    action: str = Field(..., description="Action performed e.g. LOGIN_SESSION_CREATED, DEPARTMENT_DELETED")
    resource: str = Field(..., description="Affected resource/table e.g. Refresh_Tokens, Departments")
    risk: str = Field(..., description="Risk level: LOW, MEDIUM, HIGH")
    details: Dict[str, Any] = Field(default_factory=dict, description="JSON payload of changes or context")


class AuditLogListResponse(BaseModel):
    items: List[AuditLogItem] = Field(..., description="Paginated audit log items")
    logs: List[AuditLogItem] = Field(..., description="Alias for items to support flexible frontend destructuring")
    total: int = Field(..., description="Total number of matching audit logs")
    page: int = Field(..., description="Current page number (1-indexed)")
    limit: int = Field(..., description="Number of items per page")
    total_pages: int = Field(..., description="Total pages available")


class AuditLogDetailResponse(BaseModel):
    log_id: int
    timestamp: str
    actor: str
    actor_id: Optional[int] = None
    action: str
    resource: str
    risk: str
    details: Dict[str, Any] = Field(default_factory=dict)
