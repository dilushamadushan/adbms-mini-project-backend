from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field


class NotificationItem(BaseModel):
    notification_id: int
    title: str
    message: str
    type: str = "INFO"
    target_role: Optional[str] = "admin"
    target_user_id: Optional[int] = None
    is_read: bool = False
    details: Optional[Dict[str, Any]] = None
    created_at: str


class NotificationListResponse(BaseModel):
    items: List[NotificationItem]
    notifications: List[NotificationItem] = Field(..., description="Alias for items")
    total: int
    unread_count: int
    page: int
    limit: int
    total_pages: int


class UnreadCountResponse(BaseModel):
    unread_count: int


class NotificationActionResponse(BaseModel):
    notification_id: Optional[int] = None
    updated_count: Optional[int] = None
    is_read: Optional[bool] = None
    message: str
