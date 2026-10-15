from typing import List, Dict, Any, Optional
from app.core.database import get_db
from app.repositories import department_repo
from app.schema.department_schema import DepartmentCreate, DepartmentUpdate, DepartmentResponse, DepartmentTreeResponse


def create_department(payload: DepartmentCreate) -> Dict[str, Any]:
    with get_db() as conn:
        if payload.parent_dept_id is not None:
            parent = department_repo.get_department_by_id(conn, payload.parent_dept_id)
            if not parent:
                raise ValueError(f"Parent department with ID {payload.parent_dept_id} does not exist")

        dept_id = department_repo.create_department(
            conn,
            dept_name=payload.dept_name.strip(),
            parent_dept_id=payload.parent_dept_id,
        )
        return department_repo.get_department_by_id(conn, dept_id)


def get_department_by_id(dept_id: int) -> Dict[str, Any]:
    with get_db() as conn:
        dept = department_repo.get_department_by_id(conn, dept_id)
        if not dept:
            raise ValueError(f"Department with ID {dept_id} not found")
        return dept


def get_all_departments_flat() -> List[Dict[str, Any]]:
    with get_db() as conn:
        return department_repo.get_all_departments(conn)


def get_department_catalog_tree() -> List[Dict[str, Any]]:
    with get_db() as conn:
        rows = department_repo.get_all_departments(conn)

    dept_map: Dict[int, Dict[str, Any]] = {}
    for r in rows:
        dept_map[r["dept_id"]] = {
            **r,
            "sub_departments": [],
        }

    tree: List[Dict[str, Any]] = []
    for r in rows:
        d_id = r["dept_id"]
        p_id = r["parent_dept_id"]
        if p_id and p_id in dept_map:
            dept_map[p_id]["sub_departments"].append(dept_map[d_id])
        else:
            tree.append(dept_map[d_id])

    return tree


def update_department(dept_id: int, payload: DepartmentUpdate) -> Dict[str, Any]:
    with get_db() as conn:
        existing = department_repo.get_department_by_id(conn, dept_id)
        if not existing:
            raise ValueError(f"Department with ID {dept_id} not found")

        updates: Dict[str, Any] = {}
        if payload.dept_name is not None:
            updates["dept_name"] = payload.dept_name.strip()

        if payload.parent_dept_id is not None:
            if payload.parent_dept_id == dept_id:
                raise ValueError("A department cannot be its own parent")
            parent = department_repo.get_department_by_id(conn, payload.parent_dept_id)
            if not parent:
                raise ValueError(f"Parent department with ID {payload.parent_dept_id} does not exist")
            updates["parent_dept_id"] = payload.parent_dept_id

        if updates:
            department_repo.update_department(conn, dept_id, updates)

        return department_repo.get_department_by_id(conn, dept_id)


def delete_department(dept_id: int) -> bool:
    import mysql.connector
    with get_db() as conn:
        try:
            department_repo.delete_department_sp(conn, dept_id)
            return True
        except mysql.connector.Error as err:
            raise ValueError(err.msg)
        except Exception:
            existing = department_repo.get_department_by_id(conn, dept_id)
            if not existing:
                raise ValueError(f"Department with ID {dept_id} not found")
            sub_count = department_repo.count_sub_departments(conn, dept_id)
            if sub_count > 0:
                raise ValueError(f"Cannot delete department: {sub_count} sub-department(s) depend on it")
            staff_count = department_repo.count_staff_in_department(conn, dept_id)
            if staff_count > 0:
                raise ValueError(f"Cannot delete department: {staff_count} staff member(s) are assigned to it")
            department_repo.delete_department(conn, dept_id)
            return True

