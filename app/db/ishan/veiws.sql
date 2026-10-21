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