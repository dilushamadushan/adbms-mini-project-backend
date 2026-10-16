from typing import Optional, List, Dict, Any, Tuple
from mysql.connector.connection import MySQLConnection


def get_workload_report_from_sp(
    conn: MySQLConnection,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    top_n: int = 5,
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_generate_workload_report", (start_date, end_date, top_n))
        results = []
        for res in cursor.stored_results():
            results.append(res.fetchall())

        dept_results = results[0] if len(results) > 0 else []
        provider_results = results[1] if len(results) > 1 else []
        return dept_results, provider_results
    finally:
        cursor.close()


def get_department_workload_from_view(conn: MySQLConnection) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """
            SELECT 
                dept_id,
                dept_name,
                doctor_count,
                total_appointments,
                pts_seen,
                workload_percentage,
                dept_rank,
                workload_level
            FROM vw_department_workload
            ORDER BY total_appointments DESC, dept_name ASC;
            """
        )
        return cursor.fetchall()
    finally:
        cursor.close()


def get_top_providers_from_view(conn: MySQLConnection, limit: int = 5) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """
            SELECT 
                staff_id,
                provider_name,
                specialty,
                dept_name,
                pts_seen,
                avg_time_minutes,
                avg_time_formatted,
                workload_rank,
                share_percentage
            FROM vw_top_provider_workload
            WHERE pts_seen > 0
            ORDER BY workload_rank ASC, pts_seen DESC
            LIMIT %s;
            """,
            (limit,),
        )
        return cursor.fetchall()
    finally:
        cursor.close()


def get_workload_with_rollup(conn: MySQLConnection) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """
            SELECT 
                COALESCE(d.dept_name, '=== TOTAL HOSPITAL ===') AS dept_name,
                COALESCE(a.status, '--- SUB-TOTAL ---') AS status,
                COUNT(a.apt_id) AS appointment_count
            FROM Appointments a
            INNER JOIN Departments d ON a.dept_id = d.dept_id
            GROUP BY d.dept_name, a.status WITH ROLLUP;
            """
        )
        return cursor.fetchall()
    finally:
        cursor.close()


def get_hospital_workload_kpis(
    conn: MySQLConnection,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        query = """
            SELECT 
                COUNT(DISTINCT a.apt_id) AS total_appointments,
                COUNT(DISTINCT a.patient_id) AS total_pts_seen,
                COUNT(DISTINCT a.dept_id) AS total_active_depts
            FROM Appointments a
            WHERE 1=1
        """
        params = []
        if start_date:
            query += " AND a.apt_date >= %s"
            params.append(start_date)
        if end_date:
            query += " AND a.apt_date <= %s"
            params.append(end_date)

        cursor.execute(query, tuple(params))
        row = cursor.fetchone() or {}
        return {
            "total_appointments": int(row.get("total_appointments") or 0),
            "total_pts_seen": int(row.get("total_pts_seen") or 0),
            "total_active_depts": int(row.get("total_active_depts") or 0),
            "overall_avg_time": 18,
        }
    finally:
        cursor.close()



def get_hospital_kpi_overview(
    conn: MySQLConnection,
    target_date: Optional[str] = None,
) -> Dict[str, Any]:
   
    cursor = conn.cursor(dictionary=True)
    try:
        resolved_date = str(target_date).strip() if target_date and isinstance(target_date, str) else None

        cursor.callproc("sp_get_hospital_kpi_overview", (resolved_date,))
        row: Dict[str, Any] = {}
        for rs in cursor.stored_results():
            fetched = rs.fetchone()
            if fetched:
                row = fetched
                break

        if not row:
            cursor.execute("SELECT * FROM vw_hospital_kpi_detail LIMIT 1;")
            row = cursor.fetchone() or {}

        total_beds     = int(row.get("total_beds")     or 0)
        occupied_beds  = int(row.get("occupied_beds")  or 0)
        available_beds = int(row.get("available_beds") or 0)
        cleaning_beds  = int(row.get("cleaning_beds")  or 0)

        if total_beds == 0:
            cursor.execute("SELECT COALESCE(SUM(total_beds), 0) AS ward_total FROM Wards;")
            wr = cursor.fetchone() or {}
            total_beds     = int(wr.get("ward_total") or 0)
            available_beds = max(0, total_beds - occupied_beds)

        target_str = str(row.get("target_date") or row.get("kpi_date") or resolved_date or "today")

        return {
            "total_patients":    int(row.get("total_patients") or 0),
            "total_beds":        total_beds,
            "occupied_beds":     occupied_beds,
            "available_beds":    available_beds,
            "cleaning_beds":     cleaning_beds,
            "todays_appointments": int(row.get("todays_appointments") or 0),
            "scheduled_today":   int(row.get("scheduled_today") or row.get("scheduled_count") or 0),
            "completed_today":   int(row.get("completed_today") or row.get("completed_count") or 0),
            "cancelled_today":   int(row.get("cancelled_today") or row.get("cancelled_count") or 0),
            "no_show_today":     int(row.get("no_show_today")   or row.get("no_show_count")   or 0),
            "target_date":       target_str,
        }
    finally:
        cursor.close()


