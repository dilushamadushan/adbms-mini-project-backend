-- =====================================================================
-- Clinical & Patient Module: Scheduled Database Events
-- Automated Routine Maintenance & Prescription Expiry Management
-- Database Engine: MySQL 8.0+ (InnoDB)
-- =====================================================================

USE `hms`;

-- Ensure MySQL Event Scheduler is running
SET GLOBAL event_scheduler = ON;

-- ---------------------------------------------------------------------
-- Event 1: ev_deactivate_expired_prescriptions
-- WHAT: Daily housekeeping event running at midnight (00:00:00).
--       Transitions prescriptions older than 60 days to 'Inactive'
--       if they are still flagged as 'Active'.
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS `ev_deactivate_expired_prescriptions`;

DELIMITER $$

CREATE EVENT `ev_deactivate_expired_prescriptions`
ON SCHEDULE EVERY 1 DAY
STARTS (CURRENT_DATE + INTERVAL 1 DAY)
COMMENT 'Automatically deactivates long-standing expired prescriptions daily'
DO
BEGIN
    UPDATE `Prescriptions`
    SET `status` = 'Inactive',
        `updated_at` = NOW()
    WHERE `status` = 'Active'
      AND `created_at` < DATE_SUB(NOW(), INTERVAL 60 DAY);
END$$

DELIMITER ;


-- ---------------------------------------------------------------------
-- Event 2: ev_archive_read_patient_notifications
-- WHAT: Weekly housekeeping event running every Sunday at 02:00:00.
--       Deletes read notifications for patients older than 90 days
--       to maintain optimal indexing and low table bloat.
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS `ev_archive_read_patient_notifications`;

DELIMITER $$

CREATE EVENT `ev_archive_read_patient_notifications`
ON SCHEDULE EVERY 1 WEEK
STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 2 HOUR)
COMMENT 'Cleans read patient notifications older than 90 days'
DO
BEGIN
    DELETE FROM `Notifications`
    WHERE `target_role` = 'patient'
      AND `is_read` = TRUE
      AND `created_at` < DATE_SUB(NOW(), INTERVAL 90 DAY);
END$$

DELIMITER ;
