import math
from typing import Dict, Any, Optional
from app.core.database import get_db
from app.repositories import notification_repo


def list_notifications(
    page: int = 1,
    limit: int = 10,
    is_read: Optional[bool] = None,
    notif_type: Optional[str] = None,
    target_role: Optional[str] = None,
    target_user_id: Optional[int] = None,
) -> Dict[str, Any]:
    """
    Returns paginated notifications and unread count.
    """
    page = max(1, page)
    limit = max(1, min(100, limit))

    with get_db() as conn:
        items, total, unread_count = notification_repo.get_notifications(
            conn=conn,
            page=page,
            limit=limit,
            is_read=is_read,
            notif_type=notif_type,
            target_role=target_role,
            target_user_id=target_user_id,
        )

    total_pages = math.ceil(total / limit) if total > 0 else 0

    return {
        "items": items,
        "notifications": items,
        "total": total,
        "unread_count": unread_count,
        "page": page,
        "limit": limit,
        "total_pages": total_pages,
    }


def get_unread_count(
    target_role: Optional[str] = None,
    target_user_id: Optional[int] = None,
) -> int:
    with get_db() as conn:
        return notification_repo.get_unread_count(
            conn=conn,
            target_role=target_role,
            target_user_id=target_user_id,
        )


def mark_as_read(notification_id: int) -> bool:
    with get_db() as conn:
        return notification_repo.mark_notification_read(
            conn=conn,
            notification_id=notification_id,
            is_read=True,
        )


def mark_all_as_read(
    target_role: Optional[str] = None,
    target_user_id: Optional[int] = None,
) -> int:
    with get_db() as conn:
        return notification_repo.mark_all_notifications_read(
            conn=conn,
            target_role=target_role,
            target_user_id=target_user_id,
        )


def delete_notification(notification_id: int) -> bool:
    with get_db() as conn:
        return notification_repo.delete_notification(
            conn=conn,
            notification_id=notification_id,
        )
