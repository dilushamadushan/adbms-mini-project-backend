USE dmd;

DELIMITER //

DROP PROCEDURE IF EXISTS GetAllPatients; //

CREATE PROCEDURE GetAllPatients()
BEGIN
    SELECT 
        p.patient_id,
        p.first_name,
        p.last_name,
        p.dob,
        p.blood_group,
        p.emergency_contact,
        p.allergies,
        u.user_id,
        u.username,
        u.role,
        u.is_active,
        p.created_at,
        p.updated_at
    FROM Patients p
    INNER JOIN Users u ON p.user_id = u.user_id;
END //

DELIMITER ;
