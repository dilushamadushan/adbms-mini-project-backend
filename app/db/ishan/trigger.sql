
-- =====================================================
-- 1. TRIGGER - runs when a row is added to `discharges`
--    a) set the bed to Cleaning and remove the patient from it
--    b) mark the admission as Discharged (row is NOT deleted)
--    c) write an audit log
-- =====================================================
DROP TRIGGER IF EXISTS `trg_discharge_after_insert`;

DELIMITER $$
CREATE TRIGGER `trg_discharge_after_insert`
AFTER INSERT ON `discharges`
FOR EACH ROW
BEGIN
  -- a) free the bed
  UPDATE `beds` b
  JOIN `admissions` a ON a.bed_id = b.bed_id
  SET b.status = 'Cleaning', b.current_patient_id = NULL
  WHERE a.admission_id = NEW.admission_id;

  -- b) keep the admission, only change its status
  UPDATE `admissions`
  SET status = 'Discharged'
  WHERE admission_id = NEW.admission_id;

  -- c) audit log
  INSERT INTO `audit_logs` (actor_id, action_type, resource_table, details)
  VALUES (NEW.discharge_authorized_by, 'DISCHARGE_REQUEST', 'admissions',
          JSON_OBJECT('admission_id', NEW.admission_id, 'discharge_id', NEW.discharge_id));
END$$
DELIMITER ;