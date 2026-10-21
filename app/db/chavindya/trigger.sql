USE hms;

DELIMITER //

DROP TRIGGER IF EXISTS trg_notify_admission_created; //
DROP TRIGGER IF EXISTS trg_prevent_duplicate_open_admission; //
DROP TRIGGER IF EXISTS trg_notify_admission_confirmed; //
DROP TRIGGER IF EXISTS trg_prevent_duplicate_admission_assignment; //

DROP TRIGGER IF EXISTS trg_notify_admission_inserted; //

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

DELIMITER ;
