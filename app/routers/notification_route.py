from typing import Optional
from fastapi import APIRouter, HTTPException, Query, status
from app.schema.notification_schema import (
    NotificationListResponse,
    UnreadCountResponse,
    NotificationActionResponse,
)
from app.services import notification_service

router = APIRouter(prefix="/notifications", tags=["Notifications"])


@router.get(
    "/unread-count",
    response_model=UnreadCountResponse,
    status_code=status.HTTP_200_OK,
    summary="Get Unread Notifications Count",
    description="Returns the total number of unread notifications for the notification bell badge.",
)
def get_unread_count(
    role: Optional[str] = Query("admin", description="Target role (e.g. admin)"),
):
    try:
        count = notification_service.get_unread_count(target_role=role)
        return {"unread_count": count}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch unread notifications count: {str(e)}",
        )


@router.patch(
    "/mark-all-read",
    response_model=NotificationActionResponse,
    status_code=status.HTTP_200_OK,
    summary="Mark All Notifications as Read",
    description="Updates all unread notifications to read status.",
)
def mark_all_as_read(
    role: Optional[str] = Query("admin", description="Target role (e.g. admin)"),
):
    try:
        updated = notification_service.mark_all_as_read(target_role=role)
        return {
            "updated_count": updated,
            "message": f"Marked {updated} notification(s) as read",
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to mark all notifications as read: {str(e)}",
        )


@router.get(
    "",
    response_model=NotificationListResponse,
    status_code=status.HTTP_200_OK,
    summary="Get Notifications (Paginated)",
    description="""
    Retrieves hospital system notifications automatically created by database triggers:
    - New staff member added (`STAFF_ADDED`)
    - New department created (`DEPARTMENT_ADDED`)
    - Department removed (`DEPARTMENT_DELETED`)
    
    Supports pagination and filtering by read status and event type.
    """,
)
@router.get(
    "/",
    response_model=NotificationListResponse,
    status_code=status.HTTP_200_OK,
    include_in_schema=False,
)
def get_notifications(
    page: int = Query(1, ge=1, description="Page index (1-based)"),
    limit: int = Query(10, ge=1, le=100, description="Items per page"),
    is_read: Optional[bool] = Query(None, description="Filter by read status (true/false)"),
    type: Optional[str] = Query(None, description="Filter by notification type (e.g. STAFF_ADDED, DEPARTMENT_ADDED)"),
    role: Optional[str] = Query("admin", description="Target role (default: admin)"),
):
    try:
        return notification_service.list_notifications(
            page=page,
            limit=limit,
            is_read=is_read,
            notif_type=type,
            target_role=role,
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch notifications: {str(e)}",
        )


@router.patch(
    "/{notification_id}/read",
    response_model=NotificationActionResponse,
    status_code=status.HTTP_200_OK,
    summary="Mark Single Notification as Read",
)
def mark_notification_read(
    notification_id: int,
):
    try:
        success = notification_service.mark_as_read(notification_id=notification_id)
        if not success:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Notification #{notification_id} not found",
            )
        return {
            "notification_id": notification_id,
            "is_read": True,
            "message": "Notification marked as read",
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update notification #{notification_id}: {str(e)}",
        )


@router.delete(
    "/{notification_id}",
    response_model=NotificationActionResponse,
    status_code=status.HTTP_200_OK,
    summary="Delete Notification",
)
def delete_notification(
    notification_id: int,
):
    try:
        success = notification_service.delete_notification(notification_id=notification_id)
        if not success:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Notification #{notification_id} not found",
            )
        return {
            "notification_id": notification_id,
            "message": f"Notification #{notification_id} deleted successfully",
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to delete notification #{notification_id}: {str(e)}",
        )
