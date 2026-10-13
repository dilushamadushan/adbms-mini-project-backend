import json
import logging
from typing import Dict, Any, List, Optional, Tuple
from mysql.connector.connection import MySQLConnection

logger = logging.getLogger(__name__)


def _parse_details(details_val: Any) -> Optional[Dict[str, Any]]:
    if details_val is None:
        return None
    if isinstance(details_val, dict):
        return details_val
    if isinstance(details_val, str):
        try:
            return json.loads(details_val)
        except Exception:
            return {"raw": details_val}
    return None


def get_notifications(
    conn: MySQLConnection,
    page: int = 1,
    limit: int = 10,
    is_read: Optional[bool] = None,
    notif_type: Optional[str] = None,
    target_role: Optional[str] = None,
    target_user_id: Optional[int] = None,
) -> Tuple[List[Dict[str, Any]], int, int]:
    cursor = conn.cursor(dictionary=True)
    try:
        offset = (page - 1) * limit
        where_clauses = []
        params = []

        if is_read is not None:
            where_clauses.append("is_read = %s")
            params.append(1 if is_read else 0)

        if notif_type and notif_type.strip():
            where_clauses.append("type = %s")
            params.append(notif_type.strip())

        if target_role and target_user_id:
            where_clauses.append("(target_role = %s OR target_role = 'all' OR target_user_id = %s)")
            params.extend([target_role, target_user_id])
        elif target_role:
            where_clauses.append("(target_role = %s OR target_role = 'all' OR target_role IS NULL)")
            params.append(target_role)
        elif target_user_id:
            where_clauses.append("(target_user_id = %s OR target_role = 'all')")
            params.append(target_user_id)

        where_sql = ("WHERE " + " AND ".join(where_clauses)) if where_clauses else ""

        sql = f"""
            SELECT 
                notification_id,
                title,
                message,
                type,
                target_role,
                target_user_id,
                is_read,
                details,
                created_at,
                COUNT(*) OVER() AS total_count
            FROM Notifications
            {where_sql}
            ORDER BY created_at DESC, notification_id DESC
            LIMIT %s OFFSET %s
        """
        query_params = list(params)
        query_params.extend([limit, offset])
        cursor.execute(sql, tuple(query_params))
        rows = cursor.fetchall()

        total = 0
        items = []
        for r in rows:
            if "total_count" in r and r["total_count"] is not None:
                total = int(r["total_count"])
            items.append({
                "notification_id": r["notification_id"],
                "title": r["title"],
                "message": r["message"],
                "type": r["type"],
                "target_role": r["target_role"],
                "target_user_id": r["target_user_id"],
                "is_read": bool(r["is_read"]),
                "details": _parse_details(r.get("details")),
                "created_at": str(r["created_at"])[:19],
            })

        unread_where_clauses = ["is_read = FALSE"]
        unread_params = []
        if target_role and target_user_id:
            unread_where_clauses.append("(target_role = %s OR target_role = 'all' OR target_user_id = %s)")
            unread_params.extend([target_role, target_user_id])
        elif target_role:
            unread_where_clauses.append("(target_role = %s OR target_role = 'all' OR target_role IS NULL)")
            unread_params.append(target_role)
        elif target_user_id:
            unread_where_clauses.append("(target_user_id = %s OR target_role = 'all')")
            unread_params.append(target_user_id)

        unread_sql = f"SELECT COUNT(*) AS unread_cnt FROM Notifications WHERE {' AND '.join(unread_where_clauses)}"
        cursor.execute(unread_sql, tuple(unread_params))
        unread_row = cursor.fetchone()
        unread_count = int(unread_row["unread_cnt"]) if unread_row else 0

        if not rows and offset > 0:
            count_sql = f"SELECT COUNT(*) AS cnt FROM Notifications {where_sql}"
            cursor.execute(count_sql, tuple(params))
            cnt_row = cursor.fetchone()
            if cnt_row:
                total = int(cnt_row["cnt"])

        return items, total, unread_count
    finally:
        cursor.close()


def get_unread_count(
    conn: MySQLConnection,
    target_role: Optional[str] = None,
    target_user_id: Optional[int] = None,
) -> int:
    cursor = conn.cursor(dictionary=True)
    try:
        where_clauses = ["is_read = FALSE"]
        params = []
        if target_role and target_user_id:
            where_clauses.append("(target_role = %s OR target_role = 'all' OR target_user_id = %s)")
            params.extend([target_role, target_user_id])
        elif target_role:
            where_clauses.append("(target_role = %s OR target_role = 'all' OR target_role IS NULL)")
            params.append(target_role)
        elif target_user_id:
            where_clauses.append("(target_user_id = %s OR target_role = 'all')")
            params.append(target_user_id)

        sql = f"SELECT COUNT(*) AS unread_cnt FROM Notifications WHERE {' AND '.join(where_clauses)}"
        cursor.execute(sql, tuple(params))
        row = cursor.fetchone()
        return int(row["unread_cnt"]) if row else 0
    finally:
        cursor.close()


def mark_notification_read(
    conn: MySQLConnection,
    notification_id: int,
    is_read: bool = True,
) -> bool:
    cursor = conn.cursor()
    try:
        sql = "UPDATE Notifications SET is_read = %s WHERE notification_id = %s"
        cursor.execute(sql, (1 if is_read else 0, notification_id))
        conn.commit()
        return cursor.rowcount > 0
    finally:
        cursor.close()


def mark_all_notifications_read(
    conn: MySQLConnection,
    target_role: Optional[str] = None,
    target_user_id: Optional[int] = None,
) -> int:
    cursor = conn.cursor()
    try:
        where_clauses = ["is_read = FALSE"]
        params = []
        if target_role and target_user_id:
            where_clauses.append("(target_role = %s OR target_role = 'all' OR target_user_id = %s)")
            params.extend([target_role, target_user_id])
        elif target_role:
            where_clauses.append("(target_role = %s OR target_role = 'all' OR target_role IS NULL)")
            params.append(target_role)
        elif target_user_id:
            where_clauses.append("(target_user_id = %s OR target_role = 'all')")
            params.append(target_user_id)

        sql = f"UPDATE Notifications SET is_read = TRUE WHERE {' AND '.join(where_clauses)}"
        cursor.execute(sql, tuple(params))
        conn.commit()
        return cursor.rowcount
    finally:
        cursor.close()


def delete_notification(
    conn: MySQLConnection,
    notification_id: int,
) -> bool:
    cursor = conn.cursor()
    try:
        sql = "DELETE FROM Notifications WHERE notification_id = %s"
        cursor.execute(sql, (notification_id,))
        conn.commit()
        return cursor.rowcount > 0
    finally:
        cursor.close()
