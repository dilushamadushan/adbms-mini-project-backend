DROP TRIGGER IF EXISTS trg_audit_refresh_token_issued;
DROP TRIGGER IF EXISTS trg_audit_refresh_token_revoked;
DROP TRIGGER IF EXISTS trg_audit_refresh_token_deleted;

DROP TRIGGER IF EXISTS trg_prevent_department_self_parent;
DROP TRIGGER IF EXISTS trg_audit_department_created;
DROP TRIGGER IF EXISTS trg_audit_department_deleted;

DROP TRIGGER IF EXISTS trg_notify_staff_created;
DROP TRIGGER IF EXISTS trg_notify_department_created;
DROP TRIGGER IF EXISTS trg_notify_department_deleted;

DROP TRIGGER IF EXISTS trg_prevent_duplicate_open_admission;
DROP TRIGGER IF EXISTS trg_prevent_duplicate_admission_assignment;
DROP TRIGGER IF EXISTS trg_notify_admission_inserted;

DROP TRIGGER IF EXISTS trg_after_stock_receipt_insert;
DROP TRIGGER IF EXISTS trg_before_dispensation_insert;
DROP TRIGGER IF EXISTS trg_after_dispensation_insert;

DROP TRIGGER IF EXISTS trg_check_po_delivery_lead_time;
DROP TRIGGER IF EXISTS trg_check_po_receive_lead_time;

DROP TRIGGER IF EXISTS trg_discharge_after_insert;
DROP TRIGGER IF EXISTS trg_medical_record_after_insert;
DROP TRIGGER IF EXISTS trg_audit_mar_administration;
DROP TRIGGER IF EXISTS trg_mar_before_update;
DROP TRIGGER IF EXISTS trg_mar_after_update;
DROP TRIGGER IF EXISTS trg_doctor_order_after_insert;
DROP TRIGGER IF EXISTS trg_lab_order_after_insert;
DROP TRIGGER IF EXISTS trg_lab_order_pending_to_completed;

DROP TRIGGER IF EXISTS trg_notify_nurse_new_lab_order;
DROP TRIGGER IF EXISTS trg_audit_bed_status_change;
DROP TRIGGER IF EXISTS trg_audit_mar_administrations;
DROP TRIGGER IF EXISTS trg_after_vitals_critical_alert;
DROP TRIGGER IF EXISTS trg_patient_notify_on_medical_record;
DROP TRIGGER IF EXISTS trg_patient_notify_on_prescription;

DELIMITER //

-- TG/1407 --

CREATE TRIGGER trg_audit_refresh_token_issued
AFTER INSERT ON Refresh_Tokens
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Logs (actor_id, action_type, resource_table, details)
    VALUES (
        NEW.user_id,
        'LOGIN_SESSION_CREATED',
        'Refresh_Tokens',
        JSON_OBJECT(
            'token_id', NEW.token_id,
            'user_id', NEW.user_id,
            'expires_at', NEW.expires_at,
            'created_at', NOW()
        )
    );
END //

CREATE TRIGGER trg_audit_refresh_token_revoked
AFTER UPDATE ON Refresh_Tokens
FOR EACH ROW
BEGIN
    IF OLD.revoked = FALSE AND NEW.revoked = TRUE THEN
        INSERT INTO Audit_Logs (actor_id, action_type, resource_table, details)
        VALUES (
            NEW.user_id,
            'TOKEN_REVOKED',
            'Refresh_Tokens',
            JSON_OBJECT(
                'token_id', NEW.token_id,
                'user_id', NEW.user_id,
                'action', 'LOGOUT_OR_ROTATION',
                'revoked_at', NOW()
            )
        );
    END IF;
END //

CREATE TRIGGER trg_audit_refresh_token_deleted
AFTER DELETE ON Refresh_Tokens
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Logs (actor_id, action_type, resource_table, details)
    VALUES (
        OLD.user_id,
        'TOKEN_DELETED_ON_LOGOUT',
        'Refresh_Tokens',
        JSON_OBJECT(
            'token_id', OLD.token_id,
            'user_id', OLD.user_id,
            'action', 'REMOVED_FROM_DB_ON_LOGOUT',
            'timestamp', NOW()
        )
    );
END //

CREATE TRIGGER trg_prevent_department_self_parent
BEFORE UPDATE ON Departments
FOR EACH ROW
BEGIN
    IF NEW.parent_dept_id IS NOT NULL AND NEW.parent_dept_id = NEW.dept_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Integrity violation: A department cannot be set as its own parent';
    END IF;
END //

CREATE TRIGGER trg_audit_department_created
AFTER INSERT ON Departments
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Logs (actor_id, action_type, resource_table, details, timestamp)
    VALUES (
        NULL,
        'DEPARTMENT_CREATED',
        'Departments',
        JSON_OBJECT(
            'dept_id', NEW.dept_id,
            'dept_name', NEW.dept_name,
            'parent_dept_id', NEW.parent_dept_id
        ),
        NOW()
    );
END //

CREATE TRIGGER trg_audit_department_deleted
AFTER DELETE ON Departments
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Logs (actor_id, action_type, resource_table, details, timestamp)
    VALUES (
        NULL,
        'DEPARTMENT_DELETED',
        'Departments',
        JSON_OBJECT(
            'dept_id', OLD.dept_id,
            'dept_name', OLD.dept_name,
            'parent_dept_id', OLD.parent_dept_id
        ),
        NOW()
    );
END //

CREATE TRIGGER trg_notify_staff_created
AFTER INSERT ON Staff
FOR EACH ROW
BEGIN
    DECLARE v_dept_name VARCHAR(100);
    SELECT dept_name INTO v_dept_name FROM Departments WHERE dept_id = NEW.dept_id;

    INSERT INTO Notifications (title, message, type, target_role, details, created_at)
    VALUES (
        'New Staff Member Added',
        CONCAT(
            'Staff member ', NEW.first_name, ' ', NEW.last_name,
            IF(NEW.specialty IS NOT NULL AND NEW.specialty != '', CONCAT(' (', NEW.specialty, ')'), ''),
            ' was assigned to department ', COALESCE(v_dept_name, CONCAT('ID #', NEW.dept_id)), '.'
        ),
        'STAFF_ADDED',
        'admin',
        JSON_OBJECT(
            'staff_id', NEW.staff_id,
            'user_id', NEW.user_id,
            'dept_id', NEW.dept_id,
            'dept_name', v_dept_name,
            'name', CONCAT(NEW.first_name, ' ', NEW.last_name),
            'specialty', NEW.specialty
        ),
        NOW()
    );
END //

CREATE TRIGGER trg_notify_department_created
AFTER INSERT ON Departments
FOR EACH ROW
BEGIN
    INSERT INTO Notifications (title, message, type, target_role, details, created_at)
    VALUES (
        'New Department Created',
        CONCAT('New department "', NEW.dept_name, '" (ID #', NEW.dept_id, ') has been established in the hospital.'),
        'DEPARTMENT_ADDED',
        'all',
        JSON_OBJECT(
            'dept_id', NEW.dept_id,
            'dept_name', NEW.dept_name,
            'parent_dept_id', NEW.parent_dept_id
        ),
        NOW()
    );
END //

CREATE TRIGGER trg_notify_department_deleted
AFTER DELETE ON Departments
FOR EACH ROW
BEGIN
    INSERT INTO Notifications (title, message, type, target_role, details, created_at)
    VALUES (
        'Department Removed',
        CONCAT('Department "', OLD.dept_name, '" (ID #', OLD.dept_id, ') has been removed.'),
        'DEPARTMENT_DELETED',
        'all',
        JSON_OBJECT(
            'dept_id', OLD.dept_id,
            'dept_name', OLD.dept_name
        ),
        NOW()
    );
END //

-- Chavi --

CREATE TRIGGER trg_prevent_duplicate_open_admission
BEFORE INSERT ON Admissions
FOR EACH ROW
BEGIN
    DECLARE v_locked_patient_id INT;
    DECLARE v_open_admission_id INT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_open_admission_id = NULL;

    SELECT patient_id
    INTO v_locked_patient_id
    FROM Patients
    WHERE patient_id = NEW.patient_id
    FOR UPDATE;

    SELECT a.admission_id
    INTO v_open_admission_id
    FROM Admissions a
    LEFT JOIN Discharges d ON d.admission_id = a.admission_id
    WHERE a.patient_id = NEW.patient_id
      AND (d.admission_id IS NULL OR d.status <> 'Discharged')
    LIMIT 1;

    IF v_open_admission_id IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Patient already has an open admission. Complete discharge before admitting again.';
    END IF;
END //

CREATE TRIGGER trg_prevent_duplicate_admission_assignment
BEFORE UPDATE ON Admissions
FOR EACH ROW
BEGIN
    DECLARE v_open_admission_id INT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_open_admission_id = NULL;

    IF NEW.status = 'Admitted' AND OLD.status <> 'Admitted' THEN
        SELECT a.admission_id
        INTO v_open_admission_id
        FROM Admissions a
        LEFT JOIN Discharges d ON d.admission_id = a.admission_id
        WHERE a.patient_id = NEW.patient_id
          AND a.admission_id <> NEW.admission_id
          AND (d.admission_id IS NULL OR d.status <> 'Discharged')
        LIMIT 1;

        IF v_open_admission_id IS NOT NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Patient already has an open admission. Complete discharge before admitting again.';
        END IF;
    END IF;
END //

CREATE TRIGGER trg_notify_admission_inserted
AFTER INSERT ON Admissions
FOR EACH ROW
BEGIN
    DECLARE v_patient_name VARCHAR(201);
    DECLARE v_ward_name VARCHAR(100);
    DECLARE v_bed_number VARCHAR(20);

    SELECT CONCAT(p.first_name, ' ', p.last_name), w.ward_name, b.bed_number
    INTO v_patient_name, v_ward_name, v_bed_number
    FROM Patients p
    JOIN Wards w ON w.ward_id = NEW.ward_id
    LEFT JOIN Beds b ON b.bed_id = NEW.bed_id
    WHERE p.patient_id = NEW.patient_id;

    INSERT INTO Notifications (title, message, type, target_role, details, created_at)
    VALUES (
        'New Patient Admission',
        CONCAT('Admission request for ', v_patient_name, ' in ', v_ward_name, ' has been created.'),
        'PATIENT_ADMITTED',
        'all',
        JSON_OBJECT(
            'admission_id', NEW.admission_id,
            'patient_id', NEW.patient_id,
            'patient_name', v_patient_name,
            'ward_id', NEW.ward_id,
            'ward_name', v_ward_name,
            'bed_id', NEW.bed_id,
            'bed_number', v_bed_number,
            'admitted_doctor_id', NEW.admitted_doctor_id,
            'admitted_by', NEW.admitted_by,
            'admitted_at', NEW.admitted_at,
            'admission_reason', NEW.admission_reason,
            'guardian_name', NEW.guardian_name,
            'guardian_relationship', NEW.guardian_relationship,
            'guardian_contact', NEW.guardian_contact,
            'gender', NEW.gender,
            'status', NEW.status
        ),
        NOW()
    );
END //

-- thimira --

CREATE TRIGGER trg_after_stock_receipt_insert
AFTER INSERT ON Stock_Receipts
FOR EACH ROW
BEGIN
    UPDATE Medicines
    SET 
        stock_qty = stock_qty + NEW.quantity,
        expiry_date = COALESCE(NEW.expiry_date, expiry_date),
        is_active = TRUE
    WHERE medicine_id = NEW.medicine_id;

    INSERT INTO Audit_Logs (actor_id, action_type, resource_table, details, timestamp)
    VALUES (
        NEW.received_by,
        'STOCK_RECEIVED',
        'Medicines',
        JSON_OBJECT(
            'medicine_id', NEW.medicine_id,
            'received_qty', NEW.quantity,
            'receipt_id', NEW.receipt_id
        ),
        NOW()
    );
END //

CREATE TRIGGER trg_before_dispensation_insert
BEFORE INSERT ON Dispensations
FOR EACH ROW
BEGIN
    DECLARE current_stock INT DEFAULT 0;

    SELECT stock_qty INTO current_stock
    FROM Medicines
    WHERE medicine_id = NEW.medicine_id;

    IF current_stock < NEW.quantity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Insufficient stock available for this medication';
    END IF;
END //

CREATE TRIGGER trg_after_dispensation_insert
AFTER INSERT ON Dispensations
FOR EACH ROW
BEGIN
    DECLARE remaining_stock INT;
    DECLARE reorder_lvl INT;
    DECLARE med_title VARCHAR(100);

    UPDATE Medicines
    SET stock_qty = stock_qty - NEW.quantity
    WHERE medicine_id = NEW.medicine_id;

    SELECT stock_qty, reorder_level, med_name 
    INTO remaining_stock, reorder_lvl, med_title
    FROM Medicines
    WHERE medicine_id = NEW.medicine_id;

    IF remaining_stock <= reorder_lvl THEN
        INSERT INTO Notifications (title, message, type, target_role, details, created_at)
        VALUES (
            'Low Stock Alert',
            CONCAT('Warning: Medicine "', med_title, '" stock is low (Remaining: ', remaining_stock, ', Threshold: ', reorder_lvl, ').'),
            'LOW_STOCK',
            'pharmacist',
            JSON_OBJECT(
                'medicine_id', NEW.medicine_id,
                'remaining_stock', remaining_stock,
                'reorder_level', reorder_lvl
            ),
            NOW()
        );
    END IF;
END //

CREATE TRIGGER trg_check_po_delivery_lead_time
BEFORE INSERT ON Purchase_Orders
FOR EACH ROW
BEGIN
    IF NEW.expected_delivery_date < DATE_ADD(CURDATE(), INTERVAL 1 DAY) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Restock lead time must be at least 1 day. Expected delivery date must be at least 1 day in advance.';
    END IF;
END //

CREATE TRIGGER trg_check_po_receive_lead_time
BEFORE UPDATE ON Purchase_Orders
FOR EACH ROW
BEGIN
    IF NEW.status = 'RECEIVED' AND OLD.status != 'RECEIVED' THEN
        IF DATEDIFF(CURDATE(), DATE(OLD.order_date)) < 1 AND CURDATE() < OLD.expected_delivery_date THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot confirm stock receipt before 1 day from the order date. The order is still in transit from the supplier.';
        END IF;
    END IF;
END //




-- ishan --

-- This trigger:
--   1. Creates an audit log for the discharge request.
--   2. Records the doctor who authorized the request.
--   3. Stores the admission ID, discharge ID, and status.
CREATE TRIGGER trg_discharge_after_insert
AFTER INSERT ON discharges
FOR EACH ROW
BEGIN
    INSERT INTO audit_logs (
        actor_id,
        action_type,
        resource_table,
        details
    )
    VALUES (
        NEW.discharge_authorized_by,
        'DISCHARGE_REQUEST',
        'admissions',
        JSON_OBJECT(
            'admission_id', NEW.admission_id,
            'discharge_id', NEW.discharge_id,
            'status', NEW.status
        )
    );
END //

-- It writes one line in audit_logs: who created the
-- record and which record it was.
-- =====================================================
CREATE TRIGGER trg_medical_record_after_insert
AFTER INSERT ON medical_records
FOR EACH ROW
BEGIN
  DECLARE v_user_id INT;

  -- find the doctor's login id from the staff id
  SELECT user_id INTO v_user_id FROM staff WHERE staff_id = NEW.doctor_id;

  -- write the log line
  INSERT INTO audit_logs (actor_id, action_type, resource_table, details)
  VALUES (v_user_id, 'MEDICAL_RECORD_CREATED', 'medical_records',
          JSON_OBJECT('record_id', NEW.record_id,
                      'patient_id', NEW.patient_id,
                      'apt_id', NEW.apt_id));
END //

-- WHY:  Triggers run by themselves. Nobody calls them.
-- WHAT: 4 triggers. They keep a history (audit_logs) and notify nurses.

-- 1. After a dose row is added
-- WHAT: Writes an audit line. A new "Not Given" row with no reason is logged as
--       DOSE_SCHEDULED, anything else as MEDICATION_ADMINISTERED.
-- NOTE: This REPLACES the old trigger with the same name.
CREATE TRIGGER trg_audit_mar_administration
AFTER INSERT ON medication_administration_records
FOR EACH ROW
BEGIN
  INSERT INTO audit_logs (actor_id, action_type, resource_table, details, timestamp)
  VALUES (
    NEW.administered_by,
    IF(NEW.status = 'Not Given' AND TRIM(COALESCE(NEW.reason, '')) = '',
       'DOSE_SCHEDULED', 'MEDICATION_ADMINISTERED'),
    'Medication_Administration_Records',
    JSON_OBJECT(
      'mar_id', NEW.mar_id,
      'rx_id', NEW.rx_id,
      'patient_id', NEW.patient_id,
      'status', NEW.status,
      'reason', NEW.reason,
      'notes', NEW.notes,
      'administered_at', NEW.administered_at
    ),
    NOW()
  );
END //

-- 2. Before the nurse changes a dose row
-- WHAT: If the status becomes Refused or Held, a reason is required (else error).
--       Also sets administered_at to the real time of the change.
CREATE TRIGGER trg_mar_before_update
BEFORE UPDATE ON medication_administration_records
FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status THEN
    IF NEW.status IN ('Refused', 'Held')
       AND TRIM(COALESCE(NEW.reason, '')) = '' THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A reason is required when a dose is Refused or Held';
    END IF;
    SET NEW.administered_at = NOW();
  END IF;
END //

-- 3. After the nurse changes a dose row
-- WHAT: If the status changed, writes an audit line with old status, new status, reason.
CREATE TRIGGER trg_mar_after_update
AFTER UPDATE ON medication_administration_records
FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status THEN
    INSERT INTO audit_logs (actor_id, action_type, resource_table, details)
    VALUES (
      NEW.administered_by,
      'MEDICATION_STATUS_CHANGED',
      'Medication_Administration_Records',
      JSON_OBJECT(
        'mar_id', NEW.mar_id,
        'rx_id', NEW.rx_id,
        'patient_id', NEW.patient_id,
        'old_status', OLD.status,
        'new_status', NEW.status,
        'reason', NEW.reason,
        'notes', NEW.notes
      )
    );
  END IF;
END //

-- 4. After a nurse instruction is saved
-- WHAT: Sends a notification to nurses: "New <type> order for <patient name>."
CREATE TRIGGER trg_doctor_order_after_insert
AFTER INSERT ON doctor_orders
FOR EACH ROW
BEGIN
  DECLARE v_name VARCHAR(201);

  SELECT CONCAT(first_name, ' ', last_name)
  INTO v_name
  FROM patients
  WHERE patient_id = NEW.patient_id;

  INSERT INTO notifications (title, message, type, target_role, details)
  VALUES (
    'New Doctor Order',
    CONCAT('New ', NEW.order_type, ' order for ',
           COALESCE(v_name, CONCAT('patient #', NEW.patient_id)), '.'),
    'NEW_DOCTOR_ORDER',
    'nurse',
    JSON_OBJECT('order_id', NEW.order_id,
                'patient_id', NEW.patient_id,
                'order_type', NEW.order_type)
  );
END //

-- Logs every new lab order in the audit log.
CREATE TRIGGER trg_lab_order_after_insert
AFTER INSERT ON Lab_Orders
FOR EACH ROW
BEGIN
    DECLARE v_actor_id INT;

    SELECT user_id
    INTO v_actor_id
    FROM Staff
    WHERE staff_id = NEW.doctor_id
    LIMIT 1;

    INSERT INTO Audit_Logs (
        actor_id,
        action_type,
        resource_table,
        details,
        timestamp
    )
    VALUES (
        v_actor_id,
        'LAB_ORDER_CREATED',
        'Lab_Orders',
        JSON_OBJECT(
            'lab_id', NEW.lab_id,
            'patient_id', NEW.patient_id,
            'doctor_id', NEW.doctor_id,
            'test_type', NEW.test_type,
            'status', NEW.status
        ),
        NOW()
    );
END //

-- Logs when a lab order changes from Pending to Completed.
CREATE TRIGGER trg_lab_order_pending_to_completed
AFTER UPDATE ON Lab_Orders
FOR EACH ROW
BEGIN
    DECLARE v_actor_id INT;

    IF OLD.status = 'Pending'
       AND NEW.status = 'Completed' THEN

        SELECT user_id
        INTO v_actor_id
        FROM Staff
        WHERE staff_id = NEW.doctor_id
        LIMIT 1;

        INSERT INTO Audit_Logs (
            actor_id,
            action_type,
            resource_table,
            details,
            timestamp
        )
        VALUES (
            v_actor_id,
            'LAB_RESULT_COMPLETED',
            'Lab_Orders',
            JSON_OBJECT(
                'lab_id', NEW.lab_id,
                'patient_id', NEW.patient_id,
                'doctor_id', NEW.doctor_id,
                'test_type', NEW.test_type,
                'old_status', OLD.status,
                'new_status', NEW.status,
                'results_text', COALESCE(NEW.results_text, '')
            ),
            NOW()
        );
    END IF;
END //

-- nimhara --

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

CREATE TRIGGER trg_audit_mar_administrations
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

-- maleesha --

CREATE TRIGGER trg_patient_notify_on_prescription
AFTER INSERT ON `Prescriptions`
FOR EACH ROW
BEGIN
    DECLARE v_patient_id      INT DEFAULT NULL;
    DECLARE v_patient_user_id INT DEFAULT NULL;
    DECLARE v_doctor_id       INT DEFAULT NULL;
    DECLARE v_doctor_name     VARCHAR(150) DEFAULT NULL;

    SELECT patient_id, doctor_id INTO v_patient_id, v_doctor_id
    FROM `Medical_Records`
    WHERE `record_id` = NEW.record_id
    LIMIT 1;

    IF v_patient_id IS NOT NULL THEN
        SELECT user_id INTO v_patient_user_id
        FROM `Patients`
        WHERE `patient_id` = v_patient_id
        LIMIT 1;
    END IF;

    IF v_doctor_id IS NOT NULL THEN
        SELECT CONCAT(first_name, ' ', last_name) INTO v_doctor_name
        FROM `Staff`
        WHERE `staff_id` = v_doctor_id
        LIMIT 1;
    END IF;

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
END //

CREATE TRIGGER `trg_patient_notify_on_medical_record`
AFTER INSERT ON `Medical_Records`
FOR EACH ROW
BEGIN
    DECLARE v_patient_user_id INT DEFAULT NULL;
    DECLARE v_doctor_name     VARCHAR(150) DEFAULT NULL;

    SELECT user_id INTO v_patient_user_id
    FROM `Patients`
    WHERE `patient_id` = NEW.patient_id
    LIMIT 1;

    SELECT CONCAT(first_name, ' ', last_name) INTO v_doctor_name
    FROM `Staff`
    WHERE `staff_id` = NEW.doctor_id
    LIMIT 1;

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
END //

DELIMITER ;
