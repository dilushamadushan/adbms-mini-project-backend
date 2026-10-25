from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, Field

class DepartmentBase(BaseModel):
    dept_name: str = Field(..., min_length=2, max_length=100, description="Department name")
    parent_dept_id: Optional[int] = Field(None, description="Parent department ID if this is a sub-department")

class DepartmentCreate(DepartmentBase):
    pass

class DepartmentUpdate(BaseModel):
    dept_name: Optional[str] = Field(None, min_length=2, max_length=100)
    parent_dept_id: Optional[int] = None

class DepartmentResponse(DepartmentBase):
    dept_id: int
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

class DepartmentTreeResponse(DepartmentBase):
    dept_id: int
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    sub_departments: List["DepartmentTreeResponse"] = []

DepartmentTreeResponse.model_rebuild()
