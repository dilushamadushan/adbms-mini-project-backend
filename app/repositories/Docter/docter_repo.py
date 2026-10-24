from mysql.connector.connection import MySQLConnection

#only run if id is the docter id
def get_appointments_by_doctor(conn: MySQLConnection, doctor_id: int) -> list:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("GetAppointmentsByDoctor", (doctor_id,))
        results = []
        for result in cursor.stored_results():
            results.extend(result.fetchall())
        return results
    finally:
        cursor.close()

#check the given id is docter id or not
def doctor_exists(conn: MySQLConnection, doctor_id: int) -> bool:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("CheckDoctorExists", (doctor_id,))
        for result in cursor.stored_results():
            row = result.fetchone()
            return row is not None and row["doctor_count"] > 0
        return False
    finally:
        cursor.close()


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
def get_completed_appointment_count(conn: MySQLConnection, doctor_id: int) -> int:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            "SELECT Get_Total_Appointment_Count_According_To_Doctor_complted(%s) AS completed_count",
            (doctor_id,),
        )
        row = cursor.fetchone()
        return int(row["completed_count"] or 0)
    finally:
        cursor.close()


# get the total number of patients by doctor id (scheduled and cancelled)
def get_total_patients_count(conn: MySQLConnection, doctor_id: int) -> int:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            "SELECT get_Total_Patients_count_by_docter(%s) AS patients_count",
            (doctor_id,),
        )
        row = cursor.fetchone()
        return int(row["patients_count"] or 0)
    finally:
        cursor.close()


# get appointment history of a doctor
def get_appointment_history_by_doctor(conn: MySQLConnection, doctor_id: int) -> list:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("GetAppointmentHistoryByDoctor", (doctor_id,))
        results = []
        for result in cursor.stored_results():
            results.extend(result.fetchall())
        return results
    finally:
        cursor.close()


# get upcoming appointments of a doctor
def get_upcoming_appointments_by_doctor(conn: MySQLConnection, doctor_id: int) -> list:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_get_upcoming_appointments_by_doctor", (doctor_id,))
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