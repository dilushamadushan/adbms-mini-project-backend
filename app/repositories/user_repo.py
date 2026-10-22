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


def get_patient_profile_by_user_id(conn: MySQLConnection, user_id: int) -> dict | None:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """
            SELECT
                p.patient_id,
                u.user_id,
                u.username,
                u.email,
                p.first_name,
                p.last_name,
                p.dob,
                p.blood_group,
                p.emergency_contact,
                p.allergies
            FROM Patients p
            JOIN Users u ON u.user_id = p.user_id
            WHERE p.user_id = %s
              AND LOWER(u.role) = 'patient'
            """,
            (user_id,),
        )
        return cursor.fetchone()
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


def get_staff_by_id(conn: MySQLConnection, identifier: int) -> dict | None:
    cursor = conn.cursor(dictionary=True)
    try:
        # Check by staff_id first
        cursor.execute(
            """
            SELECT 
                s.staff_id,
                s.first_name,
                s.last_name,
                s.dept_id,
                s.specialty,
                u.user_id,
                u.username,
                u.email,
                u.role,
                u.is_active
            FROM Staff s
            INNER JOIN Users u ON s.user_id = u.user_id
            WHERE s.staff_id = %s
            LIMIT 1
            """,
            (identifier,),
        )
        row = cursor.fetchone()
        if row:
            return row

        # Fallback to check by user_id
        cursor.execute(
            """
            SELECT 
                s.staff_id,
                s.first_name,
                s.last_name,
                s.dept_id,
                s.specialty,
                u.user_id,
                u.username,
                u.email,
                u.role,
                u.is_active
            FROM Staff s
            INNER JOIN Users u ON s.user_id = u.user_id
            WHERE u.user_id = %s
            LIMIT 1
            """,
            (identifier,),
        )
        return cursor.fetchone()
    finally:
        cursor.close()


def check_email_exists_excluding_user(conn: MySQLConnection, email: str, exclude_user_id: int) -> bool:
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT user_id FROM Users WHERE email = %s AND user_id != %s LIMIT 1", (email, exclude_user_id))
        return cursor.fetchone() is not None
    finally:
        cursor.close()


def check_username_exists_excluding_user(conn: MySQLConnection, username: str, exclude_user_id: int) -> bool:
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT user_id FROM Users WHERE username = %s AND user_id != %s LIMIT 1", (username, exclude_user_id))
        return cursor.fetchone() is not None
    finally:
        cursor.close()


def check_department_exists(conn: MySQLConnection, dept_id: int) -> bool:
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT dept_id FROM Departments WHERE dept_id = %s LIMIT 1", (dept_id,))
        return cursor.fetchone() is not None
    finally:
        cursor.close()


def update_staff_user(conn: MySQLConnection, staff_id: int, user_id: int, staff_data: dict, user_data: dict) -> None:
    cursor = conn.cursor()
    try:
        if staff_data:
            fields = [f"{k} = %s" for k in staff_data.keys()]
            values = list(staff_data.values()) + [staff_id]
            cursor.execute(f"UPDATE Staff SET {', '.join(fields)} WHERE staff_id = %s", tuple(values))

        if user_data:
            fields = [f"{k} = %s" for k in user_data.keys()]
            values = list(user_data.values()) + [user_id]
            cursor.execute(f"UPDATE Users SET {', '.join(fields)} WHERE user_id = %s", tuple(values))

        conn.commit()
    finally:
        cursor.close()


def check_staff_dependencies(conn: MySQLConnection, staff_id: int, user_id: int) -> list[str]:
    cursor = conn.cursor(dictionary=True)
    dependencies = []
    try:
        checks = [
            ("Appointments", "SELECT COUNT(*) AS cnt FROM Appointments WHERE doctor_id = %s", (staff_id,), "appointment(s)"),
            ("Medical_Records", "SELECT COUNT(*) AS cnt FROM Medical_Records WHERE doctor_id = %s", (staff_id,), "medical record(s)"),
            ("Lab_Orders", "SELECT COUNT(*) AS cnt FROM Lab_Orders WHERE doctor_id = %s", (staff_id,), "lab order(s)"),
            ("Admissions", "SELECT COUNT(*) AS cnt FROM Admissions WHERE admitted_doctor_id = %s OR admitted_by = %s", (staff_id, user_id), "admission record(s)"),
            ("Discharges", "SELECT COUNT(*) AS cnt FROM Discharges WHERE discharge_authorized_by = %s OR discharged_by = %s", (staff_id, user_id), "discharge authorization(s)"),
            ("Wards", "SELECT COUNT(*) AS cnt FROM Wards WHERE nurse_in_charge_id = %s", (staff_id,), "assigned ward(s) as nurse-in-charge"),
            ("Stock_Receipts", "SELECT COUNT(*) AS cnt FROM Stock_Receipts WHERE received_by = %s", (staff_id,), "stock receipt(s)"),
            ("Dispensations", "SELECT COUNT(*) AS cnt FROM Dispensations WHERE pharmacist_id = %s", (staff_id,), "dispensation record(s)"),
        ]
        for _, query, params, label in checks:
            try:
                cursor.execute(query, params)
                row = cursor.fetchone()
                if row and row["cnt"] > 0:
                    dependencies.append(f"{row['cnt']} {label}")
            except Exception:
                pass
        return dependencies
    finally:
        cursor.close()


def delete_staff_user(conn: MySQLConnection, staff_id: int, user_id: int) -> None:
    cursor = conn.cursor()
    try:
        cursor.execute("DELETE FROM Staff WHERE staff_id = %s", (staff_id,))
        cursor.execute("DELETE FROM Users WHERE user_id = %s", (user_id,))
        conn.commit()
    finally:
        cursor.close()