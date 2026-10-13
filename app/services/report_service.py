import csv
import io
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any
from app.core.database import get_db
from app.repositories import report_repo
from app.schema.report_schema import (
    DepartmentWorkloadItem,
    ProviderWorkloadItem,
    WorkloadSummaryKPIs,
    WorkloadReportResponse,
    DepartmentWorkloadResponse,
    ProviderWorkloadResponse,
    WorkloadRollupItem,
    BedOccupancyDetails,
    TodayAppointmentsDetails,
    HospitalKPIOverviewResponse,
)


def _format_department_items(dept_rows: List[Dict[str, Any]]) -> List[DepartmentWorkloadItem]:
    if not dept_rows:
        return []

    # Find maximum appointments across departments for normalizing UI progress bars
    max_appts = max((int(r.get("total_appointments") or 0) for r in dept_rows), default=1)
    if max_appts == 0:
        max_appts = 1

    formatted: List[DepartmentWorkloadItem] = []
    for r in dept_rows:
        total_appts = int(r.get("total_appointments") or 0)
        # Normalize bar between 0 and 95% (or 100%) so UI progress bar looks proportional
        progress_pct = round((total_appts / max_appts) * 92.0, 1) if total_appts > 0 else 0.0
        
        # Ensure minimum visible bar width for non-zero items (e.g. 10%)
        if total_appts > 0 and progress_pct < 10.0:
            progress_pct = 10.0

        raw_pct = float(r.get("workload_percentage") or 0.0)

        formatted.append(
            DepartmentWorkloadItem(
                dept_id=int(r["dept_id"]),
                dept_name=str(r["dept_name"]),
                doctor_count=int(r.get("doctor_count") or 0),
                total_appointments=total_appts,
                pts_seen=int(r.get("pts_seen") or 0),
                workload_percentage=raw_pct,
                progress_bar_pct=progress_pct,
                dept_rank=int(r.get("dept_rank") or 1),
                workload_level=str(r.get("workload_level") or "Low"),
            )
        )
    return formatted


def _format_provider_items(provider_rows: List[Dict[str, Any]]) -> List[ProviderWorkloadItem]:
    formatted: List[ProviderWorkloadItem] = []
    for r in provider_rows:
        avg_mins = int(r.get("avg_time_minutes") or 18)
        formatted.append(
            ProviderWorkloadItem(
                staff_id=int(r["staff_id"]),
                provider_name=str(r["provider_name"]),
                specialty=r.get("specialty"),
                dept_name=r.get("dept_name"),
                pts_seen=int(r.get("pts_seen") or 0),
                avg_time_minutes=avg_mins,
                avg_time=str(r.get("avg_time_formatted") or f"{avg_mins}m"),
                workload_rank=int(r.get("workload_rank") or 1),
                share_percentage=float(r.get("share_percentage") or 0.0),
            )
        )
    return formatted


def generate_workload_report(
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    top_n: int = 5,
) -> WorkloadReportResponse:
    """
    Generates full workload report using advanced stored procedure sp_generate_workload_report.
    Returns both Department Workload and Top Provider Workload matching the UI cards.
    """
    with get_db() as conn:
        dept_rows, provider_rows = report_repo.get_workload_report_from_sp(
            conn, start_date=start_date, end_date=end_date, top_n=top_n
        )
        kpi_data = report_repo.get_hospital_workload_kpis(
            conn, start_date=start_date, end_date=end_date
        )

    dept_items = _format_department_items(dept_rows)
    # Filter departments with > 0 appointments or top departments
    active_depts = [d for d in dept_items if d.total_appointments > 0]
    if not active_depts:
        active_depts = dept_items[:6]

    provider_items = _format_provider_items(provider_rows)

    busiest_dept = active_depts[0].dept_name if active_depts else "N/A"
    top_doc = provider_items[0].provider_name if provider_items else "N/A"

    kpis = WorkloadSummaryKPIs(
        total_departments=len(active_depts),
        total_appointments=kpi_data.get("total_appointments", 0),
        total_pts_seen=kpi_data.get("total_pts_seen", 0),
        busiest_department=busiest_dept,
        top_provider=top_doc,
        hospital_avg_consult_time=f"{kpi_data.get('overall_avg_time', 18)}m",
    )

    return WorkloadReportResponse(
        report_title="Hospital Department & Provider Workload Report",
        generated_at=datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
        period_start=start_date,
        period_end=end_date,
        summary_kpis=kpis,
        department_workload=active_depts,
        top_providers=provider_items,
    )


def get_department_workload_summary() -> DepartmentWorkloadResponse:
    """
    Fetches department workload from MySQL View `vw_department_workload`.
    """
    with get_db() as conn:
        rows = report_repo.get_department_workload_from_view(conn)
    items = _format_department_items(rows)
    active = [d for d in items if d.total_appointments > 0]
    return DepartmentWorkloadResponse(
        departments=active if active else items,
        total_departments=len(active if active else items),
    )


def get_top_providers_summary(limit: int = 5) -> ProviderWorkloadResponse:
    """
    Fetches top providers ranked by patients seen from MySQL View `vw_top_provider_workload`.
    """
    with get_db() as conn:
        rows = report_repo.get_top_providers_from_view(conn, limit=limit)
    items = _format_provider_items(rows)
    return ProviderWorkloadResponse(
        providers=items,
        total_providers_ranked=len(items),
    )


def get_rollup_analytics() -> List[WorkloadRollupItem]:
    """
    Fetches subtotal and grand total analytics using MySQL GROUP BY ... WITH ROLLUP.
    """
    with get_db() as conn:
        rows = report_repo.get_workload_with_rollup(conn)
    return [
        WorkloadRollupItem(
            dept_name=r.get("dept_name"),
            status=r.get("status"),
            appointment_count=int(r.get("appointment_count") or 0),
        )
        for r in rows
    ]


def export_workload_csv(
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    top_n: int = 10,
) -> str:
    """
    Generates a structured CSV report representing the workload analytics.
    """
    report = generate_workload_report(start_date=start_date, end_date=end_date, top_n=top_n)

    output = io.StringIO()
    writer = csv.writer(output)

    writer.writerow(["=== HOSPITAL WORKLOAD SUMMARY REPORT ==="])
    writer.writerow(["Generated At", report.generated_at])
    writer.writerow(["Total Appointments", report.summary_kpis.total_appointments])
    writer.writerow(["Total Patients Seen", report.summary_kpis.total_pts_seen])
    writer.writerow(["Busiest Department", report.summary_kpis.busiest_department])
    writer.writerow(["Top Provider", report.summary_kpis.top_provider])
    writer.writerow(["Hospital Avg Time", report.summary_kpis.hospital_avg_consult_time])
    writer.writerow([])

    writer.writerow(["--- DEPARTMENT WORKLOAD ---"])
    writer.writerow(["Rank", "Department Name", "Workload Level", "Total Appointments", "Workload %", "Doctors"])
    for d in report.department_workload:
        writer.writerow([d.dept_rank, d.dept_name, d.workload_level, d.total_appointments, f"{d.workload_percentage}%", d.doctor_count])
    writer.writerow([])

    writer.writerow(["--- TOP PROVIDER WORKLOAD ---"])
    writer.writerow(["Rank", "Provider Name", "Specialty", "Department", "Patients Seen", "Avg Time", "Share %"])
    for p in report.top_providers:
        writer.writerow([p.workload_rank, p.provider_name, p.specialty or "", p.dept_name or "", p.pts_seen, p.avg_time, f"{p.share_percentage}%"])

    return output.getvalue()


def get_hospital_kpi_overview(target_date: Optional[str] = None) -> HospitalKPIOverviewResponse:
    """
    Retrieves high-level hospital KPIs:
      - Total registered patients (total_patients)
      - Bed occupancy percentage & count breakdown (bed_occupancy)
      - Today's appointment counts (todays_appointments / today_appts)
    """
    with get_db() as conn:
        data = report_repo.get_hospital_kpi_overview(conn, target_date=target_date)

    total_patients = data["total_patients"]
    total_beds = data["total_beds"]
    occupied_beds = data["occupied_beds"]
    available_beds = data["available_beds"]
    cleaning_beds = data["cleaning_beds"]
    todays_appts = data["todays_appointments"]
    resolved_date = data["target_date"]

    occupancy_pct = round((occupied_beds * 100.0) / total_beds, 2) if total_beds > 0 else 0.0

    bed_details = BedOccupancyDetails(
        total_beds=total_beds,
        occupied_beds=occupied_beds,
        available_beds=available_beds,
        cleaning_beds=cleaning_beds,
        occupancy_rate=occupancy_pct,
        formatted_occupancy=f"{occupancy_pct}%",
    )

    appointment_details = TodayAppointmentsDetails(
        total_today=todays_appts,
        scheduled=data["scheduled_today"],
        completed=data["completed_today"],
        cancelled=data["cancelled_today"],
        no_show=data["no_show_today"],
    )

    return HospitalKPIOverviewResponse(
        total_patients=total_patients,
        total_patient=total_patients,
        bed_occupancy=occupancy_pct,
        bed_occupancy_pct=occupancy_pct,
        bed_occupancy_formatted=f"{occupancy_pct}%",
        total_beds=total_beds,
        occupied_beds=occupied_beds,
        available_beds=available_beds,
        todays_appointments=todays_appts,
        today_appointments=todays_appts,
        today_appts=todays_appts,
        target_date=resolved_date,
        bed_details=bed_details,
        appointment_details=appointment_details,
    )

