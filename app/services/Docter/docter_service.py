from logging import error
import mysql.connector
from app.core.database import get_db
from app.repositories.Docter import docter_repo

def get_doctor_medicine_list():
    with get_db() as conn:
        return docter_repo.get_doctor_medicine_list(conn)


def get_lab_order_patient_details():
    with get_db() as conn:
        return docter_repo.get_lab_order_patient_details(conn)


def create_lab_order(patient_id: int, doctor_user_id: int, test_type: str):
    try:
        with get_db() as conn:
            return docter_repo.create_lab_order(conn, patient_id, doctor_user_id, test_type)
    except mysql.connector.Error as err:
        if err.sqlstate == "45000":
            raise ValueError(err.msg) from err
        raise


def get_patient_lab_results(patient_id: int):
    try:
        with get_db() as conn:
            return docter_repo.get_patient_lab_results(conn, patient_id)
    except mysql.connector.Error as err:
        if err.sqlstate == "45000":
            raise ValueError(err.msg) from err
        raise


def create_prescription(
    patient_id: int,
    apt_id: int,
    doctor_id: int,
    diagnosis: str,
    clinical_notes: str | None,
    medicines: list[dict],
):
    try:
        with get_db() as conn:
            record_id = docter_repo.create_prescription(
                conn,
                patient_id,
                apt_id,
                doctor_id,
                diagnosis,
                clinical_notes,
                medicines,
            )
            conn.commit()
            return {
                "message": "Prescription saved successfully",
                "record_id": record_id,
            }
    except mysql.connector.Error as err:
        if err.sqlstate == "45000":
            raise ValueError(err.msg) from err
        raise


def create_admitted_prescription(
    patient_id: int,
    apt_id: int,
    doctor_id: int,
    diagnosis: str,
    clinical_notes: str | None,
    medicines: list[dict],
    nurse_orders: list[dict],
):
    try:
        with get_db() as conn:
            record_id = docter_repo.create_admitted_prescription(
                conn, patient_id, apt_id, doctor_id, diagnosis, clinical_notes,
                medicines, nurse_orders,
            )
            conn.commit()
            return {"message": "Admitted prescription saved successfully", "record_id": record_id}
    except mysql.connector.Error as err:
        if err.sqlstate == "45000":
            raise ValueError(err.msg) from err
        raise

def list_appointments_by_doctor(doctor_id: int):
    with get_db() as conn:
        if not docter_repo.doctor_exists(conn, doctor_id):
            raise ValueError("Doctor not found")
        return docter_repo.get_appointments_by_doctor(conn, doctor_id)

def get_appointment_count(doctor_id: int):
    with get_db() as conn:
        if not docter_repo.doctor_exists(conn, doctor_id):
            raise ValueError("Doctor not found")
        return docter_repo.get_appointment_count(conn, doctor_id)

def get_completed_appointment_count(doctor_id: int):
    with get_db() as conn:
        if not docter_repo.doctor_exists(conn, doctor_id):
            raise ValueError("Doctor not found")
        return docter_repo.get_completed_appointment_count(conn, doctor_id)

def get_total_patients_count(doctor_id: int):
    with get_db() as conn:
        if not docter_repo.doctor_exists(conn, doctor_id):
            raise ValueError("Doctor not found")
        return docter_repo.get_total_patients_count(conn, doctor_id)

def get_appointment_history_by_doctor(doctor_id: int):
    with get_db() as conn:
        if not docter_repo.doctor_exists(conn, doctor_id):
            raise ValueError("Doctor not found")
        return docter_repo.get_appointment_history_by_doctor(conn, doctor_id)

def get_upcoming_appointments_by_doctor(doctor_id: int):
    with get_db() as conn:
        if not docter_repo.doctor_exists(conn, doctor_id):
            raise ValueError("Doctor not found")
        return docter_repo.get_upcoming_appointments_by_doctor(conn, doctor_id)

def get_doctor_appointments_by_user(user_id: int):
    with get_db() as conn:
        if not docter_repo.doctor_user_exists(conn, user_id):
            raise ValueError("Doctor not found")
        return docter_repo.get_doctor_appointments_by_user(conn, user_id)


def get_patient_details(patient_id: int):
    with get_db() as conn:
        patient = docter_repo.get_patient_details(conn, patient_id)
        if patient is None:
            raise ValueError("Patient not found")
        return patient


def get_patient_appointment_details(appointment_id: int):
    with get_db() as conn:
        appointment = docter_repo.get_patient_appointment_details(conn, appointment_id)
        if appointment is None:
            raise ValueError("Appointment not found")
        return appointment


def get_ward_names():
    with get_db() as conn:
        return docter_repo.get_ward_names(conn)


def create_admission_request(
    patient_id: int,
    gender: str,
    ward_id: int,
    reason: str,
    doctor_id: int,
    user_id: int,
):
    try:
        with get_db() as conn:
            admission_id = docter_repo.create_admission_request(
                conn, patient_id, gender, ward_id, reason, doctor_id, user_id
            )
            return {"message": "Saved", "admission_id": admission_id}
    except mysql.connector.Error as err:
        if err.sqlstate == "45000":
            raise ValueError(err.msg) from err
        raise


def request_discharge(admission_id: int, doctor_id: int, notes: str):
    try:
        with get_db() as conn:
            docter_repo.request_discharge(conn, admission_id, doctor_id, notes)
            return {"message": "Discharged"}
    except mysql.connector.Error as err:
        if err.sqlstate == "45000":
            raise ValueError(err.msg) from err
        raise


def complete_appointment(appointment_id: int, doctor_id: int):
    try:
        with get_db() as conn:
            docter_repo.complete_appointment(conn, appointment_id, doctor_id)
            return {"message": "Appointment marked as completed"}
    except mysql.connector.Error as err:
        if err.sqlstate == "45000":
            raise ValueError(err.msg) from err
        raise


def get_active_admission_by_patient(patient_id: int):
    with get_db() as conn:
        return docter_repo.get_active_admission_by_patient(conn, patient_id)
