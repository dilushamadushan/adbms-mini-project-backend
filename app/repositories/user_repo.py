from mysql.connector.connection import MySQLConnection

def create_staff_user(conn: MySQLConnection, user_data: dict, staff_data: dict) -> dict:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            "INSERT INTO Users (username, email, password_hash, role) VALUES (%s, %s, %s, %s)",
            (user_data["username"], user_data.get("email"), user_data["password_hash"], user_data["role"])
        )
        user_id = cursor.lastrowid
 
        cursor.execute(
            "INSERT INTO Staff (user_id, dept_id, first_name, last_name, specialty) VALUES (%s, %s, %s, %s, %s)",
            (user_id, staff_data["dept_id"], staff_data["first_name"], staff_data["last_name"], staff_data["specialty"])
        )
        staff_id = cursor.lastrowid
        
        return {"user_id": user_id, "staff_id": staff_id}
    finally:
        cursor.close()

def create_patient_user(conn: MySQLConnection, user_data: dict, patient_data: dict) -> dict:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            "INSERT INTO Users (username, email, password_hash, role) VALUES (%s, %s, %s, %s)",
            (user_data["username"], user_data.get("email"), user_data["password_hash"], user_data["role"])
        )
        user_id = cursor.lastrowid

        cursor.execute(
            "INSERT INTO Patients (user_id, first_name, last_name, dob, blood_group, emergency_contact, allergies) VALUES (%s, %s, %s, %s, %s, %s, %s)",
            (user_id, patient_data["first_name"], patient_data["last_name"], patient_data["dob"], patient_data["blood_group"], patient_data["emergency_contact"], patient_data["allergies"])
        )
        patient_id = cursor.lastrowid
        
        return {"user_id": user_id, "patient_id": patient_id}
    finally:
        cursor.close()

def update_is_active(conn: MySQLConnection, user_id: int, is_active: bool) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "UPDATE Users SET is_active = %s WHERE user_id = %s",
            (is_active, user_id)
        )
        conn.commit()
        return cursor.rowcount
    finally:
        cursor.close()

def get_user_by_username(conn: MySQLConnection, username: str) -> dict:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            "SELECT * FROM Users WHERE username = %s",
            (username,)
        )
        return cursor.fetchone()
    finally:
        cursor.close()

def get_all_patients(conn: MySQLConnection) -> list:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("GetAllPatients")
        results = []
        for result in cursor.stored_results():
            results.extend(result.fetchall())
        return results
    finally:
        cursor.close()

def get_all_staff(conn: MySQLConnection) -> list:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("GetAllStaff")
        results = []
        for result in cursor.stored_results():
            results.extend(result.fetchall())
        return results
    finally:
        cursor.close()