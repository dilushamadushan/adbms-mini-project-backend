import logging
from typing import Dict, Any, List, Optional
from app.core.database import get_db
from app.repositories.Nurse import nurse_repo

logger = logging.getLogger(__name__)


def get_ward_overview(nurse_user_id: int, ward_id: Optional[int] = None) -> Dict[str, Any]:
    with get_db() as conn:
        overview = nurse_repo.get_nurse_ward_beds(conn, nurse_user_id, ward_id)
        if not overview:
            raise ValueError("Ward details not found for this nurse assignment.")
        return overview


def get_dashboard_stats(nurse_user_id: int, ward_id: Optional[int] = None) -> Dict[str, Any]:
    with get_db() as conn:
        stats = nurse_repo.get_dashboard_stats(conn, nurse_user_id, ward_id)
        if not stats:
            raise ValueError("Could not load dashboard statistics.")
        return stats


def get_unassigned_admissions(ward_id: Optional[int] = None) -> List[Dict[str, Any]]:
    with get_db() as conn:
        return nurse_repo.get_unassigned_admissions(conn, ward_id)


def assign_patient_to_bed(admission_id: int, bed_id: int, nurse_user_id: int) -> Dict[str, Any]:
    with get_db() as conn:
        return nurse_repo.assign_patient_to_bed(conn, admission_id, bed_id, nurse_user_id)


def get_bed_details(bed_id: int) -> Dict[str, Any]:
    with get_db() as conn:
        detail = nurse_repo.get_bed_details(conn, bed_id)
        if not detail:
            raise ValueError(f"Bed #{bed_id} not found.")
        return detail


def record_vitals(
    bed_id: int,
    nurse_user_id: int,
    bp: str,
    pulse: int,
    temperature: float,
    spo2: Optional[int] = None,
    resp_rate: Optional[int] = None,
    blood_sugar: Optional[float] = None,
    weight: Optional[float] = None,
) -> Dict[str, Any]:
    with get_db() as conn:
        return nurse_repo.record_patient_vitals(
            conn,
            bed_id,
            nurse_user_id,
            bp,
            pulse,
            temperature,
            spo2,
            resp_rate,
            blood_sugar,
            weight,
        )


def update_bed_status(bed_id: int, status: str, nurse_user_id: int) -> Dict[str, Any]:
    allowed_statuses = ("Available", "Cleaning", "Occupied")
    if status not in allowed_statuses:
        raise ValueError(f"Invalid bed status '{status}'. Must be one of {allowed_statuses}")
    with get_db() as conn:
        return nurse_repo.update_bed_status(conn, bed_id, status, nurse_user_id)


def complete_discharge(admission_id: int, nurse_user_id: int) -> Dict[str, Any]:
    with get_db() as conn:
        return nurse_repo.complete_patient_discharge(conn, admission_id, nurse_user_id)


def list_ward_patients(nurse_user_id: int) -> List[Dict[str, Any]]:
    with get_db() as conn:
        return nurse_repo.get_ward_patients(conn, nurse_user_id)


def get_patient_mar(patient_id: int) -> Dict[str, Any]:
    with get_db() as conn:
        return nurse_repo.get_patient_mar(conn, patient_id)


def administer_medication(
    rx_id: int,
    patient_id: int,
    nurse_user_id: int,
    status: str,
    reason: Optional[str] = None,
    notes: Optional[str] = None,
) -> Dict[str, Any]:
    allowed = ("Given", "Not Given", "Refused", "Held")
    if status not in allowed:
        raise ValueError(f"Invalid status '{status}'. Allowed: {allowed}")
    with get_db() as conn:
        return nurse_repo.administer_medication(
            conn, rx_id, patient_id, nurse_user_id, status, reason, notes
        )


def get_doctor_orders(patient_id: int) -> List[Dict[str, Any]]:
    with get_db() as conn:
        return nurse_repo.get_doctor_orders(conn, patient_id)


def acknowledge_doctor_order(
    order_id: int, nurse_user_id: int, status: str
) -> Dict[str, Any]:
    allowed = ("Acknowledged", "In_Progress", "Done")
    if status not in allowed:
        raise ValueError(f"Invalid status '{status}'. Allowed: {allowed}")
    with get_db() as conn:
        return nurse_repo.acknowledge_doctor_order(conn, order_id, nurse_user_id, status)


def get_nursing_notes(patient_id: int) -> List[Dict[str, Any]]:
    with get_db() as conn:
        return nurse_repo.get_nursing_notes(conn, patient_id)


def add_nursing_note(
    patient_id: int,
    nurse_user_id: int,
    note_type: str,
    subjective: Optional[str],
    objective: Optional[str],
    assessment: Optional[str],
    plan: Optional[str],
    content: str,
) -> Dict[str, Any]:
    with get_db() as conn:
        return nurse_repo.add_nursing_note(
            conn, patient_id, nurse_user_id, note_type, subjective, objective, assessment, plan, content
        )


def log_intake_output(
    patient_id: int,
    nurse_user_id: int,
    io_type: str,
    category: str,
    volume_ml: int,
    notes: Optional[str] = None,
) -> Dict[str, Any]:
    if io_type not in ("Intake", "Output"):
        raise ValueError("io_type must be 'Intake' or 'Output'")
    with get_db() as conn:
        return nurse_repo.log_intake_output(
            conn, patient_id, nurse_user_id, io_type, category, volume_ml, notes
        )


def get_patient_io_summary(patient_id: int, target_date: Optional[str] = None) -> Dict[str, Any]:
    with get_db() as conn:
        return nurse_repo.get_patient_io_summary(conn, patient_id, target_date)


def get_ward_nurses() -> List[Dict[str, Any]]:
    with get_db() as conn:
        return nurse_repo.get_ward_nurses(conn)


def get_ward_doctor_orders() -> List[Dict[str, Any]]:
    with get_db() as conn:
        return nurse_repo.get_ward_doctor_orders(conn)


def get_ward_mar() -> Dict[str, Any]:
    with get_db() as conn:
        return nurse_repo.get_ward_mar(conn)


def get_ward_nursing_notes() -> List[Dict[str, Any]]:
    with get_db() as conn:
        return nurse_repo.get_ward_nursing_notes(conn)


def get_nurse_lab_orders(status_filter: Optional[str] = None) -> List[Dict[str, Any]]:
    with get_db() as conn:
        return nurse_repo.get_nurse_lab_orders(conn, status_filter)


def complete_lab_order(lab_id: int, nurse_user_id: int, results_text: str) -> Dict[str, Any]:
    with get_db() as conn:
        return nurse_repo.complete_lab_order(conn, lab_id, nurse_user_id, results_text)


def get_pending_lab_count() -> int:
    with get_db() as conn:
        return nurse_repo.get_pending_lab_count(conn)




