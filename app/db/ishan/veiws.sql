-------------docter-------------------

-- //get  all departments

CREATE OR REPLACE VIEW vw_ward_names AS
SELECT ward_name
FROM wards
ORDER BY ward_name;

-- //get all admissions data

CREATE OR REPLACE VIEW vw_admissions_data AS
SELECT admission_id, patient_id, ward_id, bed_id, admitted_doctor_id, admitted_by,
       admitted_at, admission_reason, guardian_name, guardian_relationship,
       guardian_contact, gender, status
FROM admissions;


-- Medicine list for the doctor's dropdown.
-- Returns the id, name and generic name of every medicine,
-- sorted by name.
-- =====================================================
CREATE OR REPLACE VIEW `vw_doctor_medicine_list` AS
SELECT medicine_id, med_name, generic_name
FROM medicines
ORDER BY med_name;


-- Gets patient and appointment details for the doctor's lab-order page.

DROP VIEW IF EXISTS vw_lab_order_patient_details;

CREATE VIEW vw_lab_order_patient_details AS
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

SELECT *
FROM vw_lab_order_patient_details;




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
    
    
    
    SELECT *
FROM vw_current_admitted_patients;



















-----------------------patient------------------------------------------


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