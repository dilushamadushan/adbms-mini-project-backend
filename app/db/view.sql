USE hms;

CREATE OR REPLACE VIEW vw_department_workload AS
WITH DeptStats AS (
    SELECT 
        d.dept_id,
        d.dept_name,
        COUNT(DISTINCT s.staff_id) AS doctor_count,
        COUNT(a.apt_id) AS total_appointments,
        COUNT(DISTINCT a.patient_id) AS pts_seen,
        SUM(COUNT(a.apt_id)) OVER () AS hospital_total_appts
    FROM Departments d
    LEFT JOIN Staff s ON s.dept_id = d.dept_id
    LEFT JOIN Appointments a ON a.dept_id = d.dept_id
    GROUP BY d.dept_id, d.dept_name
)
SELECT 
    dept_id,
    dept_name,
    doctor_count,
    total_appointments,
    pts_seen,
    ROUND(
        COALESCE((total_appointments * 100.0) / NULLIF(hospital_total_appts, 0), 0),
        1
    ) AS workload_percentage,
    DENSE_RANK() OVER (ORDER BY total_appointments DESC) AS dept_rank,
    CASE 
        WHEN (total_appointments * 100.0) / NULLIF(hospital_total_appts, 0) >= 30.0 OR total_appointments >= 100 THEN 'Critical'
        WHEN (total_appointments * 100.0) / NULLIF(hospital_total_appts, 0) >= 20.0 OR total_appointments >= 50 THEN 'High'
        WHEN (total_appointments * 100.0) / NULLIF(hospital_total_appts, 0) >= 10.0 OR total_appointments >= 20 THEN 'Moderate'
        ELSE 'Low'
    END AS workload_level
FROM DeptStats;

CREATE OR REPLACE VIEW vw_top_provider_workload AS
WITH ProviderStats AS (
    SELECT 
        s.staff_id,
        CONCAT('Dr. ', s.first_name, ' ', s.last_name) AS provider_name,
        s.specialty,
        d.dept_name,
        COUNT(a.apt_id) AS pts_seen,
        fn_calculate_provider_avg_time(s.staff_id) AS avg_time_minutes,
        SUM(COUNT(a.apt_id)) OVER () AS total_provider_appts
    FROM Staff s
    LEFT JOIN Departments d ON s.dept_id = d.dept_id
    LEFT JOIN Appointments a ON a.doctor_id = s.staff_id
    GROUP BY s.staff_id, s.first_name, s.last_name, s.specialty, d.dept_name
)
SELECT 
    staff_id,
    provider_name,
    specialty,
    dept_name,
    pts_seen,
    avg_time_minutes,
    CONCAT(avg_time_minutes, 'm') AS avg_time_formatted,
    DENSE_RANK() OVER (ORDER BY pts_seen DESC) AS workload_rank,
    ROUND(
        COALESCE((pts_seen * 100.0) / NULLIF(total_provider_appts, 0), 0),
        1
    ) AS share_percentage
FROM ProviderStats;

CREATE OR REPLACE VIEW vw_hospital_kpi_detail AS
SELECT
    (SELECT COUNT(*) FROM Patients)                                        AS total_patients,
    (SELECT COUNT(*) FROM Beds)                                            AS total_beds,
    (SELECT COUNT(*) FROM Beds WHERE status = 'Occupied')                  AS occupied_beds,
    (SELECT COUNT(*) FROM Beds WHERE status = 'Available')                 AS available_beds,
    (SELECT COUNT(*) FROM Beds WHERE status = 'Cleaning')                  AS cleaning_beds,
    fn_bed_occupancy_pct(NULL)                                             AS bed_occupancy_pct,
    CONCAT(ROUND(fn_bed_occupancy_pct(NULL), 1), '%')                     AS bed_occupancy_formatted,
    (SELECT COUNT(*) FROM Appointments WHERE apt_date = CURDATE())         AS todays_appointments,
    (SELECT COUNT(*) FROM Appointments
     WHERE apt_date = CURDATE() AND status = 'Scheduled')                  AS scheduled_today,
    (SELECT COUNT(*) FROM Appointments
     WHERE apt_date = CURDATE() AND status = 'Completed')                  AS completed_today,
    (SELECT COUNT(*) FROM Appointments
     WHERE apt_date = CURDATE() AND status = 'Cancelled')                  AS cancelled_today,
    (SELECT COUNT(*) FROM Appointments
     WHERE apt_date = CURDATE() AND status = 'No-Show')                    AS no_show_today,
    CURDATE()                                                              AS kpi_date;

CREATE OR REPLACE VIEW vw_audit_logs_enriched AS
SELECT
    a.log_id,
    DATE_FORMAT(a.timestamp, '%Y-%m-%d %H:%i:%s') AS timestamp,
    a.timestamp AS raw_timestamp,
    a.actor_id,
    COALESCE(
        CASE 
            WHEN s.first_name IS NOT NULL AND u.role = 'doctor' THEN CONCAT('Dr. ', s.first_name, ' ', s.last_name)
            WHEN s.first_name IS NOT NULL THEN CONCAT(s.first_name, ' ', s.last_name)
            ELSE NULL
        END,
        u.username,
        NULLIF(JSON_UNQUOTE(JSON_EXTRACT(a.details, '$.actor')), 'null'),
        NULLIF(JSON_UNQUOTE(JSON_EXTRACT(a.details, '$.username')), 'null'),
        'System'
    ) AS actor,
    a.action_type AS action,
    COALESCE(a.resource_table, 'System') AS resource,
    CASE
        WHEN JSON_UNQUOTE(JSON_EXTRACT(a.details, '$.risk')) IS NOT NULL 
             AND UPPER(JSON_UNQUOTE(JSON_EXTRACT(a.details, '$.risk'))) IN ('HIGH', 'MEDIUM', 'LOW')
            THEN UPPER(JSON_UNQUOTE(JSON_EXTRACT(a.details, '$.risk')))
        WHEN UPPER(COALESCE(a.action_type, '')) LIKE '%DELETE%' 
             OR UPPER(COALESCE(a.action_type, '')) LIKE '%DROP%' 
             OR UPPER(COALESCE(a.action_type, '')) LIKE '%REVOKE%'
             OR UPPER(COALESCE(a.action_type, '')) LIKE '%PURGE%'
             OR UPPER(COALESCE(a.action_type, '')) LIKE '%UNAUTHORIZED%'
             OR UPPER(COALESCE(a.action_type, '')) LIKE '%BREACH%'
             OR UPPER(COALESCE(a.action_type, '')) LIKE '%FAIL%'
            THEN 'HIGH'
        WHEN UPPER(COALESCE(a.action_type, '')) LIKE '%UPDATE%' 
             OR UPPER(COALESCE(a.action_type, '')) LIKE '%MODIFY%' 
             OR UPPER(COALESCE(a.action_type, '')) LIKE '%PASSWORD%'
             OR UPPER(COALESCE(a.action_type, '')) LIKE '%ROLE%'
             OR UPPER(COALESCE(a.action_type, '')) LIKE '%STATUS%'
             OR UPPER(COALESCE(a.action_type, '')) LIKE '%USER%'
             OR UPPER(COALESCE(a.action_type, '')) LIKE '%DIAGNOSIS%'
             OR UPPER(COALESCE(a.action_type, '')) LIKE '%PRESCRIPTION%'
             OR UPPER(COALESCE(a.action_type, '')) LIKE '%CREATE%'
            THEN 'MEDIUM'
        ELSE 'LOW'
    END AS risk,
    a.details
FROM Audit_Logs a
LEFT JOIN Users u ON a.actor_id = u.user_id
LEFT JOIN Staff s ON u.user_id = s.user_id;

USE hms;

CREATE OR REPLACE VIEW vw_recep_appointments AS
SELECT a.apt_id, a.patient_id,
       CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
       a.doctor_id, CONCAT('Dr. ', s.first_name, ' ', s.last_name) AS doctor_name,
       a.dept_id, d.dept_name,
       a.apt_date,
       TIME_FORMAT(a.time_slot, '%H:%i') AS time_slot,
       a.status
FROM Appointments a
JOIN Patients p ON p.patient_id = a.patient_id
JOIN Staff s ON s.staff_id = a.doctor_id
JOIN Departments d ON d.dept_id = a.dept_id;
