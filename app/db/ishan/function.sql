

-- get today only scheduled appointments count

DELIMITER //

DROP FUNCTION IF EXISTS Get_Total_Appointment_Count_According_To_Doctor //

CREATE FUNCTION Get_Total_Appointment_Count_According_To_Doctor(
    doc_id INT
)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE total INT;

    SELECT COUNT(*)
    INTO total
    FROM appointments
    WHERE doctor_id = doc_id
      AND DATE(apt_date) = CURDATE()
      AND status = 'Scheduled';

    RETURN COALESCE(total, 0);
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

