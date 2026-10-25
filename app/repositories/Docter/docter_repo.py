import json
from mysql.connector.connection import MySQLConnection

def get_doctor_medicine_list(conn: MySQLConnection) -> list[dict]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """
            SELECT medicine_id, med_name, generic_name
            FROM vw_doctor_medicine_list
            ORDER BY med_name
            """
        )
        return cursor.fetchall()
    finally:
        cursor.close()


def get_lab_order_patient_details(conn: MySQLConnection) -> list[dict]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """
            SELECT v.patient_id, v.patient_name, v.age, v.blood_group, v.allergies,
                   (
                       SELECT ad.gender
                       FROM admissions ad
                       WHERE ad.patient_id = v.patient_id
                       ORDER BY ad.admitted_at DESC
                       LIMIT 1
                   ) AS gender,
                   v.appointment_id, v.appointment_date, v.appointment_status
            FROM vw_lab_order_patient_details v
            ORDER BY v.appointment_date DESC, v.appointment_id DESC
            """
        )
        return cursor.fetchall()
    finally:
        cursor.close()


def create_lab_order(
    conn: MySQLConnection,
    patient_id: int,
    doctor_user_id: int,
    test_type: str,
) -> dict:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """
            SELECT s.staff_id
            FROM Staff s
            INNER JOIN Users u ON u.user_id = s.user_id
            WHERE s.user_id = %s
              AND LOWER(u.role) = 'doctor'
              AND u.is_active = TRUE
            LIMIT 1
            """,
            (doctor_user_id,),
        )
        doctor = cursor.fetchone()
        if not doctor:
            raise ValueError("Active doctor not found")

        cursor.callproc(
            "sp_create_lab_order",
            (patient_id, int(doctor["staff_id"]), test_type),
        )
        for result in cursor.stored_results():
            row = result.fetchone()
            if row:
                return row
        raise ValueError("Lab-order procedure did not return the saved order")
    finally:
        cursor.close()


def get_patient_lab_results(conn: MySQLConnection, patient_id: int) -> list[dict]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_get_patient_lab_results", (patient_id,))
        for result in cursor.stored_results():
            return result.fetchall()
        return []
    finally:
        cursor.close()


def create_prescription(
    conn: MySQLConnection,
    patient_id: int,
    apt_id: int,
    doctor_id: int,
    diagnosis: str,
    clinical_notes: str | None,
    medicines: list[dict],
) -> int:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc(
            "sp_create_prescription",
            (
                patient_id,
                apt_id,
                doctor_id,
                diagnosis,
                clinical_notes,
                json.dumps(medicines),
            ),
        )
        for result in cursor.stored_results():
            row = result.fetchone()
            if row and row.get("record_id") is not None:
                return int(row["record_id"])
        raise ValueError("Prescription procedure did not return a record ID")
    finally:
        cursor.close()


def create_admitted_prescription(
    conn: MySQLConnection,
    patient_id: int,
    apt_id: int,
    doctor_id: int,
    diagnosis: str,
    clinical_notes: str | None,
    medicines: list[dict],
    nurse_orders: list[dict],
) -> int:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc(
            "sp_create_admitted_prescription",
            (
                patient_id,
                apt_id,
                doctor_id,
                diagnosis,
                clinical_notes,
                json.dumps(medicines),
                json.dumps(nurse_orders),
            ),
        )
        for result in cursor.stored_results():
            row = result.fetchone()
            if row and row.get("record_id") is not None:
                return int(row["record_id"])
        raise ValueError("Admitted prescription procedure did not return a record ID")
    finally:
        cursor.close()

def _get_staff_id_for_user(conn: MySQLConnection, user_id: int) -> int | None:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """
            SELECT s.staff_id
            FROM Users u
            INNER JOIN Staff s ON s.user_id = u.user_id
            WHERE u.user_id = %s
              AND LOWER(u.role) = 'doctor'
              AND u.is_active = TRUE
            LIMIT 1
            """,
            (user_id,),
        )
        row = cursor.fetchone()
        return int(row["staff_id"]) if row else None
    finally:
        cursor.close()


def get_appointments_by_doctor(conn: MySQLConnection, user_id: int) -> list:
    cursor = conn.cursor(dictionary=True)
    try:
        staff_id = _get_staff_id_for_user(conn, user_id)
        if staff_id is None:
            return []
        cursor.callproc("GetAppointmentsByDoctor", (staff_id,))
        results = []
        for result in cursor.stored_results():
            results.extend(result.fetchall())
        return results
    finally:
        cursor.close()


def get_doctor_current_schedule(
    conn: MySQLConnection,
    doctor_id: int,
) -> list[dict]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_get_doctor_current_schedule", (doctor_id,))
        rows: list[dict] = []
        for result in cursor.stored_results():
            rows = result.fetchall()
            break

        cursor.execute(
            """
            SELECT
                a.apt_id,
                DATE_FORMAT(a.apt_date, '%Y-%m-%d') AS appointment_date,
                TIME_FORMAT(a.time_slot, '%h:%i %p') AS appointment_time
            FROM Appointments a
            WHERE a.doctor_id = %s
              AND a.apt_date = CURRENT_DATE
              AND a.status = 'Scheduled'
            """,
            (doctor_id,),
        )
        appointment_ids = {
            (row["appointment_date"], row["appointment_time"]): row["apt_id"]
            for row in cursor.fetchall()
        }

        for row in rows:
            key = (str(row["appointment_date"]), row["appointment_time"])
            appointment_id = appointment_ids.get(key)
            if row.get("patient_name") or appointment_id is not None:
                row["slot_status"] = "BOOKED"
                row["apt_id"] = appointment_id
            else:
                row["slot_status"] = "OPEN"
                row["apt_id"] = None
        return rows
    finally:
        cursor.close()


def get_doctor_current_schedule_by_user(
    conn: MySQLConnection,
    user_id: int,
) -> list[dict]:
    staff_id = _get_staff_id_for_user(conn, user_id)
    if staff_id is None:
        raise ValueError("Doctor not found")
    return get_doctor_current_schedule(conn, staff_id)


def staff_doctor_exists(conn: MySQLConnection, doctor_id: int) -> bool:
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            SELECT 1
            FROM Staff
            WHERE staff_id = %s
            LIMIT 1
            """,
            (doctor_id,),
        )
        return cursor.fetchone() is not None
    finally:
        cursor.close()


def doctor_exists(conn: MySQLConnection, user_id: int) -> bool:
    return _get_staff_id_for_user(conn, user_id) is not None


 #get the total number of appointment according to the doctor id

def get_appointment_count(conn: MySQLConnection, doctor_id: int) -> int:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            "SELECT Get_Total_Appointment_Count_According_To_Doctor(%s) AS appointment_count",
            (doctor_id,),
        )
        row = cursor.fetchone()
        return int(row["appointment_count"] or 0)
    finally:
        cursor.close()


# get the total number of completed appointments for today according to the doctor id
def get_completed_appointment_count(conn: MySQLConnection, user_id: int) -> int:
    cursor = conn.cursor(dictionary=True)
    try:
        staff_id = _get_staff_id_for_user(conn, user_id)
        if staff_id is None:
            return 0
        cursor.execute(
            "SELECT Get_Total_Appointment_Count_According_To_Doctor_complted(%s) AS completed_count",
            (staff_id,),
        )
        row = cursor.fetchone()
        return int(row["completed_count"] or 0)
    finally:
        cursor.close()


# get the total number of patients by doctor id (scheduled and cancelled)
def get_total_patients_count(conn: MySQLConnection, user_id: int) -> int:
    cursor = conn.cursor(dictionary=True)
    try:
        staff_id = _get_staff_id_for_user(conn, user_id)
        if staff_id is None:
            return 0
        cursor.execute(
            "SELECT get_Total_Patients_count_by_docter(%s) AS patients_count",
            (staff_id,),
        )
        row = cursor.fetchone()
        return int(row["patients_count"] or 0)
    finally:
        cursor.close()


# get appointment history of a doctor
def get_appointment_history_by_doctor(conn: MySQLConnection, user_id: int) -> list:
    cursor = conn.cursor(dictionary=True)
    try:
        staff_id = _get_staff_id_for_user(conn, user_id)
        if staff_id is None:
            return []
        cursor.callproc("GetAppointmentHistoryByDoctor", (staff_id,))
        results = []
        for result in cursor.stored_results():
            results.extend(result.fetchall())
        return results
    finally:
        cursor.close()


# get upcoming appointments of a doctor
def get_upcoming_appointments_by_doctor(conn: MySQLConnection, user_id: int) -> list:
    cursor = conn.cursor(dictionary=True)
    try:
        staff_id = _get_staff_id_for_user(conn, user_id)
        if staff_id is None:
            return []
        cursor.callproc("sp_get_upcoming_appointments_by_doctor", (staff_id,))
        results = []
        for result in cursor.stored_results():
            for row in result.fetchall():
                if "time_slot" in row and row["time_slot"] is not None:
                    row["time_slot"] = str(row["time_slot"])
                if "apt_date" in row and row["apt_date"] is not None:
                    row["apt_date"] = str(row["apt_date"])
                if "patient_name" in row and isinstance(row["patient_name"], (bytes, bytearray)):
                    row["patient_name"] = row["patient_name"].decode("utf-8", errors="replace")
                if "reason" in row and isinstance(row["reason"], (bytes, bytearray)):
                    row["reason"] = row["reason"].decode("utf-8", errors="replace")
                results.append(row)
        return results
    finally:
        cursor.close()


# check the given user id belongs to a doctor/staff
def doctor_user_exists(conn: MySQLConnection, user_id: int) -> bool:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT COUNT(*) AS doctor_count FROM staff WHERE user_id = %s", (user_id,))
        row = cursor.fetchone()
        return row is not None and row["doctor_count"] > 0
    finally:
        cursor.close()

# get appointments for a doctor by user_id grouped by Today, Upcoming, Past
def get_doctor_appointments_by_user(conn: MySQLConnection, user_id: int) -> list:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_doctor_appointments", (user_id,))
        results = []
        for result in cursor.stored_results():
            for row in result.fetchall():
                for key, value in row.items():
                    if isinstance(value, (bytes, bytearray)):
                        row[key] = value.decode("utf-8", errors="replace")
                    elif key in ("apt_date", "appointment_time") and value is not None:
                        row[key] = str(value)
                results.append(row)
        return results
    finally:
        cursor.close()


def get_patient_details(conn: MySQLConnection, patient_id: int) -> dict | None:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("GetPatientDetails", (patient_id,))
        for result in cursor.stored_results():
            return result.fetchone()
        return None
    finally:
        cursor.close()


def get_patient_appointment_details(
    conn: MySQLConnection, appointment_id: int
) -> dict | None:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("get_patient_appointment_details", (appointment_id,))
        for result in cursor.stored_results():
            return result.fetchone()
        return None
    finally:
        cursor.close()


def get_ward_names(conn: MySQLConnection) -> list[dict]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT ward_id, ward_name FROM wards ORDER BY ward_name")
        return cursor.fetchall()
    finally:
        cursor.close()


def create_admission_request(
    conn: MySQLConnection,
    patient_id: int,
    gender: str,
    ward_id: int,
    reason: str,
    doctor_id: int,
    user_id: int,
) -> int:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc(
            "sp_create_admission_request",
            (patient_id, gender, ward_id, reason, doctor_id, user_id),
        )
        for result in cursor.stored_results():
            row = result.fetchone()
            if row and row.get("admission_id") is not None:
                conn.commit()
                return int(row["admission_id"])
        raise ValueError("Admission procedure did not return an admission ID")
    finally:
        cursor.close()


def request_discharge(
    conn: MySQLConnection,
    admission_id: int,
    doctor_id: int,
    notes: str,
) -> None:
    cursor = conn.cursor()
    try:
        cursor.callproc("request_discharge", (admission_id, doctor_id, notes))
        conn.commit()
    finally:
        cursor.close()


def complete_appointment(
    conn: MySQLConnection,
    appointment_id: int,
    doctor_id: int,
) -> None:
    cursor = conn.cursor()
    try:
        cursor.callproc("complete_appointment", (appointment_id, doctor_id))
        conn.commit()
    finally:
        cursor.close()


def get_active_admission_by_patient(
    conn: MySQLConnection, patient_id: int
) -> dict | None:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """
            SELECT admission_id, patient_id, ward_id, bed_id, admitted_doctor_id,
                   admitted_by, admitted_at, admission_reason, guardian_name,
                   guardian_relationship, guardian_contact, gender, status
            FROM vw_admissions_data
            WHERE patient_id = %s
              AND status IN ('Pending', 'Admitted')
            ORDER BY admitted_at DESC
            LIMIT 1
            """,
            (patient_id,),
        )
        return cursor.fetchone()
    finally:
        cursor.close()