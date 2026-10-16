from datetime import date, time
from typing import Any, Optional

from mysql.connector.connection import MySQLConnection


_APPOINTMENT_SELECT = """
    SELECT
        a.apt_id,
        a.patient_id,
        p.user_id AS patient_user_id,
        CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
        a.doctor_id,
        CONCAT('Dr. ', s.first_name, ' ', s.last_name) AS doctor_name,
        a.dept_id,
        d.dept_name,
        a.apt_date,
        TIME_FORMAT(a.time_slot, '%H:%i') AS time_slot,
        a.status,
        d.dept_name AS reason
    FROM Appointments a
    JOIN Patients p ON p.patient_id = a.patient_id
    JOIN Staff s ON s.staff_id = a.doctor_id
    JOIN Departments d ON d.dept_id = a.dept_id
"""


def get_patient_by_user_id(conn: MySQLConnection, user_id: int) -> Optional[dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """
            SELECT patient_id, first_name, last_name
            FROM Patients
            WHERE user_id = %s
            """,
            (user_id,),
        )
        return cursor.fetchone()
    finally:
        cursor.close()


def get_doctor_for_department(
    conn: MySQLConnection, doctor_id: int, dept_id: int
) -> Optional[dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """
            SELECT s.staff_id, s.dept_id
            FROM Staff s
            JOIN Users u ON u.user_id = s.user_id
            WHERE s.staff_id = %s
              AND s.dept_id = %s
              AND LOWER(u.role) = 'doctor'
              AND u.is_active = TRUE
            FOR UPDATE
            """,
            (doctor_id, dept_id),
        )
        return cursor.fetchone()
    finally:
        cursor.close()


def is_time_slot_available(
    conn: MySQLConnection,
    doctor_id: int,
    apt_date: date,
    time_slot: time,
    exclude_apt_id: Optional[int] = None,
) -> bool:
    exclusion = " AND apt_id != %s" if exclude_apt_id is not None else ""
    values: tuple[Any, ...] = (doctor_id, apt_date, time_slot)
    if exclude_apt_id is not None:
        values += (exclude_apt_id,)
    cursor = conn.cursor()
    try:
        cursor.execute(
            f"""
            SELECT apt_id
            FROM Appointments
            WHERE doctor_id = %s
              AND apt_date = %s
              AND time_slot = %s
              AND status = 'Scheduled'
              {exclusion}
            FOR UPDATE
            """,
            values,
        )
        return cursor.fetchone() is None
    finally:
        cursor.close()


def get_active_doctor(conn: MySQLConnection, doctor_id: int) -> Optional[dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """
            SELECT s.staff_id
            FROM Staff s
            JOIN Users u ON u.user_id = s.user_id
            WHERE s.staff_id = %s
              AND LOWER(u.role) = 'doctor'
              AND u.is_active = TRUE
            """,
            (doctor_id,),
        )
        return cursor.fetchone()
    finally:
        cursor.close()


def list_booked_slots(
    conn: MySQLConnection, doctor_id: int, apt_date: date
) -> list[str]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            SELECT TIME_FORMAT(time_slot, '%H:%i')
            FROM Appointments
            WHERE doctor_id = %s
              AND apt_date = %s
              AND status = 'Scheduled'
            """,
            (doctor_id, apt_date),
        )
        return [row[0] for row in cursor.fetchall()]
    finally:
        cursor.close()


def create_appointment(
    conn: MySQLConnection,
    patient_id: int,
    doctor_id: int,
    dept_id: int,
    apt_date: date,
    time_slot: time,
) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            INSERT INTO Appointments (patient_id, doctor_id, dept_id, apt_date, time_slot, status)
            VALUES (%s, %s, %s, %s, %s, 'Scheduled')
            """,
            (patient_id, doctor_id, dept_id, apt_date, time_slot),
        )
        return int(cursor.lastrowid)
    finally:
        cursor.close()


def list_appointments(
    conn: MySQLConnection,
    patient_user_id: Optional[int] = None,
    doctor_id: Optional[int] = None,
    apt_date: Optional[date] = None,
    apt_id: Optional[int] = None,
) -> list[dict[str, Any]]:
    conditions = []
    values: list[Any] = []
    if patient_user_id is not None:
        conditions.append("p.user_id = %s")
        values.append(patient_user_id)
    if doctor_id is not None:
        conditions.append("a.doctor_id = %s")
        values.append(doctor_id)
    if apt_date is not None:
        conditions.append("a.apt_date = %s")
        values.append(apt_date)
    if apt_id is not None:
        conditions.append("a.apt_id = %s")
        values.append(apt_id)

    query = _APPOINTMENT_SELECT
    if conditions:
        query += " WHERE " + " AND ".join(conditions)
    query += " ORDER BY a.apt_date, a.time_slot"

    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(query, tuple(values))
        return cursor.fetchall()
    finally:
        cursor.close()


def get_staff_id_by_user_id(conn: MySQLConnection, user_id: int) -> Optional[int]:
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT staff_id FROM Staff WHERE user_id = %s", (user_id,))
        row = cursor.fetchone()
        return int(row[0]) if row else None
    finally:
        cursor.close()


def update_appointment_status(conn: MySQLConnection, apt_id: int, status: str) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "UPDATE Appointments SET status = %s WHERE apt_id = %s",
            (status, apt_id),
        )
        return cursor.rowcount
    finally:
        cursor.close()


def update_appointment_schedule(
    conn: MySQLConnection, apt_id: int, apt_date: date, time_slot: time
) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            UPDATE Appointments
            SET apt_date = %s, time_slot = %s
            WHERE apt_id = %s
            """,
            (apt_date, time_slot, apt_id),
        )
        return cursor.rowcount
    finally:
        cursor.close()
