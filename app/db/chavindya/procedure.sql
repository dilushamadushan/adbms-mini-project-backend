USE hms;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_recep_get_appointments //
CREATE PROCEDURE sp_recep_get_appointments(
    IN p_appointment_id INT,
    IN p_patient_id INT,
    IN p_appointment_date DATE,
    IN p_patient_name VARCHAR(201)
)
BEGIN
    SELECT apt_id, patient_id, patient_name, doctor_id, doctor_name,
           dept_id, dept_name, apt_date, time_slot, status
    FROM vw_recep_appointments
    WHERE (p_appointment_id IS NULL OR apt_id = p_appointment_id)
      AND (p_patient_id IS NULL OR patient_id = p_patient_id)
      AND (p_appointment_date IS NULL OR apt_date = p_appointment_date)
      AND (
          p_patient_name IS NULL
          OR TRIM(p_patient_name) = ''
          OR patient_name LIKE CONCAT('%', TRIM(p_patient_name), '%')
      )
    ORDER BY apt_date, time_slot;
END //

DROP PROCEDURE IF EXISTS sp_recep_search_patients_by_name //
CREATE PROCEDURE sp_recep_search_patients_by_name(IN p_name VARCHAR(201))
BEGIN
    DECLARE v_name VARCHAR(201);
    DECLARE v_first_name VARCHAR(100);
    DECLARE v_last_name VARCHAR(100);

    SET v_name = TRIM(p_name);
    SET v_first_name = SUBSTRING_INDEX(v_name, ' ', 1);
    SET v_last_name = TRIM(SUBSTRING(v_name, CHAR_LENGTH(v_first_name) + 1));

    SELECT p.patient_id, p.user_id, u.username, u.email,
           p.first_name, p.last_name, p.dob, p.blood_group,
           p.emergency_contact, p.allergies
    FROM Patients p
    JOIN Users u ON u.user_id = p.user_id
    WHERE LOWER(u.role) = 'patient'
      AND (
          (
              p.first_name LIKE CONCAT(v_first_name, '%')
              AND (v_last_name = '' OR p.last_name LIKE CONCAT(v_last_name, '%'))
          )
          OR (
              v_last_name = ''
              AND p.last_name LIKE CONCAT(v_first_name, '%')
          )
      )
    ORDER BY p.last_name, p.first_name;
END //

DELIMITER ;