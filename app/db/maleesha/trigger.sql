-- =====================================================================
-- Clinical & Patient Module: Event-Driven Triggers
-- Automated Patient Notifications on Medical Records & Prescriptions
-- Database Engine: MySQL 8.0+ (InnoDB)
-- =====================================================================

USE `hms`;

-- ---------------------------------------------------------------------
-- Trigger 1: Notify Patient When a New Medical Record is Added
-- WHAT: Automatically pushes a notification to the target patient's user account
--       whenever an attending physician enters a medical record.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS `trg_patient_notify_on_medical_record`;

DELIMITER $$

CREATE TRIGGER `trg_patient_notify_on_medical_record`
AFTER INSERT ON `Medical_Records`
FOR EACH ROW
BEGIN
    DECLARE v_patient_user_id INT DEFAULT NULL;
    DECLARE v_doctor_name     VARCHAR(150) DEFAULT NULL;

    -- Resolve the patient's User ID from Patients table
    SELECT user_id INTO v_patient_user_id
    FROM `Patients`
    WHERE `patient_id` = NEW.patient_id
    LIMIT 1;

    -- Resolve the prescribing doctor's display name
    SELECT CONCAT(first_name, ' ', last_name) INTO v_doctor_name
    FROM `Staff`
    WHERE `staff_id` = NEW.doctor_id
    LIMIT 1;

    -- Insert active notification for the patient
    IF v_patient_user_id IS NOT NULL THEN
        INSERT INTO `Notifications` (
            title,
            message,
            type,
            target_role,
            target_user_id,
            is_read,
            details,
            created_at
        )
        VALUES (
            'New Medical Record Available',
            CONCAT('Dr. ', COALESCE(v_doctor_name, 'Your doctor'), ' has added a new medical consultation record for your visit.'),
            'INFO',
            'patient',
            v_patient_user_id,
            FALSE,
            JSON_OBJECT(
                'record_id', NEW.record_id,
                'patient_id', NEW.patient_id,
                'doctor_id', NEW.doctor_id,
                'diagnosis', NEW.diagnosis
            ),
            NOW()
        );
    END IF;
END$$

DELIMITER ;


-- ---------------------------------------------------------------------
-- Trigger 2: Notify Patient When a New Prescription is Issued
-- WHAT: Automatically alerts the patient with details of the prescribed
--       medication and dosage when a doctor writes a prescription.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS `trg_patient_notify_on_prescription`;

DELIMITER $$

CREATE TRIGGER `trg_patient_notify_on_prescription`
AFTER INSERT ON `Prescriptions`
FOR EACH ROW
BEGIN
    DECLARE v_patient_id      INT DEFAULT NULL;
    DECLARE v_patient_user_id INT DEFAULT NULL;
    DECLARE v_doctor_id       INT DEFAULT NULL;
    DECLARE v_doctor_name     VARCHAR(150) DEFAULT NULL;

    -- Resolve the associated patient and doctor through the parent Medical Record
    SELECT patient_id, doctor_id INTO v_patient_id, v_doctor_id
    FROM `Medical_Records`
    WHERE `record_id` = NEW.record_id
    LIMIT 1;

    -- Resolve the patient's User ID
    IF v_patient_id IS NOT NULL THEN
        SELECT user_id INTO v_patient_user_id
        FROM `Patients`
        WHERE `patient_id` = v_patient_id
        LIMIT 1;
    END IF;

    -- Resolve the doctor's name
    IF v_doctor_id IS NOT NULL THEN
        SELECT CONCAT(first_name, ' ', last_name) INTO v_doctor_name
        FROM `Staff`
        WHERE `staff_id` = v_doctor_id
        LIMIT 1;
    END IF;

    -- Insert active notification for the patient
    IF v_patient_user_id IS NOT NULL THEN
        INSERT INTO `Notifications` (
            title,
            message,
            type,
            target_role,
            target_user_id,
            is_read,
            details,
            created_at
        )
        VALUES (
            'New Prescription Issued',
            CONCAT('Dr. ', COALESCE(v_doctor_name, 'Your doctor'), ' prescribed ', NEW.med_name, ' (', NEW.dosage, ') for you.'),
            'INFO',
            'patient',
            v_patient_user_id,
            FALSE,
            JSON_OBJECT(
                'rx_id', NEW.rx_id,
                'record_id', NEW.record_id,
                'med_name', NEW.med_name,
                'dosage', NEW.dosage,
                'duration', NEW.duration,
                'status', NEW.status
            ),
            NOW()
        );
    END IF;
END$$

DELIMITER ;
