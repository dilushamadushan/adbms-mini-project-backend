import logging
from typing import Dict, Any, List, Optional
from decimal import Decimal
import datetime
from mysql.connector.connection import MySQLConnection

logger = logging.getLogger(__name__)


def _serialize_row(row: Dict[str, Any]) -> Dict[str, Any]:
    
    cleaned = {}
    for k, v in row.items():
        if isinstance(v, (datetime.date, datetime.datetime)):
            cleaned[k] = str(v)
        elif isinstance(v, Decimal):
            cleaned[k] = float(v)
        elif isinstance(v, (bytes, bytearray)):
            cleaned[k] = v.decode("utf-8", errors="replace")
        elif isinstance(v, bool):
            cleaned[k] = v
        else:
            cleaned[k] = v
    return cleaned


def get_nurse_ward_beds(conn: MySQLConnection, nurse_user_id: int, ward_id: Optional[int] = None) -> Optional[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_get_nurse_ward_beds", (nurse_user_id, ward_id))
        stored_results = list(cursor.stored_results())
        if not stored_results:
            return None

        summary_rows = stored_results[0].fetchall()
        if not summary_rows:
            return None
        ward_data = _serialize_row(summary_rows[0])

        beds = []
        if len(stored_results) > 1:
            for row in stored_results[1].fetchall():
                beds.append(_serialize_row(row))

        assigned_wards = []
        if len(stored_results) > 2:
            for row in stored_results[2].fetchall():
                assigned_wards.append(_serialize_row(row))

        ward_data["beds"] = beds
        ward_data["assigned_wards"] = assigned_wards
        return ward_data
    finally:
        cursor.close()


def get_dashboard_stats(conn: MySQLConnection, nurse_user_id: int, ward_id: Optional[int] = None) -> Optional[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_get_nurse_dashboard_stats", (nurse_user_id, ward_id))
        for result in cursor.stored_results():
            row = result.fetchone()
            if row:
                return _serialize_row(row)
        return None
    finally:
        cursor.close()


def get_unassigned_admissions(conn: MySQLConnection, ward_id: Optional[int] = None) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_get_unassigned_admissions", (ward_id,))
        for result in cursor.stored_results():
            return [_serialize_row(r) for r in result.fetchall()]
        return []
    finally:
        cursor.close()


def assign_patient_to_bed(conn: MySQLConnection, admission_id: int, bed_id: int, nurse_user_id: int) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_nurse_assign_bed", (admission_id, bed_id, nurse_user_id))
        conn.commit()
        for result in cursor.stored_results():
            row = result.fetchone()
            if row:
                return _serialize_row(row)
        return {"status": "success"}
    finally:
        cursor.close()


def get_bed_details(conn: MySQLConnection, bed_id: int) -> Optional[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_get_bed_details", (bed_id,))
        stored_results = list(cursor.stored_results())
        if not stored_results:
            return None

        bed_rows = stored_results[0].fetchall()
        if not bed_rows:
            return None
        detail = _serialize_row(bed_rows[0])

        vitals_list = []
        if len(stored_results) > 1:
            for row in stored_results[1].fetchall():
                vitals_list.append(_serialize_row(row))

        detail["recent_vitals"] = vitals_list
        return detail
    finally:
        cursor.close()


def record_patient_vitals(
    conn: MySQLConnection,
    bed_id: int,
    nurse_user_id: int,
    bp: str,
    pulse: int,
    temperature: float,
    spo2: Optional[int] = None,
    resp_rate: Optional[int] = None,
    blood_sugar: Optional[float] = None,
    weight: Optional[float] = None,
) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        sugar_val = Decimal(str(blood_sugar)) if blood_sugar is not None else None
        weight_val = Decimal(str(weight)) if weight is not None else None
        cursor.callproc(
            "sp_record_patient_vitals",
            (
                bed_id,
                nurse_user_id,
                bp,
                pulse,
                Decimal(str(temperature)),
                spo2,
                resp_rate,
                sugar_val,
                weight_val,
            ),
        )
        for result in cursor.stored_results():
            row = result.fetchone()
            if row:
                return _serialize_row(row)
        raise RuntimeError("No vital log record returned from procedure.")
    finally:
        cursor.close()


def update_bed_status(
    conn: MySQLConnection, bed_id: int, new_status: str, nurse_user_id: int
) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_update_bed_status", (bed_id, new_status, nurse_user_id))
        for result in cursor.stored_results():
            row = result.fetchone()
            if row:
                return _serialize_row(row)
        return {"bed_id": bed_id, "status": new_status}
    finally:
        cursor.close()


def complete_patient_discharge(
    conn: MySQLConnection, admission_id: int, nurse_user_id: int
) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_complete_patient_discharge", (admission_id, nurse_user_id))
        for result in cursor.stored_results():
            row = result.fetchone()
            if row:
                return _serialize_row(row)
        raise RuntimeError("Discharge procedure did not return a response.")
    finally:
        cursor.close()


def get_ward_patients(conn: MySQLConnection, nurse_user_id: int) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        query = "SELECT * FROM vw_nurse_admitted_patients ORDER BY patient_name ASC"
        cursor.execute(query)
        rows = cursor.fetchall()
        return [_serialize_row(r) for r in rows]
    finally:
        cursor.close()


def get_patient_mar(conn: MySQLConnection, patient_id: int) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_get_patient_mar", (patient_id,))
        stored_results = list(cursor.stored_results())
        prescriptions = []
        history = []
        if len(stored_results) > 0:
            for r in stored_results[0].fetchall():
                row_dict = _serialize_row(r)
                row_dict["has_allergy_conflict"] = bool(row_dict.get("has_allergy_conflict", 0))
                prescriptions.append(row_dict)
        if len(stored_results) > 1:
            for r in stored_results[1].fetchall():
                history.append(_serialize_row(r))
        return {"prescriptions": prescriptions, "history": history}
    finally:
        cursor.close()


def administer_medication(
    conn: MySQLConnection,
    rx_id: int,
    patient_id: int,
    nurse_user_id: int,
    status: str,
    reason: Optional[str] = None,
    notes: Optional[str] = None,
) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc(
            "sp_administer_medication",
            (rx_id, patient_id, nurse_user_id, status, reason, notes),
        )
        for result in cursor.stored_results():
            row = result.fetchone()
            if row:
                return _serialize_row(row)
        raise RuntimeError("No administration log returned.")
    finally:
        cursor.close()


def get_doctor_orders(conn: MySQLConnection, patient_id: int) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_get_doctor_orders", (patient_id,))
        results = []
        for r in cursor.stored_results():
            for row in r.fetchall():
                results.append(_serialize_row(row))
        return results
    finally:
        cursor.close()


def acknowledge_doctor_order(
    conn: MySQLConnection, order_id: int, nurse_user_id: int, status: str
) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_acknowledge_doctor_order", (order_id, nurse_user_id, status))
        for r in cursor.stored_results():
            row = r.fetchone()
            if row:
                return _serialize_row(row)
        return {"order_id": order_id, "status": status}
    finally:
        cursor.close()


def get_nursing_notes(conn: MySQLConnection, patient_id: int) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_get_nursing_notes", (patient_id,))
        results = []
        for r in cursor.stored_results():
            for row in r.fetchall():
                results.append(_serialize_row(row))
        return results
    finally:
        cursor.close()


def add_nursing_note(
    conn: MySQLConnection,
    patient_id: int,
    nurse_user_id: int,
    note_type: str,
    subjective: Optional[str],
    objective: Optional[str],
    assessment: Optional[str],
    plan: Optional[str],
    content: str,
) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc(
            "sp_add_nursing_note",
            (patient_id, nurse_user_id, note_type, subjective, objective, assessment, plan, content),
        )
        for r in cursor.stored_results():
            row = r.fetchone()
            if row:
                return _serialize_row(row)
        raise RuntimeError("Failed to create nursing note.")
    finally:
        cursor.close()


def log_intake_output(
    conn: MySQLConnection,
    patient_id: int,
    nurse_user_id: int,
    io_type: str,
    category: str,
    volume_ml: int,
    notes: Optional[str] = None,
) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc(
            "sp_log_intake_output",
            (patient_id, nurse_user_id, io_type, category, volume_ml, notes),
        )
        for r in cursor.stored_results():
            row = r.fetchone()
            if row:
                return _serialize_row(row)
        raise RuntimeError("Failed to record intake/output.")
    finally:
        cursor.close()


def get_patient_io_summary(
    conn: MySQLConnection, patient_id: int, target_date: Optional[str] = None
) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        date_param = target_date if target_date else None
        cursor.callproc("sp_get_patient_io_summary", (patient_id, date_param))
        stored_results = list(cursor.stored_results())
        summary = {"summary_date": str(datetime.date.today()), "total_intake_ml": 0, "total_output_ml": 0, "net_balance_ml": 0, "entries": []}
        if len(stored_results) > 0:
            totals_row = stored_results[0].fetchone()
            if totals_row:
                summary.update(_serialize_row(totals_row))
        if len(stored_results) > 1:
            entries = []
            for r in stored_results[1].fetchall():
                entries.append(_serialize_row(r))
            summary["entries"] = entries
        return summary
    finally:
        cursor.close()


def get_current_shift_handover(conn: MySQLConnection, nurse_user_id: int) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_get_current_shift_handover", (nurse_user_id,))
        results = []
        for r in cursor.stored_results():
            for row in r.fetchall():
                results.append(_serialize_row(row))
        return results
    finally:
        cursor.close()


def create_shift_handover(
    conn: MySQLConnection, nurse_user_id: int, shift_type: str, summary_notes: str
) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_create_shift_handover", (nurse_user_id, shift_type, summary_notes))
        for r in cursor.stored_results():
            row = r.fetchone()
            if row:
                return _serialize_row(row)
        raise RuntimeError("Failed to create shift handover.")
    finally:
        cursor.close()


def accept_shift_handover(conn: MySQLConnection, handover_id: int, nurse_user_id: int) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_accept_shift_handover", (handover_id, nurse_user_id))
        for r in cursor.stored_results():
            row = r.fetchone()
            if row:
                return _serialize_row(row)
        return {"handover_id": handover_id, "status": "Accepted"}
    finally:
        cursor.close()


def get_ward_inventory_requests(conn: MySQLConnection, nurse_user_id: int) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_get_ward_inventory_requests", (nurse_user_id,))
        results = []
        for r in cursor.stored_results():
            for row in r.fetchall():
                results.append(_serialize_row(row))
        return results
    finally:
        cursor.close()


def request_ward_stock(
    conn: MySQLConnection, nurse_user_id: int, medicine_id: Optional[int], item_name: str, quantity: int
) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_request_ward_stock", (nurse_user_id, medicine_id, item_name, quantity))
        for r in cursor.stored_results():
            row = r.fetchone()
            if row:
                return _serialize_row(row)
        raise RuntimeError("Failed to create stock request.")
    finally:
        cursor.close()
