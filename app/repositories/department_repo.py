from typing import Optional, List, Dict, Any
from mysql.connector.connection import MySQLConnection


def create_department(conn: MySQLConnection, dept_name: str, parent_dept_id: Optional[int]) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "INSERT INTO Departments (dept_name, parent_dept_id) VALUES (%s, %s)",
            (dept_name, parent_dept_id),
        )
        return cursor.lastrowid
    finally:
        cursor.close()


def get_department_by_id(conn: MySQLConnection, dept_id: int) -> Optional[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            "SELECT dept_id, dept_name, parent_dept_id, created_at, updated_at FROM Departments WHERE dept_id = %s",
            (dept_id,),
        )
        return cursor.fetchone()
    finally:
        cursor.close()


def get_all_departments(conn: MySQLConnection) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            "SELECT dept_id, dept_name, parent_dept_id, created_at, updated_at FROM Departments ORDER BY parent_dept_id ASC, dept_name ASC"
        )
        return cursor.fetchall()
    finally:
        cursor.close()


def update_department(conn: MySQLConnection, dept_id: int, updates: Dict[str, Any]) -> int:
    if not updates:
        return 0

    fields = []
    values = []
    for key, val in updates.items():
        fields.append(f"{key} = %s")
        values.append(val)

    values.append(dept_id)
    query = f"UPDATE Departments SET {', '.join(fields)} WHERE dept_id = %s"

    cursor = conn.cursor()
    try:
        cursor.execute(query, tuple(values))
        return cursor.rowcount
    finally:
        cursor.close()


def count_sub_departments(conn: MySQLConnection, dept_id: int) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT COUNT(*) FROM Departments WHERE parent_dept_id = %s", (dept_id,))
        row = cursor.fetchone()
        return row[0] if row else 0
    finally:
        cursor.close()


def count_staff_in_department(conn: MySQLConnection, dept_id: int) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT COUNT(*) FROM Staff WHERE dept_id = %s", (dept_id,))
        row = cursor.fetchone()
        return row[0] if row else 0
    finally:
        cursor.close()


def delete_department(conn: MySQLConnection, dept_id: int) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute("DELETE FROM Departments WHERE dept_id = %s", (dept_id,))
        return cursor.rowcount
    finally:
        cursor.close()


def get_department_hierarchy_cte(conn: MySQLConnection) -> List[Dict[str, Any]]:
    """
    Executes stored procedure sp_get_department_hierarchy using Recursive CTE.
    """
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_get_department_hierarchy")
        results = []
        for result in cursor.stored_results():
            results = result.fetchall()
        return results
    finally:
        cursor.close()


def delete_department_sp(conn: MySQLConnection, dept_id: int) -> None:
    """
    Executes transactional stored procedure sp_delete_department with integrity SIGNAL checks.
    """
    cursor = conn.cursor()
    try:
        cursor.callproc("sp_delete_department", (dept_id,))
    finally:
        cursor.close()

