
-- This trigger:
--   1. Creates an audit log for the discharge request.
--   2. Records the doctor who authorized the request.
--   3. Stores the admission ID, discharge ID, and statu
DROP TRIGGER IF EXISTS `trg_discharge_after_insert`;

DELIMITER $$

CREATE TRIGGER `trg_discharge_after_insert`
AFTER INSERT ON `discharges`
FOR EACH ROW
BEGIN
    INSERT INTO `audit_logs` (
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
END$$

DELIMITER ;





-- It writes one line in audit_logs: who created the
-- record and which record it was.
-- =====================================================
DROP TRIGGER IF EXISTS `trg_medical_record_after_insert`;
DELIMITER $$
CREATE TRIGGER `trg_medical_record_after_insert`
AFTER INSERT ON `medical_records`
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
END$$
DELIMITER ;













USE `hms`;

-- WHY:  Triggers run by themselves. Nobody calls them.
-- WHAT: 4 triggers. They keep a history (audit_logs) and notify nurses.

-- 1. After a dose row is added
-- WHAT: Writes an audit line. A new "Not Given" row with no reason is logged as
--       DOSE_SCHEDULED, anything else as MEDICATION_ADMINISTERED.
-- NOTE: This REPLACES the old trigger with the same name.
DROP TRIGGER IF EXISTS `trg_audit_mar_administration`;
DELIMITER $$
CREATE TRIGGER `trg_audit_mar_administration`
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
END$$
DELIMITER ;

-- 2. Before the nurse changes a dose row
-- WHAT: If the status becomes Refused or Held, a reason is required (else error).
--       Also sets administered_at to the real time of the change.
DROP TRIGGER IF EXISTS `trg_mar_before_update`;
DELIMITER $$
CREATE TRIGGER `trg_mar_before_update`
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
END$$
DELIMITER ;

-- 3. After the nurse changes a dose row
-- WHAT: If the status changed, writes an audit line with old status, new status, reason.
DROP TRIGGER IF EXISTS `trg_mar_after_update`;
DELIMITER $$
CREATE TRIGGER `trg_mar_after_update`
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
END$$
DELIMITER ;

-- 4. After a nurse instruction is saved
-- WHAT: Sends a notification to nurses: "New <type> order for <patient name>."
DROP TRIGGER IF EXISTS `trg_doctor_order_after_insert`;
DELIMITER $$
CREATE TRIGGER `trg_doctor_order_after_insert`
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
END$$
DELIMITER ;







-- Logs every new lab order in the audit log.

DROP TRIGGER IF EXISTS trg_lab_order_after_insert;

DELIMITER $$

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
END$$

DELIMITER ;


-- Logs when a lab order changes from Pending to Completed.

DROP TRIGGER IF EXISTS trg_lab_order_pending_to_completed;

DELIMITER $$

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
END$$

DELIMITER ;