-- TG/1407 --

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

-- Chavi -- 

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


-- thimira --

CREATE OR REPLACE VIEW vw_medicine_inventory AS
SELECT 
    m.medicine_id,
    m.med_name,
    m.generic_name,
    m.unit_price,
    m.stock_qty,
    m.reorder_level,
    m.expiry_date,
    DATEDIFF(m.expiry_date, CURDATE()) AS days_to_expiry,
    fn_calculate_medicine_status(m.stock_qty, m.reorder_level, m.expiry_date) AS stock_status,
    (m.unit_price * m.stock_qty) AS inventory_value,
    m.is_active,
    m.created_at,
    m.updated_at
FROM Medicines m;

CREATE OR REPLACE VIEW vw_near_expiry_alerts AS
SELECT 
    m.medicine_id,
    m.med_name,
    m.generic_name,
    m.stock_qty,
    m.unit_price,
    m.expiry_date,
    DATEDIFF(m.expiry_date, CURDATE()) AS days_remaining,
    CASE 
        WHEN m.expiry_date <= CURDATE() THEN 'EXPIRED'
        ELSE 'EXPIRING_SOON'
    END AS urgency_level
FROM Medicines m
WHERE m.expiry_date <= DATE_ADD(CURDATE(), INTERVAL 30 DAY)
  AND m.is_active = TRUE
ORDER BY m.expiry_date ASC;

CREATE OR REPLACE VIEW vw_daily_dispensing_summary AS
SELECT 
    DATE(d.dispensed_at) AS dispense_date,
    COUNT(d.dispense_id) AS total_transactions,
    SUM(d.quantity) AS total_units_dispensed,
    SUM(d.quantity * d.unit_price_at_sale) AS total_revenue,
    COUNT(DISTINCT d.pharmacist_id) AS pharmacists_on_duty,
    GROUP_CONCAT(DISTINCT m.med_name ORDER BY m.med_name SEPARATOR ', ') AS medicine_names,
    GROUP_CONCAT(DISTINCT CONCAT(m.med_name, ' (', d.quantity, ' units)') ORDER BY m.med_name SEPARATOR ', ') AS medicines_detail
FROM Dispensations d
LEFT JOIN Medicines m ON d.medicine_id = m.medicine_id
GROUP BY DATE(d.dispensed_at)
ORDER BY dispense_date DESC;




-- ishan --

-- ------------- doctor -------------------

-- get all wards
CREATE OR REPLACE VIEW vw_ward_names AS
SELECT ward_name
FROM wards
ORDER BY ward_name;

-- get all admissions data
CREATE OR REPLACE VIEW vw_admissions_data AS
SELECT admission_id, patient_id, ward_id, bed_id, admitted_doctor_id, admitted_by,
       admitted_at, admission_reason, guardian_name, guardian_relationship,
       guardian_contact, gender, status
FROM admissions;

-- Medicine list for the doctor's dropdown.
-- Returns the id, name and generic name of every medicine,
-- sorted by name.
-- =====================================================
CREATE OR REPLACE VIEW vw_doctor_medicine_list AS
SELECT medicine_id, med_name, generic_name
FROM medicines
ORDER BY med_name;

-- Gets patient and appointment details for the doctor's lab-order page.
CREATE OR REPLACE VIEW vw_lab_order_patient_details AS
SELECT
    p.patient_id,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
    TIMESTAMPDIFF(YEAR, p.dob, CURDATE()) AS age,
    p.blood_group,
    COALESCE(NULLIF(TRIM(p.allergies), ''), 'None') AS allergies,
    a.apt_id AS appointment_id,
    a.apt_date AS appointment_date,
    a.status AS appointment_status
FROM Patients AS p
INNER JOIN Appointments AS a
    ON a.patient_id = p.patient_id;

-- =========================================================
-- VIEW: CURRENTLY ADMITTED PATIENTS
-- =========================================================
-- Returns all patients whose admission status is 'Admitted'.
-- Bed information is optional because the current Admissions
-- table allows bed_id to be NULL.
-- =========================================================
CREATE OR REPLACE VIEW vw_current_admitted_patients AS
SELECT
    a.admission_id,
    p.patient_id,

    CONCAT(
        p.first_name,
        ' ',
        p.last_name
    ) AS patient_name,

    TIMESTAMPDIFF(
        YEAR,
        p.dob,
        CURRENT_DATE
    ) AS age,

    a.gender,

    COALESCE(
        p.blood_group,
        'Not recorded'
    ) AS blood_group,

    COALESCE(
        NULLIF(TRIM(p.allergies), ''),
        'None recorded'
    ) AS allergies,

    COALESCE(
        w.ward_name,
        'Ward not assigned'
    ) AS ward_name,

    COALESCE(
        b.bed_number,
        'Bed not assigned'
    ) AS bed_number,

    a.admission_reason,
    a.admitted_at,
    a.status

FROM Admissions AS a

INNER JOIN Patients AS p
    ON p.patient_id = a.patient_id

LEFT JOIN Wards AS w
    ON w.ward_id = a.ward_id

LEFT JOIN Beds AS b
    ON b.bed_id = a.bed_id

WHERE a.status = 'Admitted'

ORDER BY
    a.admitted_at DESC;

-- ----------------------- patient ------------------------------------------

CREATE OR REPLACE VIEW vw_doctor_departments AS
SELECT
    s.staff_id                                AS doctor_id,
    CONCAT(s.first_name, ' ', s.last_name)    AS doctor_name,
    s.specialty,
    d.dept_id,
    d.dept_name                               AS department_name,
    u.is_active
FROM staff s
JOIN users u        ON u.user_id = s.user_id
JOIN departments d  ON d.dept_id = s.dept_id
WHERE u.role = 'doctor';

-- nimhara --

CREATE OR REPLACE VIEW vw_nurse_ward_overview AS
SELECT 
    w.ward_id,
    w.ward_name,
    w.total_beds,
    w.nurse_in_charge_id,
    CONCAT(s.first_name, ' ', s.last_name) AS nurse_name,
    COUNT(CASE WHEN b.status = 'Occupied' THEN 1 END) AS occupied_beds,
    COUNT(CASE WHEN b.status = 'Available' THEN 1 END) AS available_beds,
    COUNT(CASE WHEN b.status = 'Cleaning' THEN 1 END) AS cleaning_beds,
    ROUND(
        COALESCE(
            (COUNT(CASE WHEN b.status = 'Occupied' THEN 1 END) * 100.0) / NULLIF(w.total_beds, 0),
            0
        ),
        1
    ) AS occupancy_rate
FROM Wards w
LEFT JOIN Staff s ON w.nurse_in_charge_id = s.staff_id
LEFT JOIN Beds b ON w.ward_id = b.ward_id
GROUP BY w.ward_id, w.ward_name, w.total_beds, w.nurse_in_charge_id, s.first_name, s.last_name;


CREATE OR REPLACE VIEW vw_nurse_ward_beds AS
SELECT 
    b.bed_id,
    b.bed_number,
    b.ward_id,
    w.ward_name,
    w.nurse_in_charge_id,
    b.status AS bed_status,
    b.current_patient_id,
    CASE 
        WHEN p.patient_id IS NOT NULL THEN CONCAT(p.first_name, ' ', p.last_name)
        ELSE NULL
    END AS patient_name,
    p.dob,
    p.blood_group,
    p.allergies,
    adm.admission_id,
    adm.admitted_at,
    adm.admission_reason,
    CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS attending_doctor_name,
    dis.discharge_id,
    dis.status AS discharge_status,
    (
        SELECT vl.bp 
        FROM Vitals_Log vl 
        WHERE vl.patient_id = b.current_patient_id 
        ORDER BY vl.recorded_at DESC 
        LIMIT 1
    ) AS latest_bp,
    (
        SELECT vl.pulse 
        FROM Vitals_Log vl 
        WHERE vl.patient_id = b.current_patient_id 
        ORDER BY vl.recorded_at DESC 
        LIMIT 1
    ) AS latest_pulse,
    (
        SELECT vl.temperature 
        FROM Vitals_Log vl 
        WHERE vl.patient_id = b.current_patient_id 
        ORDER BY vl.recorded_at DESC 
        LIMIT 1
    ) AS latest_temperature,
    (
        SELECT vl.spo2 
        FROM Vitals_Log vl 
        WHERE vl.patient_id = b.current_patient_id 
        ORDER BY vl.recorded_at DESC 
        LIMIT 1
    ) AS latest_spo2,
    (
        SELECT vl.recorded_at 
        FROM Vitals_Log vl 
        WHERE vl.patient_id = b.current_patient_id 
        ORDER BY vl.recorded_at DESC 
        LIMIT 1
    ) AS latest_vitals_time
FROM Beds b
INNER JOIN Wards w ON b.ward_id = w.ward_id
LEFT JOIN Patients p ON b.current_patient_id = p.patient_id
LEFT JOIN Admissions adm ON (
    adm.patient_id = p.patient_id 
    AND (adm.bed_id = b.bed_id OR adm.status = 'Admitted')
)
LEFT JOIN Staff doc ON adm.admitted_doctor_id = doc.staff_id
LEFT JOIN Discharges dis ON adm.admission_id = dis.admission_id;


CREATE OR REPLACE VIEW vw_nurse_admitted_patients AS
SELECT 
    p.patient_id,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
    p.dob,
    TIMESTAMPDIFF(YEAR, p.dob, CURDATE()) AS age,
    p.blood_group,
    p.emergency_contact,
    p.allergies,
    adm.admission_id,
    adm.admitted_at,
    adm.admission_reason,
    adm.status AS admission_status,
    w.ward_id,
    w.ward_name,
    w.nurse_in_charge_id,
    b.bed_id,
    b.bed_number,
    b.status AS bed_status,
    CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS attending_doctor,
    dis.discharge_id,
    dis.status AS discharge_status,
    dis.discharge_notes
FROM Admissions adm
INNER JOIN Patients p ON adm.patient_id = p.patient_id
INNER JOIN Wards w ON adm.ward_id = w.ward_id
LEFT JOIN Beds b ON adm.bed_id = b.bed_id
LEFT JOIN Staff doc ON adm.admitted_doctor_id = doc.staff_id
LEFT JOIN Discharges dis ON adm.admission_id = dis.admission_id
WHERE adm.status = 'Admitted';


CREATE OR REPLACE VIEW vw_patient_active_prescriptions AS
SELECT 
    rx.rx_id,
    rx.record_id,
    mr.patient_id,
    rx.med_name,
    rx.dosage,
    rx.duration,
    rx.status AS rx_status,
    CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS prescribing_doctor,
    fn_check_allergy_conflict(mr.patient_id, rx.med_name) AS has_allergy_conflict,
    p.allergies AS patient_allergies,
    (
        SELECT mar.status 
        FROM Medication_Administration_Records mar 
        WHERE mar.rx_id = rx.rx_id 
        ORDER BY mar.administered_at DESC 
        LIMIT 1
    ) AS latest_admin_status,
    (
        SELECT mar.administered_at 
        FROM Medication_Administration_Records mar 
        WHERE mar.rx_id = rx.rx_id 
        ORDER BY mar.administered_at DESC 
        LIMIT 1
    ) AS latest_admin_time
FROM Prescriptions rx
INNER JOIN Medical_Records mr ON rx.record_id = mr.record_id
INNER JOIN Patients p ON mr.patient_id = p.patient_id
LEFT JOIN Staff doc ON mr.doctor_id = doc.staff_id
WHERE rx.status = 'Active';


CREATE OR REPLACE VIEW vw_nurse_doctor_orders AS
SELECT 
    ord.order_id,
    ord.patient_id,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
    b.bed_id,
    b.bed_number,
    ord.doctor_id,
    CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS doctor_name,
    ord.order_type,
    ord.instruction,
    ord.status,
    ord.acknowledged_by,
    CONCAT(ack_nurse.first_name, ' ', ack_nurse.last_name) AS acknowledged_by_name,
    ord.acknowledged_at,
    ord.completed_by,
    ord.completed_at,
    ord.created_at
FROM Doctor_Orders ord
INNER JOIN Patients p ON ord.patient_id = p.patient_id
LEFT JOIN Admissions adm ON (adm.patient_id = p.patient_id AND adm.status = 'Admitted')
LEFT JOIN Beds b ON adm.bed_id = b.bed_id
INNER JOIN Staff doc ON ord.doctor_id = doc.staff_id
LEFT JOIN Staff ack_nurse ON ord.acknowledged_by = ack_nurse.staff_id;

-- maleesha --

CREATE OR REPLACE VIEW vw_patient_clinical_timeline AS
SELECT 
    mr.record_id,
    mr.patient_id,
    p.user_id AS patient_user_id,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
    p.dob AS patient_dob,
    p.blood_group,
    p.allergies,
    mr.doctor_id,
    CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS doctor_name,
    doc.specialty AS doctor_specialty,
    d.dept_id,
    d.dept_name AS department_name,
    mr.apt_id,
    a.apt_date,
    a.time_slot,
    a.status AS appointment_status,
    mr.diagnosis,
    mr.clinical_notes,
    mr.created_at AS record_created_at,
    (
        SELECT COUNT(*)
        FROM `Prescriptions` rx
        WHERE rx.record_id = mr.record_id
    ) AS total_prescriptions_count,
    (
        SELECT COUNT(*)
        FROM `Prescriptions` rx
        WHERE rx.record_id = mr.record_id AND LOWER(rx.status) = 'active'
    ) AS active_prescriptions_count
FROM `Medical_Records` mr
JOIN `Patients` p ON mr.patient_id = p.patient_id
LEFT JOIN `Staff` doc ON mr.doctor_id = doc.staff_id
LEFT JOIN `Departments` d ON doc.dept_id = d.dept_id
LEFT JOIN `Appointments` a ON mr.apt_id = a.apt_id;

CREATE OR REPLACE VIEW vw_active_prescriptions_catalog AS
SELECT 
    rx.rx_id,
    rx.record_id,
    mr.patient_id,
    p.user_id AS patient_user_id,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
    p.emergency_contact,
    rx.med_name,
    rx.dosage,
    rx.duration,
    rx.status AS rx_status,
    mr.doctor_id,
    CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS doctor_name,
    doc.specialty AS doctor_specialty,
    d.dept_name AS department_name,
    mr.diagnosis,
    rx.created_at AS prescribed_at,
    rx.updated_at AS last_updated_at
FROM `Prescriptions` rx
JOIN `Medical_Records` mr ON rx.record_id = mr.record_id
JOIN `Patients` p ON mr.patient_id = p.patient_id
LEFT JOIN `Staff` doc ON mr.doctor_id = doc.staff_id
LEFT JOIN `Departments` d ON doc.dept_id = d.dept_id
WHERE LOWER(rx.status) = 'active';

CREATE OR REPLACE VIEW vw_diagnosis_frequency_analytics AS
WITH DiagnosisCounts AS (
    SELECT 
        d.dept_id,
        d.dept_name,
        TRIM(mr.diagnosis) AS diagnosis_title,
        COUNT(mr.record_id) AS case_count,
        COUNT(DISTINCT mr.patient_id) AS unique_patients_count
    FROM `Medical_Records` mr
    JOIN `Staff` doc ON mr.doctor_id = doc.staff_id
    JOIN `Departments` d ON doc.dept_id = d.dept_id
    WHERE mr.diagnosis IS NOT NULL AND TRIM(mr.diagnosis) != ''
    GROUP BY d.dept_id, d.dept_name, TRIM(mr.diagnosis)
)
SELECT 
    dept_id,
    dept_name,
    diagnosis_title,
    case_count,
    unique_patients_count,
    DENSE_RANK() OVER (PARTITION BY dept_id ORDER BY case_count DESC) AS dept_diagnosis_rank
FROM DiagnosisCounts;