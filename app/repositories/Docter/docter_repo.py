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