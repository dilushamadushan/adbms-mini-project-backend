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