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