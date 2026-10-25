from datetime import datetime
from typing import List, Optional, Dict, Any
from mysql.connector.connection import MySQLConnection

def _to_am_pm(val: str) -> str:
    """Format slot string to 12-hour AM/PM format (e.g. '09:00 AM', '01:30 PM')."""
    if not val:
        return ""
    val = str(val).strip()
    if "AM" in val or "PM" in val:
        return val
    try:
        parts = val.split(":")
        h = int(parts[0])
        m = int(parts[1])
        return datetime(2000, 1, 1, h, m).strftime("%I:%M %p")
    except Exception:
        return val

def get_doctor_departments_view(conn: MySQLConnection) -> list:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT * FROM vw_doctor_departments")
        return cursor.fetchall()
    finally:
        cursor.close()

def get_available_slots_proc(
    conn: MySQLConnection,
    doctor_name: str,
    department_name: str,
    apt_date: str
) -> List[str]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_get_available_slots", (doctor_name, department_name, apt_date))
        slots: List[str] = []
        for result in cursor.stored_results():
            rows = result.fetchall()
            slots.extend([_to_am_pm(row["available_slot"]) for row in rows if "available_slot" in row])
        return slots
    finally:
        cursor.close()

def get_patient_id_by_user_id(conn: MySQLConnection, user_id: int):
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT patient_id FROM Patients WHERE user_id = %s LIMIT 1", (user_id,))
        row = cursor.fetchone()
        return row["patient_id"] if row else None
    finally:
        cursor.close()

def book_appointment_proc(
    conn: MySQLConnection,
    patient_id: int,
    doctor_id: int,
    dept_id: int,
    apt_date: str,
    time_slot: str,
) -> dict:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc(
            "sp_book_appointment",
            (patient_id, doctor_id, dept_id, apt_date, time_slot),
        )
        appointment = None
        for result in cursor.stored_results():
            appointment = result.fetchone()
            if appointment:
                break
        conn.commit()

        if appointment:
            # Ensure date and time slot are plain strings for JSON serialization
            if "apt_date" in appointment and appointment["apt_date"] is not None:
                appointment["apt_date"] = str(appointment["apt_date"])
            if "time_slot" in appointment and appointment["time_slot"] is not None:
                appointment["time_slot"] = str(appointment["time_slot"])

        return appointment or {}
    finally:
        cursor.close()


def update_patient_profile(
    conn: MySQLConnection,
    user_id: int,
    patient_data: dict,
    user_data: dict,
) -> None:
    """Update patient personal details and user account email.
    Explicitly strips out medical details like blood_group and allergies so they cannot be updated.
    """
    # Strict safeguard: Never allow self-service changes to medical fields
    patient_data.pop("blood_group", None)
    patient_data.pop("allergies", None)

    cursor = conn.cursor()
    try:
        if patient_data:
            fields = [f"{k} = %s" for k in patient_data.keys()]
            values = list(patient_data.values()) + [user_id]
            cursor.execute(
                f"UPDATE Patients SET {', '.join(fields)} WHERE user_id = %s",
                tuple(values),
            )

        if user_data:
            fields = [f"{k} = %s" for k in user_data.keys()]
            values = list(user_data.values()) + [user_id]
            cursor.execute(
                f"UPDATE Users SET {', '.join(fields)} WHERE user_id = %s",
                tuple(values),
            )

        conn.commit()
    finally:
        cursor.close()


def get_patient_prescriptions(
    conn: MySQLConnection,
    patient_id: int,
    status_filter: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """Retrieve only prescriptions for a patient without medical record fields.
    Supports matching either by patient_id or user_id.
    """
    cursor = conn.cursor(dictionary=True)
    try:
        query = """
            SELECT 
                rx.rx_id,
                rx.record_id,
                rx.med_name,
                rx.dosage,
                rx.duration,
                rx.status,
                rx.created_at,
                rx.updated_at
            FROM Prescriptions rx
            JOIN Medical_Records mr ON rx.record_id = mr.record_id
            JOIN Patients p ON mr.patient_id = p.patient_id
            WHERE (mr.patient_id = %s OR p.user_id = %s)
        """
        params: list = [patient_id, patient_id]

        if status_filter:
            query += " AND LOWER(rx.status) = LOWER(%s)"
            params.append(status_filter.strip())

        query += " ORDER BY rx.created_at DESC, rx.rx_id DESC"

        cursor.execute(query, tuple(params))
        rows = cursor.fetchall()
        for r in rows:
            if r.get("created_at") is not None:
                r["created_at"] = str(r["created_at"])
            if r.get("updated_at") is not None:
                r["updated_at"] = str(r["updated_at"])
        return rows
    finally:
        cursor.close()


def get_patient_medical_records(
    conn: MySQLConnection,
    patient_id: int,
) -> List[Dict[str, Any]]:
    """Retrieve all medical records for a patient joining Medical_Records, Staff, Appointments, and Patients.
    Supports matching either by patient_id or user_id.
    """
    cursor = conn.cursor(dictionary=True)
    try:
        query = """
            SELECT 
                mr.record_id,
                mr.patient_id,
                CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
                mr.doctor_id,
                CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS doctor_name,
                doc.specialty AS doctor_specialty,
                mr.apt_id,
                a.apt_date,
                mr.diagnosis,
                mr.clinical_notes,
                mr.created_at,
                mr.updated_at
            FROM Medical_Records mr
            JOIN Patients p ON mr.patient_id = p.patient_id
            LEFT JOIN Staff doc ON mr.doctor_id = doc.staff_id
            LEFT JOIN Appointments a ON mr.apt_id = a.apt_id
            WHERE (mr.patient_id = %s OR p.user_id = %s)
            ORDER BY mr.created_at DESC, mr.record_id DESC
        """
        cursor.execute(query, (patient_id, patient_id))
        rows = cursor.fetchall()

        if rows:
            record_ids = [r["record_id"] for r in rows if "record_id" in r]
            rx_by_record: Dict[int, List[Dict[str, Any]]] = {}

            if record_ids:
                format_strings = ",".join(["%s"] * len(record_ids))
                rx_query = f"""
                    SELECT 
                        rx.rx_id,
                        rx.record_id,
                        rx.med_name,
                        rx.dosage,
                        rx.duration,
                        rx.status,
                        rx.created_at,
                        rx.updated_at
                    FROM Prescriptions rx
                    WHERE rx.record_id IN ({format_strings})
                    ORDER BY rx.rx_id ASC
                """
                cursor.execute(rx_query, tuple(record_ids))
                rx_rows = cursor.fetchall()

                for rx in rx_rows:
                    if rx.get("created_at") is not None:
                        rx["created_at"] = str(rx["created_at"])
                    if rx.get("updated_at") is not None:
                        rx["updated_at"] = str(rx["updated_at"])
                    rec_id = rx["record_id"]
                    rx_by_record.setdefault(rec_id, []).append(rx)

            for r in rows:
                if r.get("created_at") is not None:
                    r["created_at"] = str(r["created_at"])
                if r.get("updated_at") is not None:
                    r["updated_at"] = str(r["updated_at"])
                if r.get("apt_date") is not None:
                    r["apt_date"] = str(r["apt_date"])
                rec_id = r["record_id"]
                r["prescriptions"] = rx_by_record.get(rec_id, [])

        return rows
    finally:
        cursor.close()






