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