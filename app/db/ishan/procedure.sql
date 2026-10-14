-- DOCTER//////////////////////////////////////////////////

-- //get apointments of a doctor according to docter id current day--

DELIMITER //

CREATE PROCEDURE IF NOT EXISTS GetAppointmentsByDoctor(IN p_doctor_id INT)
BEGIN
    SELECT
        a.apt_id,
        a.patient_id,
        CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
        p.dob,
        p.blood_group,
        p.allergies,
        a.dept_id,
        d.dept_name,
        a.apt_date,
        TIME_FORMAT(a.time_slot, '%H:%i')      AS time_slot,
        a.status
    FROM Appointments a
    INNER JOIN Patients    p ON a.patient_id = p.patient_id
    INNER JOIN Departments d ON a.dept_id    = d.dept_id
    WHERE a.doctor_id = p_doctor_id
      AND DATE(a.apt_date) = CURDATE()
    ORDER BY a.apt_date DESC, a.time_slot;
END //





-- //get appointment history of a doctor according to doctor id--



DELIMITER //
CREATE PROCEDURE GetAppointmentHistoryByDoctor(IN p_doctor_id INT)
BEGIN
    SELECT
        a.apt_id,
        a.patient_id,
        CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
        p.dob,
        p.blood_group,
        p.allergies,
        a.dept_id,
        d.dept_name,
        a.apt_date,
        TIME_FORMAT(a.time_slot, '%H:%i')      AS time_slot,
        a.status
    FROM Appointments a
    INNER JOIN Patients    p ON a.patient_id = p.patient_id
    INNER JOIN Departments d ON a.dept_id    = d.dept_id
    WHERE a.doctor_id = p_doctor_id
      AND DATE(a.apt_date) < CURDATE() -- Filters for historical appointments strictly before today
    ORDER BY a.apt_date DESC, a.time_slot;
END //

DELIMITER ;