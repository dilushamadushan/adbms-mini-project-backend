-- =====================================================================
-- Clinical & Patient Module: Views & Analytical Queries
-- Clinical Timelines, Active Medication Catalogs & Diagnosis Analytics
-- Database Engine: MySQL 8.0+ (InnoDB)
-- =====================================================================

USE `hms`;

-- ---------------------------------------------------------------------
-- View 1: vw_patient_clinical_timeline
-- WHAT: Complete chronological timeline of all patient visits, medical
--       records, diagnoses, clinical notes, and physician departments.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW `vw_patient_clinical_timeline` AS
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


-- ---------------------------------------------------------------------
-- View 2: vw_active_prescriptions_catalog
-- WHAT: Live catalog of active medications linked to patients and doctors,
--       displaying medication details, dosage, and duration.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW `vw_active_prescriptions_catalog` AS
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


-- ---------------------------------------------------------------------
-- View 3: vw_diagnosis_frequency_analytics
-- WHAT: Advanced analytical view using window functions to rank the most
--       frequent clinical diagnoses across hospital departments.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW `vw_diagnosis_frequency_analytics` AS
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
