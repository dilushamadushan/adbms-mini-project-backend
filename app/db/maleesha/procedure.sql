-- =====================================================================
-- Clinical & Patient Module: Stored Procedures
-- Patient Medical History, Prescription Tracking & Status Management
-- Database Engine: MySQL 8.0+ (InnoDB)
-- =====================================================================

USE `hms`;

-- ---------------------------------------------------------------------
-- Procedure 1: sp_get_patient_medical_history
-- WHAT: Returns complete medical record history for a patient including
--       diagnoses, clinical notes, attending physicians, and appointment dates.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS `sp_get_patient_medical_history`;

DELIMITER $$

CREATE PROCEDURE `sp_get_patient_medical_history`(
    IN p_patient_id INT
)
BEGIN
    -- Validate that patient exists
    IF NOT EXISTS (
        SELECT 1 FROM `Patients`
        WHERE `patient_id` = p_patient_id OR `user_id` = p_patient_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Patient not found with the specified ID.';
    END IF;

    -- Return medical record history with physician and department details
    SELECT 
        mr.record_id,
        mr.patient_id,
        CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
        mr.doctor_id,
        CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS doctor_name,
        doc.specialty AS doctor_specialty,
        d.dept_name AS department_name,
        mr.apt_id,
        a.apt_date,
        a.time_slot,
        mr.diagnosis,
        mr.clinical_notes,
        mr.created_at,
        mr.updated_at
    FROM `Medical_Records` mr
    JOIN `Patients` p ON mr.patient_id = p.patient_id
    LEFT JOIN `Staff` doc ON mr.doctor_id = doc.staff_id
    LEFT JOIN `Departments` d ON doc.dept_id = d.dept_id
    LEFT JOIN `Appointments` a ON mr.apt_id = a.apt_id
    WHERE (mr.patient_id = p_patient_id OR p.user_id = p_patient_id)
    ORDER BY mr.created_at DESC, mr.record_id DESC;
END$$

DELIMITER ;


-- ---------------------------------------------------------------------
-- Procedure 2: sp_get_patient_rx_summary
-- WHAT: Aggregates prescription statistics (total, active, inactive)
--       and returns all associated medications with their status.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS `sp_get_patient_rx_summary`;

DELIMITER $$

CREATE PROCEDURE `sp_get_patient_rx_summary`(
    IN p_patient_id INT
)
BEGIN
    -- Validate that patient exists
    IF NOT EXISTS (
        SELECT 1 FROM `Patients`
        WHERE `patient_id` = p_patient_id OR `user_id` = p_patient_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Patient not found with the specified ID.';
    END IF;

    -- Result Set 1: Prescription Totals Summary
    SELECT 
        COUNT(rx.rx_id) AS total_prescriptions,
        SUM(CASE WHEN LOWER(rx.status) = 'active' THEN 1 ELSE 0 END) AS active_prescriptions,
        SUM(CASE WHEN LOWER(rx.status) != 'active' THEN 1 ELSE 0 END) AS inactive_prescriptions
    FROM `Prescriptions` rx
    JOIN `Medical_Records` mr ON rx.record_id = mr.record_id
    JOIN `Patients` p ON mr.patient_id = p.patient_id
    WHERE (mr.patient_id = p_patient_id OR p.user_id = p_patient_id);

    -- Result Set 2: Detailed Prescription List
    SELECT 
        rx.rx_id,
        rx.record_id,
        rx.med_name,
        rx.dosage,
        rx.duration,
        rx.status,
        CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS prescribing_doctor,
        mr.diagnosis,
        rx.created_at,
        rx.updated_at
    FROM `Prescriptions` rx
    JOIN `Medical_Records` mr ON rx.record_id = mr.record_id
    JOIN `Patients` p ON mr.patient_id = p.patient_id
    LEFT JOIN `Staff` doc ON mr.doctor_id = doc.staff_id
    WHERE (mr.patient_id = p_patient_id OR p.user_id = p_patient_id)
    ORDER BY rx.created_at DESC, rx.rx_id DESC;
END$$

DELIMITER ;


-- ---------------------------------------------------------------------
-- Procedure 3: sp_deactivate_prescription
-- WHAT: Safely transitions a prescription to 'Inactive' within an ACID
--       transaction and logs an entry to the Audit_Logs table.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS `sp_deactivate_prescription`;

DELIMITER $$

CREATE PROCEDURE `sp_deactivate_prescription`(
    IN p_rx_id INT,
    IN p_actor_user_id INT
)
proc_label: BEGIN
    DECLARE v_current_status VARCHAR(50);
    DECLARE v_record_id      INT;

    -- SQL Exception rollback handler
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Transaction failed: unable to deactivate prescription.';
    END;

    -- Validate prescription existence
    SELECT status, record_id INTO v_current_status, v_record_id
    FROM `Prescriptions`
    WHERE `rx_id` = p_rx_id
    LIMIT 1;

    IF v_current_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Prescription not found with the specified ID.';
    END IF;

    IF v_current_status = 'Inactive' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Prescription is already inactive.';
    END IF;

    START TRANSACTION;

        -- Update status
        UPDATE `Prescriptions`
        SET `status` = 'Inactive',
            `updated_at` = NOW()
        WHERE `rx_id` = p_rx_id;

        -- Audit log entry
        INSERT INTO `Audit_Logs` (
            actor_id,
            action_type,
            resource_table,
            details,
            timestamp
        )
        VALUES (
            p_actor_user_id,
            'PRESCRIPTION_DEACTIVATED',
            'Prescriptions',
            JSON_OBJECT(
                'rx_id', p_rx_id,
                'record_id', v_record_id,
                'previous_status', v_current_status,
                'new_status', 'Inactive'
            ),
            NOW()
        );

    COMMIT;

    SELECT p_rx_id AS rx_id, 'Inactive' AS status, 'Prescription deactivated successfully' AS message;
END$$

DELIMITER ;
