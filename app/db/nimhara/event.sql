USE hms;


DELIMITER //

DROP EVENT IF EXISTS ev_flag_overdue_cleaning_beds //

CREATE EVENT ev_flag_overdue_cleaning_beds
ON SCHEDULE EVERY 1 HOUR
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO Notifications (title, message, type, target_role, details, created_at)
    SELECT 
        'Bed Cleaning Delayed',
        CONCAT('Bed ', b.bed_number, ' in Ward ', w.ward_name, ' has been in Cleaning status for over 4 hours.'),
        'BED_CLEANING_OVERDUE',
        'nurse',
        JSON_OBJECT('bed_id', b.bed_id, 'ward_id', b.ward_id, 'bed_number', b.bed_number),
        NOW()
    FROM Beds b
    INNER JOIN Wards w ON b.ward_id = w.ward_id
    WHERE b.status = 'Cleaning'
      AND b.updated_at < (NOW() - INTERVAL 4 HOUR);
END //

DELIMITER ;
