from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from app.core.security import get_current_user_payload
from app.schema.user_schema import StaffUserCreate, StaffUserResponse, PatientUserCreate, PatientUserResponse, PatientProfileResponse, UserStatusUpdate
from app.services.user_service import create_new_staff_user, create_new_patient_user, update_user_status, GetAllPatients, GetAllStaff, get_patient_profile

router = APIRouter(prefix="/users", tags=["Users"])

import mysql.connector

@router.post("/staff", response_model=StaffUserResponse, status_code=status.HTTP_201_CREATED)
def add_staff_member(payload: StaffUserCreate, background_tasks: BackgroundTasks):
    try:
        return create_new_staff_user(payload, background_tasks=background_tasks)
    except mysql.connector.IntegrityError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Username or email already exists")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

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


@router.get("/staff", response_model=list[StaffUserResponse], status_code=status.HTTP_200_OK)
def get_all_staff():
    try:
        return GetAllStaff()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
