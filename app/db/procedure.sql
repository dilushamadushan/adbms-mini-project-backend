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

DELIMITER //

DROP PROCEDURE IF EXISTS GetAllStaff; //

CREATE PROCEDURE GetAllStaff()
BEGIN
    SELECT 
        s.staff_id,
        s.first_name,
        s.last_name,
        s.dept_id,
        s.specialty,
        u.user_id,
        u.username,
        u.role,
        u.is_active
    FROM Staff s
    INNER JOIN Users u ON s.user_id = u.user_id;
END //

DELIMITER ;