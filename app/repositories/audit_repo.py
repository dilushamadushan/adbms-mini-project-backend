import json
import logging
from typing import Dict, Any, List, Optional, Tuple
from mysql.connector.connection import MySQLConnection

logger = logging.getLogger(__name__)


def _parse_details(details_val: Any) -> Dict[str, Any]:
    if isinstance(details_val, dict):
        return details_val
    if isinstance(details_val, str):
        try:
            return json.loads(details_val)
        except Exception:
            return {"raw": details_val}
    return {}


def get_audit_logs(
    conn: MySQLConnection,
    page: int = 1,
    limit: int = 10,
    actor: Optional[str] = None,
    action: Optional[str] = None,
    risk: Optional[str] = None,
    date: Optional[str] = None,
) -> Tuple[List[Dict[str, Any]], int]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc(
            "sp_get_audit_logs",
            [
                page,
                limit,
                actor if actor else None,
                action if action else None,
                risk if risk else None,
                date if date else None,
            ],
        )

        rows = []
        for result in cursor.stored_results():
            rows = result.fetchall()
            break

        total = 0
        cleaned_items = []
        for r in rows:
            if "total_count" in r and r["total_count"] is not None:
                total = int(r["total_count"])
            cleaned_items.append({
                "log_id": r["log_id"],
                "timestamp": str(r["timestamp"]),
                "actor": r["actor"] or "System",
                "action": r["action"] or "",
                "resource": r["resource"] or "System",
                "risk": r["risk"] or "LOW",
                "details": _parse_details(r.get("details")),
            })

        return cleaned_items, total

    except Exception as sp_err:
        logger.warning("Stored procedure sp_get_audit_logs failed, falling back to view: %s", sp_err)
        return _get_audit_logs_fallback_view(conn, page, limit, actor, action, risk, date)
    finally:
        cursor.close()


def _get_audit_logs_fallback_view(
    conn: MySQLConnection,
    page: int = 1,
    limit: int = 10,
    actor: Optional[str] = None,
    action: Optional[str] = None,
    risk: Optional[str] = None,
    date: Optional[str] = None,
) -> Tuple[List[Dict[str, Any]], int]:
    cursor = conn.cursor(dictionary=True)
    try:
        offset = (page - 1) * limit
        where_clauses = []
        params = []

        if actor and actor.strip():
            where_clauses.append("actor LIKE %s")
            params.append(f"%{actor.strip()}%")
        if action and action.strip():
            where_clauses.append("action LIKE %s")
            params.append(f"%{action.strip()}%")
        if risk and risk.strip():
            where_clauses.append("UPPER(risk) = UPPER(%s)")
            params.append(risk.strip())
        if date and date.strip():
            where_clauses.append("DATE(raw_timestamp) = DATE(%s)")
            params.append(date.strip())

        where_sql = ("WHERE " + " AND ".join(where_clauses)) if where_clauses else ""

        sql = f"""
            SELECT 
                log_id,
                timestamp,
                actor,
                action,
                resource,
                risk,
                details,
                COUNT(*) OVER() AS total_count
            FROM vw_audit_logs_enriched
            {where_sql}
            ORDER BY raw_timestamp DESC, log_id DESC
            LIMIT %s OFFSET %s
        """
        params.extend([limit, offset])
        cursor.execute(sql, tuple(params))
        rows = cursor.fetchall()

        total = 0
        cleaned_items = []
        for r in rows:
            if "total_count" in r and r["total_count"] is not None:
                total = int(r["total_count"])
            cleaned_items.append({
                "log_id": r["log_id"],
                "timestamp": str(r["timestamp"]),
                "actor": r["actor"] or "System",
                "action": r["action"] or "",
                "resource": r["resource"] or "System",
                "risk": r["risk"] or "LOW",
                "details": _parse_details(r.get("details")),
            })

        if not rows and offset > 0:
            count_sql = f"SELECT COUNT(*) AS cnt FROM vw_audit_logs_enriched {where_sql}"
            cursor.execute(count_sql, tuple(params[:-2]))
            cnt_row = cursor.fetchone()
            if cnt_row:
                total = int(cnt_row["cnt"])

        return cleaned_items, total
    finally:
        cursor.close()


def get_audit_log_by_id(conn: MySQLConnection, log_id: int) -> Optional[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        sql = """
            SELECT 
                log_id,
                timestamp,
                actor,
                actor_id,
                action,
                resource,
                risk,
                details
            FROM vw_audit_logs_enriched
            WHERE log_id = %s
            LIMIT 1
        """
        cursor.execute(sql, (log_id,))
        row = cursor.fetchone()
        if not row:
            return None

        return {
            "log_id": row["log_id"],
            "timestamp": str(row["timestamp"]),
            "actor": row["actor"] or "System",
            "actor_id": row["actor_id"],
            "action": row["action"] or "",
            "resource": row["resource"] or "System",
            "risk": row["risk"] or "LOW",
            "details": _parse_details(row.get("details")),
        }
    finally:
        cursor.close()


def get_all_audit_logs_for_export(
    conn: MySQLConnection,
    actor: Optional[str] = None,
    action: Optional[str] = None,
    risk: Optional[str] = None,
    date: Optional[str] = None,
    max_records: int = 5000,
) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        where_clauses = []
        params = []

        if actor and actor.strip():
            where_clauses.append("actor LIKE %s")
            params.append(f"%{actor.strip()}%")
        if action and action.strip():
            where_clauses.append("action LIKE %s")
            params.append(f"%{action.strip()}%")
        if risk and risk.strip():
            where_clauses.append("UPPER(risk) = UPPER(%s)")
            params.append(risk.strip())
        if date and date.strip():
            where_clauses.append("DATE(raw_timestamp) = DATE(%s)")
            params.append(date.strip())

        where_sql = ("WHERE " + " AND ".join(where_clauses)) if where_clauses else ""

        sql = f"""
            SELECT 
                log_id,
                timestamp,
                actor,
                action,
                resource,
                risk,
                details
            FROM vw_audit_logs_enriched
            {where_sql}
            ORDER BY raw_timestamp DESC, log_id DESC
            LIMIT %s
        """
        params.append(max_records)
        cursor.execute(sql, tuple(params))
        rows = cursor.fetchall()

        cleaned_items = []
        for r in rows:
            cleaned_items.append({
                "log_id": r["log_id"],
                "timestamp": str(r["timestamp"]),
                "actor": r["actor"] or "System",
                "action": r["action"] or "",
                "resource": r["resource"] or "System",
                "risk": r["risk"] or "LOW",
                "details": _parse_details(r.get("details")),
            })
        return cleaned_items
    finally:
        cursor.close()
