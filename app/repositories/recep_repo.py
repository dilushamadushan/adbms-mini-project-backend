import json
from datetime import date, datetime, time
from decimal import Decimal
from typing import Any, Optional

from mysql.connector.connection import MySQLConnection

import hashlib
import random
import string


_ADMISSION_SELECT = """
    SELECT a.admission_id, a.patient_id,
           CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
           a.ward_id, w.ward_name, a.bed_id, b.bed_number, a.admitted_at,
           a.admitted_doctor_id,
           CONCAT('Dr. ', ds.first_name, ' ', ds.last_name) AS admitted_doctor_name,
           a.admission_reason, a.guardian_name, a.guardian_relationship,
           a.guardian_contact, a.gender,
           CASE
               WHEN dis.status = 'Discharged' THEN 'Discharged'
               WHEN dis.status = 'Authorized' THEN 'Discharge Authorized'
               ELSE a.status
           END AS status,
           dis.discharge_authorized_by,
           dis.discharge_authorized_at, dis.discharge_notes,
           NULL AS bill_id, NULL AS room_charges, NULL AS treatment_charges,
           NULL AS other_charges, NULL AS total_amount, NULL AS amount_paid,
           NULL AS payment_method, NULL AS payment_status
    FROM Admissions a
    JOIN Patients p ON p.patient_id = a.patient_id
    JOIN Wards w ON w.ward_id = a.ward_id
    LEFT JOIN Beds b ON b.bed_id = a.bed_id
    JOIN Staff ds ON ds.staff_id = a.admitted_doctor_id
    LEFT JOIN Discharges dis ON dis.admission_id = a.admission_id
"""

def get_patient_records(conn: MySQLConnection, search: Optional[str] = None) -> list[dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        if search and search.strip():
            cursor.callproc("sp_recep_search_patients_by_name", (search.strip(),))
            records: list[dict[str, Any]] = []
            for result in cursor.stored_results():
                records.extend(result.fetchall())
        else:
            cursor.execute("SELECT fn_recep_get_all_patients() AS patient_records")
            row = cursor.fetchone()
            patient_records = row["patient_records"]
            records = (
                json.loads(patient_records)
                if isinstance(patient_records, (str, bytes, bytearray))
                else patient_records
            )
            records.sort(key=lambda patient: (patient["last_name"], patient["first_name"]))
        return records
    finally:
        cursor.close()


def create_patient(
    conn: MySQLConnection,
    data: dict[str, Any],
) -> dict[str, Any]:
    username = f"{data['first_name'].lower()}.{data['last_name'].lower()}{random.randint(100, 999)}"
    raw_password = f"{data['first_name'].capitalize()}@{''.join(random.choices(string.ascii_letters + string.digits, k=4))}"
    password_hash = hashlib.sha256(raw_password.encode()).hexdigest()
    cursor = conn.cursor()
    try:
        cursor.execute(
            "INSERT INTO Users (username, email, password_hash, role) VALUES (%s, %s, %s, 'patient')",
            (username, data["email"], password_hash),
        )
        user_id = int(cursor.lastrowid)
        cursor.execute(
            """
            INSERT INTO Patients (user_id, first_name, last_name, dob, blood_group, emergency_contact, allergies)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            """,
            (
                user_id, data["first_name"], data["last_name"], data["dob"],
                data["blood_group"], data["emergency_contact"], data["allergies"],
            ),
        )
        patient_id = int(cursor.lastrowid)
        return {
            "patient_id": patient_id, "user_id": user_id, "username": username,
            "email": data["email"], "first_name": data["first_name"],
            "last_name": data["last_name"], "dob": data["dob"],
            "blood_group": data["blood_group"], "emergency_contact": data["emergency_contact"],
            "allergies": data["allergies"], "raw_password": raw_password,
        }
    finally:
        cursor.close()


def get_patient_id(conn: MySQLConnection, patient_id: int) -> Optional[int]:
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT patient_id FROM Patients WHERE patient_id = %s", (patient_id,))
        row = cursor.fetchone()
        return int(row[0]) if row else None
    finally:
        cursor.close()


def list_appointments(
    conn: MySQLConnection,
    appointment_id: Optional[int] = None,
    patient_id: Optional[int] = None,
    appointment_date: Optional[date] = None,
    patient_name: Optional[str] = None,
) -> list[dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc(
            "sp_recep_get_appointments",
            (
                appointment_id,
                patient_id,
                appointment_date,
                patient_name.strip() if patient_name and patient_name.strip() else None,
            ),
        )
        appointments: list[dict[str, Any]] = []
        for result in cursor.stored_results():
            appointments.extend(result.fetchall())
        return appointments
    finally:
        cursor.close()


def is_doctor_in_department(conn: MySQLConnection, doctor_id: int, dept_id: int) -> bool:
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            SELECT s.staff_id FROM Staff s JOIN Users u ON u.user_id = s.user_id
            WHERE s.staff_id = %s AND s.dept_id = %s
              AND LOWER(u.role) = 'doctor' AND u.is_active = TRUE
            """,
            (doctor_id, dept_id),
        )
        return cursor.fetchone() is not None
    finally:
        cursor.close()


def is_slot_available(
    conn: MySQLConnection,
    doctor_id: int,
    apt_date: date,
    time_slot: time,
    exclude_apt_id: Optional[int] = None,
) -> bool:
    query = """
        SELECT apt_id FROM Appointments
        WHERE doctor_id = %s AND apt_date = %s AND time_slot = %s AND status = 'Scheduled'
    """
    values: tuple[Any, ...] = (doctor_id, apt_date, time_slot)
    if exclude_apt_id is not None:
        query += " AND apt_id != %s"
        values += (exclude_apt_id,)
    query += " FOR UPDATE"
    cursor = conn.cursor()
    try:
        cursor.execute(query, values)
        return cursor.fetchone() is None
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


def update_appointment_schedule(
    conn: MySQLConnection, appointment_id: int, apt_date: date, time_slot: time
) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "UPDATE Appointments SET apt_date = %s, time_slot = %s WHERE apt_id = %s",
            (apt_date, time_slot, appointment_id),
        )
        return cursor.rowcount
    finally:
        cursor.close()


def update_appointment_status(conn: MySQLConnection, appointment_id: int, status: str) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute("UPDATE Appointments SET status = %s WHERE apt_id = %s", (status, appointment_id))
        return cursor.rowcount
    finally:
        cursor.close()

def get_overview(conn: MySQLConnection, today: date) -> dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT COUNT(*) AS total_patients FROM Patients")
        total_patients = cursor.fetchone()["total_patients"]
        cursor.execute(
            """
            SELECT COUNT(*) AS active_admissions
            FROM Admissions a
            LEFT JOIN Discharges dis ON dis.admission_id = a.admission_id
            WHERE dis.status IS NULL OR dis.status != 'Discharged'
            """
        )
        active_admissions = cursor.fetchone()["active_admissions"]
        cursor.execute(
            """
            SELECT a.apt_id, a.apt_date, TIME_FORMAT(a.time_slot, '%H:%i') AS time_slot,
                   a.status, CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
                   CONCAT('Dr. ', s.first_name, ' ', s.last_name) AS doctor_name,
                   d.dept_name
            FROM Appointments a
            JOIN Patients p ON p.patient_id = a.patient_id
            JOIN Staff s ON s.staff_id = a.doctor_id
            JOIN Departments d ON d.dept_id = a.dept_id
            WHERE a.apt_date = %s
            ORDER BY a.time_slot
            """,
            (today,),
        )
        appointments = cursor.fetchall()
        return {
            "total_patients": int(total_patients),
            "active_admissions": int(active_admissions),
            "appointments_today": len(appointments),
            "appointments": appointments,
        }
    finally:
        cursor.close()


def list_wards(conn: MySQLConnection) -> list[dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT ward_id, ward_name FROM Wards ORDER BY ward_name")
        return cursor.fetchall()
    finally:
        cursor.close()


def list_available_beds(
    conn: MySQLConnection, ward_id: Optional[int] = None
) -> list[dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        query = """
            SELECT b.bed_id, b.bed_number, w.ward_id, w.ward_name
            FROM Beds b
            JOIN Wards w ON w.ward_id = b.ward_id
            WHERE b.status = 'Available' AND b.current_patient_id IS NULL
        """
        values: tuple[Any, ...] = ()
        if ward_id is not None:
            query += " AND b.ward_id = %s"
            values = (ward_id,)
        query += " ORDER BY w.ward_name, b.bed_number"
        cursor.execute(
            query,
            values,
        )
        return cursor.fetchall()
    finally:
        cursor.close()


def get_patient_id(conn: MySQLConnection, patient_id: int) -> Optional[int]:
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT patient_id FROM Patients WHERE patient_id = %s", (patient_id,))
        row = cursor.fetchone()
        return int(row[0]) if row else None
    finally:
        cursor.close()


def lock_patient_for_admission(conn: MySQLConnection, patient_id: int) -> bool:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT patient_id FROM Patients WHERE patient_id = %s FOR UPDATE",
            (patient_id,),
        )
        return cursor.fetchone() is not None
    finally:
        cursor.close()


def has_open_admission(conn: MySQLConnection, patient_id: int) -> bool:
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            SELECT 1
            FROM Admissions a
            LEFT JOIN Discharges d ON d.admission_id = a.admission_id
            WHERE a.patient_id = %s
              AND (d.admission_id IS NULL OR d.status <> 'Discharged')
            LIMIT 1
            """,
            (patient_id,),
        )
        return cursor.fetchone() is not None
    finally:
        cursor.close()


def is_active_doctor(conn: MySQLConnection, doctor_id: int) -> bool:
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            SELECT s.staff_id
            FROM Staff s JOIN Users u ON u.user_id = s.user_id
            WHERE s.staff_id = %s AND LOWER(u.role) = 'doctor' AND u.is_active = TRUE
            """,
            (doctor_id,),
        )
        return cursor.fetchone() is not None
    finally:
        cursor.close()


def create_admission(
    conn: MySQLConnection,
    patient_id: int,
    ward_id: int,
    admitted_doctor_id: int,
    admitted_by: int,
    reason: str,
    guardian_name: str,
    guardian_relationship: str,
    guardian_contact: str,
    gender: str,
) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            INSERT INTO Admissions (
                patient_id, ward_id, admitted_doctor_id, admitted_by,
                admission_reason, guardian_name, guardian_relationship,
                guardian_contact, gender
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                patient_id, ward_id, admitted_doctor_id, admitted_by,
                reason, guardian_name, guardian_relationship, guardian_contact,
                gender,
            ),
        )
        return int(cursor.lastrowid)
    finally:
        cursor.close()


def assign_admission_bed(
    conn: MySQLConnection, admission_id: int, bed_id: int
) -> bool:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            "SELECT patient_id, ward_id, bed_id, status FROM Admissions WHERE admission_id = %s FOR UPDATE",
            (admission_id,),
        )
        admission = cursor.fetchone()
        if not admission or admission["status"] != "Pending" or admission["bed_id"] is not None:
            return False
        cursor.execute(
            """
            UPDATE Beds
            SET status = 'Occupied', current_patient_id = %s
            WHERE bed_id = %s AND ward_id = %s
              AND status = 'Available' AND current_patient_id IS NULL
            """,
            (admission["patient_id"], bed_id, admission["ward_id"]),
        )
        if cursor.rowcount != 1:
            return False
        cursor.execute(
            "UPDATE Admissions SET bed_id = %s, status = 'Admitted' WHERE admission_id = %s AND bed_id IS NULL AND status = 'Pending'",
            (bed_id, admission_id),
        )
        if cursor.rowcount != 1:
            raise RuntimeError("Admission bed assignment was not persisted")
        return True
    finally:
        cursor.close()


def list_admissions(conn: MySQLConnection, active_only: bool = False) -> list[dict[str, Any]]:
    query = _ADMISSION_SELECT
    if active_only:
        query += " WHERE dis.status IS NULL OR dis.status != 'Discharged'"
    query += " ORDER BY a.admitted_at DESC"
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(query)
        return cursor.fetchall()
    finally:
        cursor.close()


def get_admission(conn: MySQLConnection, admission_id: int, lock: bool = False) -> Optional[dict[str, Any]]:
    query = _ADMISSION_SELECT + " WHERE a.admission_id = %s"
    if lock:
        query += " FOR UPDATE"
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(query, (admission_id,))
        return cursor.fetchone()
    finally:
        cursor.close()


def get_doctor_staff_id(conn: MySQLConnection, user_id: int) -> Optional[int]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            SELECT s.staff_id
            FROM Staff s JOIN Users u ON u.user_id = s.user_id
            WHERE s.user_id = %s AND LOWER(u.role) = 'doctor' AND u.is_active = TRUE
            """,
            (user_id,),
        )
        row = cursor.fetchone()
        return int(row[0]) if row else None
    finally:
        cursor.close()


def authorize_discharge(
    conn: MySQLConnection, admission_id: int, authorized_staff_id: int, notes: str
) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            INSERT INTO Discharges (
                admission_id, discharge_authorized_by, discharge_notes
            )
            SELECT %s, %s, %s
            FROM Admissions a
            WHERE a.admission_id = %s
              AND a.status = 'Admitted'
              AND NOT EXISTS (
                  SELECT 1 FROM Discharges dis WHERE dis.admission_id = a.admission_id
              )
            """,
            (admission_id, authorized_staff_id, notes, admission_id),
        )
        return cursor.rowcount
    finally:
        cursor.close()


def save_discharge_bill(
    conn: MySQLConnection,
    admission_id: int,
    room_charges: Decimal,
    treatment_charges: Decimal,
    other_charges: Decimal,
    payment_amount: Decimal,
    payment_method: Optional[str],
) -> bool:
    cursor = conn.cursor()
    total = room_charges + treatment_charges + other_charges
    try:
        cursor.execute(
            "SELECT bill_id, total_amount, amount_paid FROM Bills WHERE admission_id = %s FOR UPDATE",
            (admission_id,),
        )
        existing = cursor.fetchone()
        if existing:
            bill_id, old_total, old_paid = existing
            new_paid = Decimal(old_paid) + payment_amount
            if new_paid > total:
                raise ValueError("Payment exceeds the calculated bill total")
            payment_status = "Paid" if new_paid == total else "Partially Paid" if new_paid > 0 else "Unpaid"
            cursor.execute(
                """
                UPDATE Bills
                SET room_charges = %s, treatment_charges = %s, other_charges = %s,
                    total_amount = %s, amount_paid = %s,
                    payment_method = COALESCE(%s, payment_method),
                    payment_status = %s,
                    paid_at = IF(%s = 'Paid', NOW(), paid_at)
                WHERE bill_id = %s
                """,
                (
                    room_charges, treatment_charges, other_charges, total, new_paid,
                    payment_method, payment_status, payment_status, bill_id,
                ),
            )
        else:
            if payment_amount > total:
                raise ValueError("Payment exceeds the calculated bill total")
            payment_status = "Paid" if payment_amount == total else "Partially Paid" if payment_amount > 0 else "Unpaid"
            cursor.execute(
                """
                INSERT INTO Bills (
                    admission_id, room_charges, treatment_charges, other_charges,
                    total_amount, amount_paid, payment_method, payment_status, paid_at
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, IF(%s = 'Paid', NOW(), NULL))
                """,
                (
                    admission_id, room_charges, treatment_charges, other_charges,
                    total, payment_amount, payment_method, payment_status, payment_status,
                ),
            )
        return payment_status == "Paid"
    finally:
        cursor.close()


def complete_discharge(conn: MySQLConnection, admission_id: int, user_id: int) -> int:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """
            SELECT a.bed_id, a.patient_id
            FROM Admissions a
            JOIN Bills bi ON bi.admission_id = a.admission_id
            JOIN Discharges dis ON dis.admission_id = a.admission_id
            WHERE a.admission_id = %s
              AND a.status = 'Admitted'
              AND dis.status = 'Authorized'
              AND bi.payment_status = 'Paid'
            FOR UPDATE
            """,
            (admission_id,),
        )
        admission = cursor.fetchone()
        if not admission:
            return 0
        cursor.execute(
            """
            UPDATE Discharges
            SET status = 'Discharged', discharged_by = %s, discharged_at = NOW()
            WHERE admission_id = %s AND status = 'Authorized'
            """,
            (user_id, admission_id),
        )
        cursor.execute(
            """
            UPDATE Beds
            SET status = 'Cleaning', current_patient_id = NULL
            WHERE bed_id = %s AND current_patient_id = %s
            """,
            (admission["bed_id"], admission["patient_id"]),
        )
        return cursor.rowcount
    finally:
        cursor.close()


def discharge_authorized_admission(
    conn: MySQLConnection, admission_id: int, user_id: int
) -> bool:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """
            SELECT a.bed_id, a.patient_id
            FROM Admissions a
            JOIN Discharges dis ON dis.admission_id = a.admission_id
            WHERE a.admission_id = %s
              AND a.status = 'Admitted'
              AND dis.status = 'Authorized'
            FOR UPDATE
            """,
            (admission_id,),
        )
        admission = cursor.fetchone()
        if not admission:
            return False

        cursor.execute(
            """
            UPDATE Discharges
            SET status = 'Discharged', discharged_by = %s, discharged_at = NOW()
            WHERE admission_id = %s AND status = 'Authorized'
            """,
            (user_id, admission_id),
        )
        if cursor.rowcount != 1:
            return False

        if admission["bed_id"] is not None:
            cursor.execute(
                """
                UPDATE Beds
                SET status = 'Cleaning', current_patient_id = NULL
                WHERE bed_id = %s AND current_patient_id = %s
                """,
                (admission["bed_id"], admission["patient_id"]),
            )
        return True
    finally:
        cursor.close()


def add_bill_payment(
    conn: MySQLConnection, admission_id: int, amount: Decimal, method: str
) -> bool:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT bill_id, total_amount, amount_paid FROM Bills WHERE admission_id = %s FOR UPDATE",
            (admission_id,),
        )
        bill = cursor.fetchone()
        if not bill:
            raise ValueError("No bill has been calculated for this admission")
        bill_id, total, paid = bill
        new_paid = Decimal(paid) + amount
        if new_paid > Decimal(total):
            raise ValueError("Payment exceeds the outstanding balance")
        status = "Paid" if new_paid == Decimal(total) else "Partially Paid"
        cursor.execute(
            """
            UPDATE Bills
            SET amount_paid = %s, payment_method = %s, payment_status = %s,
                paid_at = IF(%s = 'Paid', NOW(), paid_at)
            WHERE bill_id = %s
            """,
            (new_paid, method, status, status, bill_id),
        )
        return status == "Paid"
    finally:
        cursor.close()
