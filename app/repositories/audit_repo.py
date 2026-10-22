import json
import logging
from typing import Dict, Any, List, Optional, Tuple
from mysql.connector.connection import MySQLConnection
import mysql.connector

logger = logging.getLogger(__name__)

_VIEW_CREATED = False

AUDIT_LOGS_SOURCE = """(
    SELECT
        a.log_id,
        DATE_FORMAT(a.timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp,
        a.timestamp AS raw_timestamp,
        a.actor_id,
        COALESCE(
            CASE 
                WHEN s.first_name IS NOT NULL AND u.role = 'doctor' THEN CONCAT('Dr. ', s.first_name, ' ', s.last_name)
                WHEN s.first_name IS NOT NULL THEN CONCAT(s.first_name, ' ', s.last_name)
                ELSE NULL
            END,
            u.username,
            NULLIF(JSON_UNQUOTE(JSON_EXTRACT(a.details, '$.actor')), 'null'),
            NULLIF(JSON_UNQUOTE(JSON_EXTRACT(a.details, '$.username')), 'null'),
            'System'
        ) AS actor,
        a.action_type AS action,
        COALESCE(a.resource_table, 'System') AS resource,
        CASE
            WHEN JSON_UNQUOTE(JSON_EXTRACT(a.details, '$.risk')) IS NOT NULL 
                 AND UPPER(JSON_UNQUOTE(JSON_EXTRACT(a.details, '$.risk'))) IN ('HIGH', 'MEDIUM', 'LOW')
                THEN UPPER(JSON_UNQUOTE(JSON_EXTRACT(a.details, '$.risk')))
            WHEN UPPER(COALESCE(a.action_type, '')) LIKE '%DELETE%' 
                 OR UPPER(COALESCE(a.action_type, '')) LIKE '%DROP%' 
                 OR UPPER(COALESCE(a.action_type, '')) LIKE '%REVOKE%'
                 OR UPPER(COALESCE(a.action_type, '')) LIKE '%PURGE%'
                 OR UPPER(COALESCE(a.action_type, '')) LIKE '%UNAUTHORIZED%'
                 OR UPPER(COALESCE(a.action_type, '')) LIKE '%BREACH%'
                 OR UPPER(COALESCE(a.action_type, '')) LIKE '%FAIL%'
                THEN 'HIGH'
            WHEN UPPER(COALESCE(a.action_type, '')) LIKE '%UPDATE%' 
                 OR UPPER(COALESCE(a.action_type, '')) LIKE '%MODIFY%' 
                 OR UPPER(COALESCE(a.action_type, '')) LIKE '%PASSWORD%'
                 OR UPPER(COALESCE(a.action_type, '')) LIKE '%ROLE%'
                 OR UPPER(COALESCE(a.action_type, '')) LIKE '%STATUS%'
                 OR UPPER(COALESCE(a.action_type, '')) LIKE '%USER%'
                 OR UPPER(COALESCE(a.action_type, '')) LIKE '%DIAGNOSIS%'
                 OR UPPER(COALESCE(a.action_type, '')) LIKE '%PRESCRIPTION%'
                 OR UPPER(COALESCE(a.action_type, '')) LIKE '%CREATE%'
                THEN 'MEDIUM'
            ELSE 'LOW'
        END AS risk,
        a.details
    FROM Audit_Logs a
    LEFT JOIN Users u ON a.actor_id = u.user_id
    LEFT JOIN Staff s ON u.user_id = s.user_id
)"""


def _ensure_audit_view(conn: MySQLConnection) -> None:
    global _VIEW_CREATED
    if _VIEW_CREATED:
        return
    cursor = conn.cursor()
    try:
        cursor.execute(f"CREATE OR REPLACE VIEW vw_audit_logs_enriched AS SELECT * FROM {AUDIT_LOGS_SOURCE} AS _src")
        conn.commit()
        _VIEW_CREATED = True
        logger.info("Successfully ensured view vw_audit_logs_enriched exists in database.")
    except Exception as e:
        logger.warning("Could not auto-create vw_audit_logs_enriched (inline query will be used): %s", e)
    finally:
        cursor.close()


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
    # Ensure view exists for stored procedure to work smoothly
    _ensure_audit_view(conn)

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
        logger.warning("sp_get_audit_logs failed, falling back to direct table query: %s", sp_err)
        return _get_audit_logs_fallback_query(conn, page, limit, actor, action, risk, date)
    finally:
        cursor.close()


def _get_audit_logs_fallback_query(
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

        # Check if view is usable; otherwise query AUDIT_LOGS_SOURCE inline
        table_source = "vw_audit_logs_enriched" if _VIEW_CREATED else f"{AUDIT_LOGS_SOURCE} AS v"

        try:
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
                FROM {table_source}
                {where_sql}
                ORDER BY raw_timestamp DESC, log_id DESC
                LIMIT %s OFFSET %s
            """
            exec_params = list(params) + [limit, offset]
            cursor.execute(sql, tuple(exec_params))
            rows = cursor.fetchall()
        except mysql.connector.Error:
            # If view failed with table missing, unconditionally use the inline source
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
                FROM {AUDIT_LOGS_SOURCE} AS v
                {where_sql}
                ORDER BY raw_timestamp DESC, log_id DESC
                LIMIT %s OFFSET %s
            """
            exec_params = list(params) + [limit, offset]
            cursor.execute(sql, tuple(exec_params))
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
            count_sql = f"SELECT COUNT(*) AS cnt FROM {AUDIT_LOGS_SOURCE} AS v {where_sql}"
            cursor.execute(count_sql, tuple(params))
            cnt_row = cursor.fetchone()
            if cnt_row:
                total = int(cnt_row["cnt"])

        return cleaned_items, total
    finally:
        cursor.close()


def get_audit_log_by_id(conn: MySQLConnection, log_id: int) -> Optional[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        table_source = "vw_audit_logs_enriched" if _VIEW_CREATED else f"{AUDIT_LOGS_SOURCE} AS v"
        try:
            sql = f"""
                SELECT 
                    log_id,
                    timestamp,
                    actor,
                    actor_id,
                    action,
                    resource,
                    risk,
                    details
                FROM {table_source}
                WHERE log_id = %s
                LIMIT 1
            """
            cursor.execute(sql, (log_id,))
            row = cursor.fetchone()
        except mysql.connector.Error:
            sql = f"""
                SELECT 
                    log_id,
                    timestamp,
                    actor,
                    actor_id,
                    action,
                    resource,
                    risk,
                    details
                FROM {AUDIT_LOGS_SOURCE} AS v
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
            "actor_id": row.get("actor_id"),
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

        table_source = "vw_audit_logs_enriched" if _VIEW_CREATED else f"{AUDIT_LOGS_SOURCE} AS v"
        try:
            sql = f"""
                SELECT 
                    log_id,
                    timestamp,
                    actor,
                    action,
                    resource,
                    risk,
                    details
                FROM {table_source}
                {where_sql}
                ORDER BY raw_timestamp DESC, log_id DESC
                LIMIT %s
            """
            cursor.execute(sql, tuple(params + [max_records]))
            rows = cursor.fetchall()
        except mysql.connector.Error:
            sql = f"""
                SELECT 
                    log_id,
                    timestamp,
                    actor,
                    action,
                    resource,
                    risk,
                    details
                FROM {AUDIT_LOGS_SOURCE} AS v
                {where_sql}
                ORDER BY raw_timestamp DESC, log_id DESC
                LIMIT %s
            """
            cursor.execute(sql, tuple(params + [max_records]))
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
