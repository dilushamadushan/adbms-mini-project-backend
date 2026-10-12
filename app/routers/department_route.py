from typing import List
from fastapi import APIRouter, HTTPException, status
from app.schema.department_schema import (
    DepartmentCreate,
    DepartmentUpdate,
    DepartmentResponse,
    DepartmentTreeResponse,
)
from app.services import department_service

router = APIRouter(prefix="/departments", tags=["Departments"])


@router.get("/catalog", response_model=List[DepartmentTreeResponse], status_code=status.HTTP_200_OK)
def get_department_catalog():
    """
    Get departments structured as a hierarchical catalog with nested sub-departments.
    """
    try:
        return department_service.get_department_catalog_tree()
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))


@router.get("", response_model=List[DepartmentResponse], status_code=status.HTTP_200_OK)
def get_all_departments():
    """
    Get all departments as a flat list.
    """
    try:
        return department_service.get_all_departments_flat()
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))


@router.get("/{dept_id}", response_model=DepartmentResponse, status_code=status.HTTP_200_OK)
def get_department(dept_id: int):
    """
    Get a single department by ID.
    """
    try:
        return department_service.get_department_by_id(dept_id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))


@router.post("", response_model=DepartmentResponse, status_code=status.HTTP_201_CREATED)
def create_department(payload: DepartmentCreate):
    """
    Add a new department or sub-department.
    """
    try:
        return department_service.create_department(payload)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))


@router.put("/{dept_id}", response_model=DepartmentResponse, status_code=status.HTTP_200_OK)
@router.patch("/{dept_id}", response_model=DepartmentResponse, status_code=status.HTTP_200_OK)
def update_department(dept_id: int, payload: DepartmentUpdate):
    """
    Update department name or parent department (reassign hierarchy).
    """
    try:
        return department_service.update_department(dept_id, payload)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))


@router.delete("/{dept_id}", status_code=status.HTTP_200_OK)
def delete_department(dept_id: int):
    """
    Remove a department. Cannot delete if sub-departments or staff are attached.
    """
    try:
        department_service.delete_department(dept_id)
        return {"message": "Department deleted successfully", "dept_id": dept_id}
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
