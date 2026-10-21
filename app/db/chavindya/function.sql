USE hms;

DELIMITER //

DROP FUNCTION IF EXISTS fn_recep_get_all_patients //
CREATE FUNCTION fn_recep_get_all_patients()
RETURNS JSON
READS SQL DATA
BEGIN
    DECLARE v_patients JSON;

    SELECT COALESCE(
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'patient_id', p.patient_id,
                'user_id', p.user_id,
                'username', u.username,
                'email', u.email,
                'first_name', p.first_name,
                'last_name', p.last_name,
                'dob', p.dob,
                'blood_group', p.blood_group,
                'emergency_contact', p.emergency_contact,
                'allergies', p.allergies
            )
        ),
        JSON_ARRAY()
    )
    INTO v_patients
    FROM Patients p
    JOIN Users u ON u.user_id = p.user_id
    WHERE LOWER(u.role) = 'patient';

    RETURN v_patients;
END //

DELIMITER ;