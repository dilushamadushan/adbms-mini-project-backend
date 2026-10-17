from datetime import datetime
from typing import List
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



