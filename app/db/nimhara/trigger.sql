USE hms;


DELIMITER //

DROP TRIGGER IF EXISTS trg_after_vitals_critical_alert //

CREATE TRIGGER trg_after_vitals_critical_alert
AFTER INSERT ON Vitals_Log
FOR EACH ROW
BEGIN
    DECLARE v_systolic INT DEFAULT 120;
    DECLARE v_is_critical BOOLEAN DEFAULT FALSE;
    DECLARE v_patient_name VARCHAR(200);
    DECLARE v_attending_doc_id INT;

    IF NEW.bp IS NOT NULL AND INSTR(NEW.bp, '/') > 0 THEN
        SET v_systolic = CAST(SUBSTRING_INDEX(NEW.bp, '/', 1) AS UNSIGNED);
    END IF;

    IF (NEW.spo2 IS NOT NULL AND NEW.spo2 < 92)
       OR (v_systolic >= 160 OR v_systolic <= 85)
       OR (NEW.pulse >= 120 OR NEW.pulse <= 45)
       OR (NEW.temperature >= 102.0)
       OR (NEW.resp_rate IS NOT NULL AND (NEW.resp_rate >= 28 OR NEW.resp_rate <= 8)) THEN
        SET v_is_critical = TRUE;
    END IF;

    IF v_is_critical THEN
        SELECT CONCAT(first_name, ' ', last_name) INTO v_patient_name
        FROM Patients
        WHERE patient_id = NEW.patient_id;

        SELECT s.user_id INTO v_attending_doc_id
        FROM Admissions adm
        INNER JOIN Staff s ON adm.admitted_doctor_id = s.staff_id
        WHERE adm.patient_id = NEW.patient_id AND adm.status = 'Admitted'
        LIMIT 1;

        INSERT INTO Notifications (title, message, type, target_role, target_user_id, is_read, details, created_at)
        VALUES (
            'CRITICAL PATIENT VITALS ALERT',
            CONCAT('Patient ', COALESCE(v_patient_name, CONCAT('ID #', NEW.patient_id)), 
                   ' recorded critical vitals: BP: ', COALESCE(NEW.bp, 'N/A'), 
                   ', HR: ', COALESCE(NEW.pulse, 0), ' bpm', 
                   ', SpO2: ', COALESCE(CONCAT(NEW.spo2, '%'), 'N/A'),
                   ', Temp: ', COALESCE(NEW.temperature, 0.0), '°F.'),
            'CRITICAL_VITALS',
            'doctor',
            v_attending_doc_id,
            FALSE,
            JSON_OBJECT(
                'vital_id', NEW.vital_id,
                'patient_id', NEW.patient_id,
                'bp', NEW.bp,
                'pulse', NEW.pulse,
                'spo2', NEW.spo2,
                'resp_rate', NEW.resp_rate,
                'temperature', NEW.temperature,
                'recorded_by', NEW.recorded_by
            ),
            NOW()
        );
    END IF;
END //

DELIMITER ;


DELIMITER //

DROP TRIGGER IF EXISTS trg_audit_mar_administration //

CREATE TRIGGER trg_audit_mar_administration
AFTER INSERT ON Medication_Administration_Records
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Logs (actor_id, action_type, resource_table, details, timestamp)
    VALUES (
        NEW.administered_by,
        'MEDICATION_ADMINISTERED',
        'Medication_Administration_Records',
        JSON_OBJECT(
            'mar_id', NEW.mar_id,
            'rx_id', NEW.rx_id,
            'patient_id', NEW.patient_id,
            'status', NEW.status,
            'reason', NEW.reason,
            'administered_at', NEW.administered_at
        ),
        NOW()
    );
END //

DELIMITER ;


DELIMITER //

DROP TRIGGER IF EXISTS trg_audit_bed_status_change //

CREATE TRIGGER trg_audit_bed_status_change
AFTER UPDATE ON Beds
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status OR (OLD.current_patient_id <=> NEW.current_patient_id) = 0 THEN
        INSERT INTO Audit_Logs (actor_id, action_type, resource_table, details, timestamp)
        VALUES (
            NULL,
            'BED_STATUS_CHANGED',
            'Beds',
            JSON_OBJECT(
                'bed_id', NEW.bed_id,
                'bed_number', NEW.bed_number,
                'old_status', OLD.status,
                'new_status', NEW.status,
                'old_patient_id', OLD.current_patient_id,
                'new_patient_id', NEW.current_patient_id
            ),
            NOW()
        );
    END IF;
END //

DELIMITER ;


DELIMITER //

DROP TRIGGER IF EXISTS trg_notify_nurse_new_lab_order //

CREATE TRIGGER trg_notify_nurse_new_lab_order
AFTER INSERT ON Lab_Orders
FOR EACH ROW
BEGIN
    DECLARE v_patient_name VARCHAR(200);
    DECLARE v_doc_name VARCHAR(200);

    IF NEW.status = 'Pending' THEN
        SELECT CONCAT(first_name, ' ', last_name) INTO v_patient_name
        FROM Patients
        WHERE patient_id = NEW.patient_id;

        SELECT CONCAT(first_name, ' ', last_name) INTO v_doc_name
        FROM Staff
        WHERE staff_id = NEW.doctor_id;

        INSERT INTO Notifications (title, message, type, target_role, details, created_at)
        VALUES (
            'NEW LAB TEST ORDERED',
            CONCAT('Doctor ', COALESCE(v_doc_name, 'Physician'), ' ordered ', NEW.test_type, ' for patient ', COALESCE(v_patient_name, CONCAT('ID #', NEW.patient_id)), '.'),
            'LAB_ORDER_NEW',
            'nurse',
            JSON_OBJECT('lab_id', NEW.lab_id, 'patient_id', NEW.patient_id, 'test_type', NEW.test_type),
            NOW()
        );
    END IF;
END //

DELIMITER ;

