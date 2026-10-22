USE hms;


DELIMITER //

DROP FUNCTION IF EXISTS fn_check_allergy_conflict //

CREATE FUNCTION fn_check_allergy_conflict(
    p_patient_id INT,
    p_medicine_name VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_allergies TEXT;
    DECLARE v_conflict BOOLEAN DEFAULT FALSE;

    SELECT allergies INTO v_allergies
    FROM Patients
    WHERE patient_id = p_patient_id;

    IF v_allergies IS NOT NULL AND v_allergies != '' AND v_allergies != 'None' THEN
        IF INSTR(LOWER(p_medicine_name), LOWER(v_allergies)) > 0 
           OR INSTR(LOWER(v_allergies), LOWER(p_medicine_name)) > 0 THEN
            SET v_conflict = TRUE;
        END IF;
    END IF;

    RETURN v_conflict;
END //

DELIMITER ;


DELIMITER //

DROP FUNCTION IF EXISTS fn_calc_patient_io_balance //

CREATE FUNCTION fn_calc_patient_io_balance(
    p_patient_id INT,
    p_date DATE
)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total_intake INT DEFAULT 0;
    DECLARE v_total_output INT DEFAULT 0;

    SELECT COALESCE(SUM(volume_ml), 0) INTO v_total_intake
    FROM Intake_Output_Logs
    WHERE patient_id = p_patient_id
      AND io_type = 'Intake'
      AND DATE(recorded_at) = COALESCE(p_date, CURDATE());

    SELECT COALESCE(SUM(volume_ml), 0) INTO v_total_output
    FROM Intake_Output_Logs
    WHERE patient_id = p_patient_id
      AND io_type = 'Output'
      AND DATE(recorded_at) = COALESCE(p_date, CURDATE());

    RETURN (v_total_intake - v_total_output);
END //

DELIMITER ;


DELIMITER //

DROP FUNCTION IF EXISTS fn_patient_vitals_status //

CREATE FUNCTION fn_patient_vitals_status(p_patient_id INT)
RETURNS VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_bp VARCHAR(20);
    DECLARE v_pulse INT;
    DECLARE v_temp DECIMAL(5,2);
    DECLARE v_spo2 INT;
    DECLARE v_resp INT;
    DECLARE v_systolic INT DEFAULT 120;
    DECLARE v_status VARCHAR(20) DEFAULT 'STABLE';

    SELECT bp, pulse, temperature, spo2, resp_rate
    INTO v_bp, v_pulse, v_temp, v_spo2, v_resp
    FROM Vitals_Log
    WHERE patient_id = p_patient_id
    ORDER BY recorded_at DESC
    LIMIT 1;

    IF v_pulse IS NULL THEN
        RETURN 'STABLE';
    END IF;

    IF v_bp IS NOT NULL AND INSTR(v_bp, '/') > 0 THEN
        SET v_systolic = CAST(SUBSTRING_INDEX(v_bp, '/', 1) AS UNSIGNED);
    END IF;

    IF (v_spo2 IS NOT NULL AND v_spo2 < 92)
       OR (v_systolic >= 160 OR v_systolic <= 85)
       OR (v_pulse >= 120 OR v_pulse <= 45)
       OR (v_temp >= 102.0)
       OR (v_resp IS NOT NULL AND (v_resp >= 28 OR v_resp <= 8)) THEN
        SET v_status = 'CRITICAL';
    ELSEIF (v_spo2 IS NOT NULL AND v_spo2 <= 94)
       OR (v_systolic >= 135)
       OR (v_pulse >= 95)
       OR (v_temp >= 99.5)
       OR (v_resp IS NOT NULL AND (v_resp >= 22 OR v_resp <= 10)) THEN
        SET v_status = 'MODERATE';
    ELSE
        SET v_status = 'STABLE';
    END IF;

    RETURN v_status;
END //

DELIMITER ;


DELIMITER //

DROP FUNCTION IF EXISTS fn_ward_occupancy_rate //

CREATE FUNCTION fn_ward_occupancy_rate(p_ward_id INT)
RETURNS DECIMAL(5,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_occupied INT DEFAULT 0;
    DECLARE v_pct DECIMAL(5,2) DEFAULT 0.00;

    SELECT total_beds INTO v_total FROM Wards WHERE ward_id = p_ward_id;
    SELECT COUNT(*) INTO v_occupied FROM Beds WHERE ward_id = p_ward_id AND status = 'Occupied';

    IF v_total > 0 THEN
        SET v_pct = ROUND((v_occupied * 100.0) / v_total, 2);
    END IF;

    RETURN v_pct;
END //

DELIMITER ;
