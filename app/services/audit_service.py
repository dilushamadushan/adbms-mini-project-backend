import csv
import io
import json
import math
from typing import Dict, Any, List, Optional
from app.core.database import get_db
from app.repositories import audit_repo


def list_audit_logs(
    page: int = 1,
    limit: int = 10,
    actor: Optional[str] = None,
    action: Optional[str] = None,
    risk: Optional[str] = None,
    date: Optional[str] = None,
) -> Dict[str, Any]:
    page = max(1, page)
    limit = max(1, min(100, limit))

    with get_db() as conn:
        items, total = audit_repo.get_audit_logs(
            conn=conn,
            page=page,
            limit=limit,
            actor=actor,
            action=action,
            risk=risk,
            date=date,
        )

    total_pages = math.ceil(total / limit) if total > 0 else 0

    return {
        "items": items,
        "logs": items,  
        "total": total,
        "page": page,
        "limit": limit,
        "total_pages": total_pages,
    }


def get_recent_audit_logs(limit: int = 4) -> List[Dict[str, Any]]:
    limit = max(1, min(50, limit))
    with get_db() as conn:
        items, _ = audit_repo.get_audit_logs(
            conn=conn,
            page=1,
            limit=limit,
        )
    return items


def get_audit_log_by_id(log_id: int) -> Optional[Dict[str, Any]]:
    with get_db() as conn:
        return audit_repo.get_audit_log_by_id(conn=conn, log_id=log_id)


def export_audit_logs_to_csv(
    actor: Optional[str] = None,
    action: Optional[str] = None,
    risk: Optional[str] = None,
    date: Optional[str] = None,
) -> str:
    with get_db() as conn:
        logs = audit_repo.get_all_audit_logs_for_export(
            conn=conn,
            actor=actor,
            action=action,
            risk=risk,
            date=date,
        )

    output = io.StringIO()
    writer = csv.writer(output)

    writer.writerow(["Log ID", "Timestamp", "Actor", "Action", "Resource", "Risk", "Details"])

    for item in logs:
        details_str = json.dumps(item.get("details", {}), ensure_ascii=False)
        writer.writerow([
            item.get("log_id"),
            item.get("timestamp"),
            item.get("actor"),
            item.get("action"),
            item.get("resource"),
            item.get("risk"),
            details_str,
        ])

    return output.getvalue()
