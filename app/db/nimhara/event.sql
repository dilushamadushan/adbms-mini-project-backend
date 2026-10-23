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


DELIMITER //

DROP EVENT IF EXISTS ev_check_pending_discharge_orders //

CREATE EVENT ev_check_pending_discharge_orders
ON SCHEDULE EVERY 5 MINUTE
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO Notifications (title, message, type, target_role, details, created_at)
    SELECT 
        'Pending Doctor Orders - Discharge Awaiting',
        CONCAT('Patient ', p.first_name, ' ', p.last_name, ' in Bed ', b.bed_number, ' has authorized discharge. Please mark pending doctor orders as Done before bed release.'),
        'DISCHARGE_ORDERS_PENDING',
        'nurse',
        JSON_OBJECT('admission_id', adm.admission_id, 'patient_id', p.patient_id, 'bed_id', b.bed_id),
        NOW()
    FROM Discharges dis
    INNER JOIN Admissions adm ON dis.admission_id = adm.admission_id
    INNER JOIN Patients p ON adm.patient_id = p.patient_id
    INNER JOIN Beds b ON adm.bed_id = b.bed_id
    WHERE dis.status = 'Authorized'
      AND b.status = 'Occupied'
      AND EXISTS (
          SELECT 1 FROM Doctor_Orders ord 
          WHERE ord.patient_id = p.patient_id AND ord.status != 'Done'
      );
END //

DELIMITER ;
