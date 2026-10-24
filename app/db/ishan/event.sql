-- Changes Active medicines to Inactive when their
-- duration is over (for example "3 days" have passed
-- since the prescription was saved).
-- It understands durations like "5 days" or "1 month".
-- =====================================================
DROP EVENT IF EXISTS `ev_deactivate_finished_prescriptions`;
CREATE EVENT `ev_deactivate_finished_prescriptions`
ON SCHEDULE EVERY 1 DAY
STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 DAY + INTERVAL 1 HOUR)
DO
  UPDATE prescriptions
  SET status = 'Inactive'
  WHERE status = 'Active'
    AND duration REGEXP '^[0-9]+ (day|days|month|months)$'
    AND created_at + INTERVAL (
          CAST(SUBSTRING_INDEX(duration, ' ', 1) AS UNSIGNED)
          * IF(duration LIKE '%month%', 30, 1)    -- 1 month counts as 30 days
        ) DAY < NOW();


-- =====================================================
-- 6. TURN ON THE EVENT SCHEDULER
-- Without this, the event in section 5 never runs.
-- It needs admin rights, and it turns off again when MySQL
-- restarts unless it is saved in the MySQL config file.
-- =====================================================
SHOW VARIABLES LIKE 'event_scheduler';     -- should show ON
SET GLOBAL event_scheduler = ON;











USE `hms`;

-- WHY:  Nurses may forget a new doctor order.
-- WHAT: Runs by itself every 30 minutes. Finds orders still Pending after 1 hour
--       and sends a reminder to nurses. Each order gets only ONE reminder.
-- NOTE: The event scheduler must be ON (it is set in the normal-patient script).

DROP EVENT IF EXISTS `ev_remind_unacknowledged_orders`;

CREATE EVENT `ev_remind_unacknowledged_orders`
ON SCHEDULE EVERY 30 MINUTE
DO
  INSERT INTO notifications (title, message, type, target_role, details)
  SELECT
    'Doctor Order Not Acknowledged',
    CONCAT('Order #', o.order_id, ' (', o.order_type, ') for patient #',
           o.patient_id, ' is still Pending.'),
    'ORDER_PENDING_REMINDER',
    'nurse',
    JSON_OBJECT('order_id', o.order_id, 'patient_id', o.patient_id)
  FROM doctor_orders o
  WHERE o.status = 'Pending'
    AND o.created_at < NOW() - INTERVAL 1 HOUR
    AND NOT EXISTS (
      SELECT 1
      FROM notifications n
      WHERE n.type = 'ORDER_PENDING_REMINDER'
        AND CAST(JSON_UNQUOTE(JSON_EXTRACT(n.details, '$.order_id')) AS UNSIGNED) = o.order_id
    );
