DROP FUNCTION IF EXISTS fn_is_token_active;
DROP FUNCTION IF EXISTS fn_calculate_provider_avg_time; 
DROP FUNCTION IF EXISTS fn_get_workload_level; 
DROP FUNCTION IF EXISTS fn_get_audit_risk; 
DROP FUNCTION IF EXISTS fn_bed_occupancy_pct; 
DROP FUNCTION IF EXISTS fn_recep_get_all_patients;
DROP FUNCTION IF EXISTS fn_calculate_medicine_status;
DROP FUNCTION IF EXISTS fn_get_total_inventory_value;

DROP FUNCTION IF EXISTS Get_Total_Appointment_Count_According_To_Doctor;
DROP FUNCTION IF EXISTS Get_Total_Appointment_Count_According_To_Doctor_complted;
DROP FUNCTION IF EXISTS get_Total_Patients_count_by_docter;


DELIMITER //

-- TG/1407 --

CREATE FUNCTION fn_is_token_active(p_token_hash VARCHAR(255))
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_count INT;
    SELECT COUNT(*) INTO v_count
    FROM Refresh_Tokens
    WHERE token_hash = p_token_hash
      AND revoked = FALSE
      AND expires_at > NOW();
    RETURN (v_count > 0);
END //

CREATE FUNCTION fn_calculate_provider_avg_time(p_doctor_id INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_dept_name VARCHAR(100);
    DECLARE v_specialty VARCHAR(100);

    SELECT d.dept_name, s.specialty INTO v_dept_name, v_specialty
    FROM Staff s
    LEFT JOIN Departments d ON s.dept_id = d.dept_id
    WHERE s.staff_id = p_doctor_id;

    IF v_dept_name = 'Emergency Medicine' OR v_specialty LIKE '%Emergency%' THEN
        RETURN 18;
    ELSEIF v_dept_name = 'Cardiology' OR v_specialty LIKE '%Cardio%' THEN
        RETURN 22;
    ELSEIF v_dept_name = 'General Medicine' OR v_specialty LIKE '%Physician%' OR v_specialty LIKE '%General%' THEN
        RETURN 15;
    ELSEIF v_dept_name = 'Orthopedics' THEN
        RETURN 20;
    ELSE
        RETURN 15 + (p_doctor_id * 3) % 12;
    END IF;
END //

CREATE FUNCTION fn_get_workload_level(p_count INT, p_pct DECIMAL(5,2))
RETURNS VARCHAR(20)
DETERMINISTIC
CONTAINS SQL
BEGIN
    IF p_pct >= 30.0 OR p_count >= 100 THEN
        RETURN 'Critical';
    ELSEIF p_pct >= 20.0 OR p_count >= 50 THEN
        RETURN 'High';
    ELSEIF p_pct >= 10.0 OR p_count >= 20 THEN
        RETURN 'Moderate';
    ELSE
        RETURN 'Low';
    END IF;
END //

CREATE FUNCTION fn_get_audit_risk(p_action VARCHAR(100), p_details JSON)
RETURNS VARCHAR(10)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_risk_override VARCHAR(10);
    DECLARE v_action_upper VARCHAR(100);

    IF p_details IS NOT NULL THEN
        SET v_risk_override = UPPER(TRIM(BOTH '"' FROM JSON_UNQUOTE(JSON_EXTRACT(p_details, '$.risk'))));
        IF v_risk_override IN ('HIGH', 'MEDIUM', 'LOW') THEN
            RETURN v_risk_override;
        END IF;
    END IF;

    SET v_action_upper = UPPER(COALESCE(p_action, ''));

    IF v_action_upper LIKE '%DELETE%' 
       OR v_action_upper LIKE '%DROP%' 
       OR v_action_upper LIKE '%REVOKE%'
       OR v_action_upper LIKE '%PURGE%'
       OR v_action_upper LIKE '%UNAUTHORIZED%'
       OR v_action_upper LIKE '%BREACH%'
       OR v_action_upper LIKE '%FAIL%' THEN
        RETURN 'HIGH';

    ELSEIF v_action_upper LIKE '%UPDATE%' 
       OR v_action_upper LIKE '%MODIFY%' 
       OR v_action_upper LIKE '%PASSWORD%'
       OR v_action_upper LIKE '%ROLE%'
       OR v_action_upper LIKE '%STATUS%'
       OR v_action_upper LIKE '%USER%'
       OR v_action_upper LIKE '%DIAGNOSIS%'
       OR v_action_upper LIKE '%PRESCRIPTION%'
       OR v_action_upper LIKE '%CREATE%' THEN
        RETURN 'MEDIUM';

    ELSE
        RETURN 'LOW';
    END IF;
END //

CREATE FUNCTION fn_bed_occupancy_pct(p_ward_id INT)
RETURNS DECIMAL(5,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_occupied INT DEFAULT 0;

    IF p_ward_id IS NOT NULL THEN
        SELECT COUNT(*) INTO v_total FROM Beds WHERE ward_id = p_ward_id;
        SELECT COUNT(*) INTO v_occupied FROM Beds WHERE ward_id = p_ward_id AND status = 'Occupied';
    ELSE
        SELECT COUNT(*) INTO v_total FROM Beds;
        SELECT COUNT(*) INTO v_occupied FROM Beds WHERE status = 'Occupied';
    END IF;

    IF v_total = 0 THEN
        RETURN 0.00;
    END IF;

    RETURN ROUND((v_occupied * 100.0) / v_total, 2);
END //

-- Chavi --
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

-- thimira --
CREATE FUNCTION fn_calculate_medicine_status(
    p_stock INT,
    p_reorder INT,
    p_expiry DATE
)
RETURNS VARCHAR(30)
DETERMINISTIC
NO SQL
BEGIN
    IF p_stock <= 0 THEN
        RETURN 'OUT_OF_STOCK';
    ELSEIF p_expiry <= CURDATE() THEN
        RETURN 'EXPIRED';
    ELSEIF p_expiry <= DATE_ADD(CURDATE(), INTERVAL 30 DAY) THEN
        RETURN 'EXPIRING_SOON';
    ELSEIF p_stock <= p_reorder THEN
        RETURN 'LOW_STOCK';
    ELSE
        RETURN 'IN_STOCK';
    END IF;
END //

CREATE FUNCTION fn_get_total_inventory_value()
RETURNS DECIMAL(12,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE total_val DECIMAL(12,2) DEFAULT 0.00;

    SELECT COALESCE(SUM(unit_price * stock_qty), 0.00)
    INTO total_val
    FROM Medicines
    WHERE is_active = TRUE;

    RETURN total_val;
END //








-- ishan --

-- get today's total appointments for a doctor using Users.user_id
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

-- get total completed appointments count current date
CREATE FUNCTION Get_Total_Appointment_Count_According_To_Doctor_complted(
    doc_id VARCHAR(10)
)
RETURNS INT
DETERMINISTIC
READS SQL DATA
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

-- get total patients count by doctor only status scheduled and cancelled
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

