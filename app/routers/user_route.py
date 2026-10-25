from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, status
import mysql.connector

from app.core.security import get_current_user_payload
from app.schema.user_schema import (
    StaffUserCreate,
    StaffUserResponse,
    StaffUserUpdate,
    StaffDeleteResponse,
    PatientUserCreate,
    PatientUserResponse,
    PatientProfileResponse,
    UserStatusUpdate,
)
from app.services.user_service import (
    create_new_staff_user,
    create_new_patient_user,
    update_user_status,
    GetAllPatients,
    GetAllStaff,
    get_patient_profile,
    get_staff_member,
    update_staff_member,
    delete_staff_member,
)

router = APIRouter(prefix="/users", tags=["Users"])
staff_router = APIRouter(prefix="/staff", tags=["Staff"])


# -------------------------------------------------------------
# Staff Endpoints under /users/staff
# -------------------------------------------------------------

@router.post("/staff", response_model=StaffUserResponse, status_code=status.HTTP_201_CREATED)
def add_staff_member(payload: StaffUserCreate, background_tasks: BackgroundTasks):
    try:
        return create_new_staff_user(payload, background_tasks=background_tasks)
    except mysql.connector.IntegrityError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Username or email already exists")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/staff", response_model=list[StaffUserResponse], status_code=status.HTTP_200_OK)
def get_all_staff():
    try:
        return GetAllStaff()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/staff/{staff_id}", response_model=StaffUserResponse, status_code=status.HTTP_200_OK)
def get_staff_by_id_endpoint(staff_id: int):
    try:
        return get_staff_member(staff_id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))


@router.put("/staff/{staff_id}", response_model=StaffUserResponse, status_code=status.HTTP_200_OK)
@router.patch("/staff/{staff_id}", response_model=StaffUserResponse, status_code=status.HTTP_200_OK)
def edit_staff_member(staff_id: int, payload: StaffUserUpdate):
    try:
        return update_staff_member(staff_id, payload)
    except ValueError as e:
        msg = str(e)
        if "not found" in msg.lower():
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=msg)
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=msg)
    except mysql.connector.IntegrityError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Database constraint error: duplicate entry or invalid reference")
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))


@router.delete("/staff/{staff_id}", response_model=StaffDeleteResponse, status_code=status.HTTP_200_OK)
def remove_staff_member(staff_id: int, soft: bool = Query(False, description="Set true to deactivate instead of permanently delete")):
    try:
        return delete_staff_member(staff_id, soft=soft)
    except ValueError as e:
        msg = str(e)
        if "not found" in msg.lower():
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=msg)
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=msg)
    except mysql.connector.IntegrityError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete staff member due to active hospital records referencing them. Please deactivate their account instead.",
        )
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))


# -------------------------------------------------------------
# Staff Endpoints under /staff (convenience alias for frontend)
# -------------------------------------------------------------

@staff_router.get("", response_model=list[StaffUserResponse], status_code=status.HTTP_200_OK)
@staff_router.get("/", response_model=list[StaffUserResponse], status_code=status.HTTP_200_OK, include_in_schema=False)
def get_all_staff_alias():
    try:
        return GetAllStaff()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@staff_router.post("", response_model=StaffUserResponse, status_code=status.HTTP_201_CREATED)
@staff_router.post("/", response_model=StaffUserResponse, status_code=status.HTTP_201_CREATED, include_in_schema=False)
def add_staff_member_alias(payload: StaffUserCreate, background_tasks: BackgroundTasks):
    try:
        return create_new_staff_user(payload, background_tasks=background_tasks)
    except mysql.connector.IntegrityError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Username or email already exists")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@staff_router.get("/{staff_id}", response_model=StaffUserResponse, status_code=status.HTTP_200_OK)
def get_staff_alias(staff_id: int):
    return get_staff_by_id_endpoint(staff_id)


@staff_router.put("/{staff_id}", response_model=StaffUserResponse, status_code=status.HTTP_200_OK)
@staff_router.patch("/{staff_id}", response_model=StaffUserResponse, status_code=status.HTTP_200_OK)
def edit_staff_alias(staff_id: int, payload: StaffUserUpdate):
    return edit_staff_member(staff_id, payload)


@staff_router.delete("/{staff_id}", response_model=StaffDeleteResponse, status_code=status.HTTP_200_OK)
def remove_staff_alias(staff_id: int, soft: bool = Query(False, description="Set true to deactivate instead of permanently delete")):
    return remove_staff_member(staff_id, soft=soft)


# -------------------------------------------------------------
# User & Patient Endpoints
# -------------------------------------------------------------

@router.delete("/{user_id}", response_model=StaffDeleteResponse, status_code=status.HTTP_200_OK)
def remove_user_by_id(user_id: int, soft: bool = Query(False, description="Set true to deactivate instead of permanently delete")):
    return remove_staff_member(user_id, soft=soft)


@router.post("/patient", response_model=PatientUserResponse, status_code=status.HTTP_201_CREATED)
def add_patient_member(payload: PatientUserCreate, background_tasks: BackgroundTasks):
    try:
        return create_new_patient_user(payload, background_tasks=background_tasks)
    except mysql.connector.IntegrityError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Username or email already exists")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.patch("/{user_id}/status", status_code=status.HTTP_200_OK)
def change_user_status(user_id: int, payload: UserStatusUpdate):
    try:
        update_user_status(user_id, payload.is_active)
        return {"message": "User status updated successfully", "user_id": user_id, "is_active": payload.is_active}
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/patients", response_model=list[PatientUserResponse], status_code=status.HTTP_200_OK)
def get_all_patients():
    try:
        return GetAllPatients()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/patient/me", response_model=PatientProfileResponse, status_code=status.HTTP_200_OK)
def get_my_patient_profile(token_payload: dict = Depends(get_current_user_payload)):
    if str(token_payload.get("role", "")).lower() != "patient":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Patient access required")
    try:
        return get_patient_profile(int(token_payload["sub"]))
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))

