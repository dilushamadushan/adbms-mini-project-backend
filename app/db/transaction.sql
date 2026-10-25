DROP PROCEDURE IF EXISTS sp_admit_patient_transaction;
DROP PROCEDURE IF EXISTS sp_dispense_prescription_transaction;

DELIMITER //

-- ============================================================================
-- Transaction 1: Atomic Inpatient Admission & Bed Allocation
-- ============================================================================
CREATE PROCEDURE sp_admit_patient_transaction(
    IN p_patient_id INT,
    IN p_ward_id INT,
    IN p_bed_id INT,
    IN p_doctor_id INT,
    IN p_admitted_by INT,
    IN p_reason TEXT,
    IN p_guardian_name VARCHAR(200),
    IN p_guardian_rel VARCHAR(100),
    IN p_guardian_contact VARCHAR(20),
    IN p_gender ENUM('Female', 'Male'),
    OUT p_admission_id INT,
    OUT p_status_message VARCHAR(255)
)
proc_label: BEGIN
    DECLARE v_bed_status VARCHAR(20);
    DECLARE v_current_bed_patient INT;
    DECLARE v_active_admission INT DEFAULT NULL;
    DECLARE v_patient_exists INT DEFAULT 0;
    DECLARE v_doctor_exists INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_admission_id = NULL;
        SET p_status_message = 'Transaction aborted: SQL exception encountered.';
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_patient_exists 
    FROM Patients 
    WHERE patient_id = p_patient_id 
    FOR UPDATE;

    IF v_patient_exists = 0 THEN
        ROLLBACK;
        SET p_status_message = 'Patient record does not exist';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Patient record does not exist';
    END IF;

    SELECT COUNT(*) INTO v_doctor_exists 
    FROM Staff 
    WHERE staff_id = p_doctor_id;

    IF v_doctor_exists = 0 THEN
        ROLLBACK;
        SET p_status_message = 'Admitting doctor does not exist';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Admitting doctor does not exist';
    END IF;

    SELECT a.admission_id INTO v_active_admission
    FROM Admissions a
    LEFT JOIN Discharges d ON d.admission_id = a.admission_id
    WHERE a.patient_id = p_patient_id
      AND (d.admission_id IS NULL OR d.status <> 'Discharged')
    LIMIT 1
    FOR UPDATE;

    IF v_active_admission IS NOT NULL THEN
        ROLLBACK;
        SET p_status_message = 'Patient already has an active, non-discharged admission.';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Integrity violation: Patient already has an active admission.';
    END IF;

    SELECT status, current_patient_id INTO v_bed_status, v_current_bed_patient
    FROM Beds
    WHERE bed_id = p_bed_id AND ward_id = p_ward_id
    FOR UPDATE;

    IF v_bed_status IS NULL THEN
        ROLLBACK;
        SET p_status_message = 'Specified bed was not found in the target ward.';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Specified bed was not found in target ward.';
    END IF;

    IF v_bed_status <> 'Available' OR v_current_bed_patient IS NOT NULL THEN
        ROLLBACK;
        SET p_status_message = CONCAT('Bed ID #', p_bed_id, ' is not available (Current status: ', v_bed_status, ').');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Conflict: Requested bed is currently occupied or undergoing cleaning.';
    END IF;

    INSERT INTO Admissions (
        patient_id, ward_id, bed_id, admitted_doctor_id, admitted_by,
        admitted_at, admission_reason, guardian_name, guardian_relationship,
        guardian_contact, gender, status
    ) VALUES (
        p_patient_id, p_ward_id, p_bed_id, p_doctor_id, p_admitted_by,
        NOW(), p_reason, p_guardian_name, p_guardian_rel,
        p_guardian_contact, p_gender, 'Admitted'
    );

    SET p_admission_id = LAST_INSERT_ID();

    SAVEPOINT sp_admission_created;

    UPDATE Beds
    SET status = 'Occupied',
        current_patient_id = p_patient_id,
        updated_at = NOW()
    WHERE bed_id = p_bed_id;

    INSERT INTO Doctor_Orders (
        patient_id, doctor_id, order_type, instruction,
        status, created_at
    ) VALUES (
        p_patient_id, p_doctor_id, 'Nursing_Care',
        CONCAT('Initial inpatient admission workup: Vitals Q4H, IV access, monitoring in Ward #', p_ward_id),
        'Pending', NOW()
    );

    INSERT INTO Audit_Logs (actor_id, action_type, resource_table, details, timestamp)
    VALUES (
        p_admitted_by,
        'INPATIENT_ADMISSION_COMMITTED',
        'Admissions',
        JSON_OBJECT(
            'admission_id', p_admission_id,
            'patient_id', p_patient_id,
            'ward_id', p_ward_id,
            'bed_id', p_bed_id,
            'doctor_id', p_doctor_id
        ),
        NOW()
    );

    COMMIT;
    SET p_status_message = 'Patient admitted and bed allocated successfully.';
END //


-- ============================================================================
-- Transaction 2: Atomic Prescription Dispensation & Medicine Stock Accounting
-- ============================================================================
CREATE PROCEDURE sp_dispense_prescription_transaction(
    IN p_rx_id INT,
    IN p_medicine_id INT,
    IN p_pharmacist_id INT,
    IN p_quantity INT,
    OUT p_dispense_id INT,
    OUT p_total_price DECIMAL(10,2),
    OUT p_status_message VARCHAR(255)
)
proc_label: BEGIN
    DECLARE v_unit_price DECIMAL(10,2);
    DECLARE v_med_name VARCHAR(100);
    DECLARE v_patient_id INT;
    DECLARE v_record_id INT;
    DECLARE v_total_stock INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_dispense_id = NULL;
        SET p_total_price = 0.00;
        SET p_status_message = 'Transaction aborted: SQL exception encountered during dispensation.';
        RESIGNAL;
    END;

    START TRANSACTION;

    IF p_quantity <= 0 THEN
        ROLLBACK;
        SET p_status_message = 'Requested dispensation quantity must be greater than zero.';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid quantity: Dispense quantity must be positive.';
    END IF;

    SELECT p.record_id, mr.patient_id
    INTO v_record_id, v_patient_id
    FROM Prescriptions p
    JOIN Medical_Records mr ON mr.record_id = p.record_id
    WHERE p.rx_id = p_rx_id
    FOR UPDATE;

    IF v_record_id IS NULL THEN
        ROLLBACK;
        SET p_status_message = 'Prescription record not found.';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Prescription record does not exist.';
    END IF;

    SELECT med_name, unit_price
    INTO v_med_name, v_unit_price
    FROM Medicines
    WHERE medicine_id = p_medicine_id
    FOR UPDATE;

    IF v_unit_price IS NULL THEN
        ROLLBACK;
        SET p_status_message = 'Medicine catalog record not found.';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Medicine not found in pharmacy inventory.';
    END IF;

    SELECT 
        COALESCE((SELECT SUM(quantity) FROM Stock_Receipts WHERE medicine_id = p_medicine_id), 0) -
        COALESCE((SELECT SUM(quantity) FROM Dispensations WHERE medicine_id = p_medicine_id), 0)
    INTO v_total_stock;

    IF v_total_stock < p_quantity THEN
        ROLLBACK;
        SET p_status_message = CONCAT('Insufficient stock for ', v_med_name, '. In stock: ', v_total_stock, ', Requested: ', p_quantity);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient pharmacy inventory stock.';
    END IF;

    SET p_total_price = ROUND(v_unit_price * p_quantity, 2);

    INSERT INTO Dispensations (
        rx_id, medicine_id, pharmacist_id, quantity,
        total_price, dispensed_at
    ) VALUES (
        p_rx_id, p_medicine_id, p_pharmacist_id, p_quantity,
        p_total_price, NOW()
    );

    SET p_dispense_id = LAST_INSERT_ID();

    SAVEPOINT sp_dispensation_recorded;

    INSERT INTO Medication_Administration_Records (
        rx_id, patient_id, administered_by, scheduled_time,
        status, notes, administered_at
    ) VALUES (
        p_rx_id, v_patient_id, p_pharmacist_id, DATE_FORMAT(NOW(), '%H:%i'),
        'Given', CONCAT('Dispensed by Pharmacy (Staff #', p_pharmacist_id, ') - Qty: ', p_quantity),
        NOW()
    );

    INSERT INTO Audit_Logs (actor_id, action_type, resource_table, details, timestamp)
    VALUES (
        p_pharmacist_id,
        'MEDICINE_DISPENSED_TRANSACTION',
        'Dispensations',
        JSON_OBJECT(
            'dispense_id', p_dispense_id,
            'rx_id', p_rx_id,
            'medicine_id', p_medicine_id,
            'quantity', p_quantity,
            'total_price', p_total_price
        ),
        NOW()
    );

    COMMIT;
    SET p_status_message = CONCAT('Dispensed ', p_quantity, ' unit(s) of ', v_med_name, ' successfully ($', p_total_price, ').');
END //

DELIMITER ;
