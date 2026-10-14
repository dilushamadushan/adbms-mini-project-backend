
-- get today appointments count
DELIMITER //
CREATE FUNCTION IF NOT EXISTS Get_Total_Appointment_Count_According_To_Doctor(
    doc_id VARCHAR(10)
)
RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE total INT;
    
    SELECT COUNT(patient_id)
    INTO total
    FROM appointments
    WHERE doctor_id = doc_id
      AND DATE(apt_date) = CURDATE(); 
      
    RETURN total;
END //
DELIMITER ;