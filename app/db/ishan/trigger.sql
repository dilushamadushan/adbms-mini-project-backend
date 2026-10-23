
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