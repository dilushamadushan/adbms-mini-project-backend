-- =====================================================================
-- Clinical & Patient Module: User-Defined Functions (UDFs)
-- Clinical Metric Calculations & Medication Check Utilities
-- Database Engine: MySQL 8.0+ (InnoDB)
-- =====================================================================

USE `hms`;

-- ---------------------------------------------------------------------
-- Function 1: fn_patient_active_rx_count
-- WHAT: Returns the total count of currently 'Active' prescriptions for a patient.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS `fn_patient_active_rx_count`;

DELIMITER $$

CREATE FUNCTION `fn_patient_active_rx_count`(
    p_patient_id INT
)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_count INT DEFAULT 0;

    SELECT COUNT(rx.rx_id) INTO v_count
    FROM `Prescriptions` rx
    JOIN `Medical_Records` mr ON rx.record_id = mr.record_id
    WHERE mr.patient_id = p_patient_id
      AND LOWER(rx.status) = 'active';

    RETURN v_count;
END$$

DELIMITER ;


-- ---------------------------------------------------------------------
-- Function 2: fn_patient_total_visits
-- WHAT: Returns the total number of clinical consultation visits recorded
--       in Medical_Records for a given patient.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS `fn_patient_total_visits`;

DELIMITER $$

CREATE FUNCTION `fn_patient_total_visits`(
    p_patient_id INT
)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT DEFAULT 0;

    SELECT COUNT(record_id) INTO v_total
    FROM `Medical_Records`
    WHERE `patient_id` = p_patient_id;

    RETURN v_total;
END$$

DELIMITER ;


-- ---------------------------------------------------------------------
-- Function 3: fn_has_active_prescription_for_med
-- WHAT: Checks if a patient is currently taking a specific medication
--       to prevent duplicate prescription issuance.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS `fn_has_active_prescription_for_med`;

DELIMITER $$

CREATE FUNCTION `fn_has_active_prescription_for_med`(
    p_patient_id INT,
    p_med_name   VARCHAR(100)
)
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_exists BOOLEAN DEFAULT FALSE;

    IF EXISTS (
        SELECT 1
        FROM `Prescriptions` rx
        JOIN `Medical_Records` mr ON rx.record_id = mr.record_id
        WHERE mr.patient_id = p_patient_id
          AND LOWER(rx.status) = 'active'
          AND LOWER(TRIM(rx.med_name)) = LOWER(TRIM(p_med_name))
    ) THEN
        SET v_exists = TRUE;
    END IF;

    RETURN v_exists;
END$$

DELIMITER ;
