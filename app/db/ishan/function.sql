

-- get today's total appointments for a doctor using Users.user_id

DELIMITER //

DROP FUNCTION IF EXISTS Get_Total_Appointment_Count_According_To_Doctor //

CREATE FUNCTION Get_Total_Appointment_Count_According_To_Doctor(
    user_id_input INT
)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE doctor_staff_id INT DEFAULT NULL;
    DECLARE total INT DEFAULT 0;

    -- Find the Staff ID related to the logged-in User ID
    SELECT s.staff_id
    INTO doctor_staff_id
    FROM Users u
    INNER JOIN Staff s
        ON s.user_id = u.user_id
    WHERE u.user_id = user_id_input
      AND LOWER(u.role) = 'doctor'
      AND u.is_active = TRUE
    LIMIT 1;

    -- Return zero when the user is not an active doctor
    IF doctor_staff_id IS NULL THEN
        RETURN 0;
    END IF;

    -- Count today's appointments for the related doctor
    SELECT COUNT(*)
    INTO total
    FROM Appointments
    WHERE doctor_id = doctor_staff_id
      AND DATE(apt_date) = CURDATE();

    RETURN total;
END //

DELIMITER ;



-- get total completed appointments count current date
DELIMITER //
CREATE FUNCTION IF NOT EXISTS Get_Total_Appointment_Count_According_To_Doctor_complted(
    doc_id VARCHAR(10)
)
RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE total INT;

    SELECT COUNT(*)
    INTO total
    FROM appointments
    WHERE doctor_id = doc_id
      AND DATE(apt_date) = CURDATE()
      AND status = 'Completed';

    RETURN total;
END //

DELIMITER ;



-- get total patients count by doctor only status scheduled and cancelled

DELIMITER //

DROP FUNCTION IF EXISTS get_Total_Patients_count_by_docter //

CREATE FUNCTION get_Total_Patients_count_by_docter(
    doc_id INT
)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE total INT;

    SELECT COUNT(patient_id)
    INTO total
    FROM appointments
    WHERE doctor_id = doc_id
      AND status IN ('Scheduled', 'Cancelled');

    RETURN total;
END //

DELIMITER ;
