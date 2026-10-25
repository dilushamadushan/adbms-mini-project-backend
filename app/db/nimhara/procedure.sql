USE hms;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_nurse_ward_beds //

CREATE PROCEDURE sp_get_nurse_ward_beds(
    IN p_nurse_user_id INT,
    IN p_ward_id INT
)
BEGIN
    DECLARE v_staff_id INT;
    DECLARE v_ward_id INT;

    SELECT staff_id INTO v_staff_id FROM Staff WHERE user_id = p_nurse_user_id;

    IF p_ward_id IS NOT NULL AND p_ward_id > 0 THEN
        SET v_ward_id = p_ward_id;
    ELSE
        SELECT ward_id INTO v_ward_id 
        FROM Wards 
        WHERE nurse_in_charge_id = v_staff_id 
        ORDER BY ward_id ASC
        LIMIT 1;

        IF v_ward_id IS NULL THEN
            SELECT ward_id INTO v_ward_id FROM Wards ORDER BY ward_id ASC LIMIT 1;
        END IF;
    END IF;

    SELECT 
        w.ward_id,
        w.ward_name,
        w.total_beds,
        COUNT(CASE WHEN b.status = 'Occupied' THEN 1 END) AS occupied_beds,
        COUNT(CASE WHEN b.status = 'Available' THEN 1 END) AS available_beds,
        COUNT(CASE WHEN b.status = 'Cleaning' THEN 1 END) AS cleaning_beds,
        fn_ward_occupancy_rate(w.ward_id) AS occupancy_rate
    FROM Wards w
    LEFT JOIN Beds b ON w.ward_id = b.ward_id
    WHERE w.ward_id = v_ward_id
    GROUP BY w.ward_id, w.ward_name, w.total_beds;

    SELECT 
        b.bed_id,
        b.bed_number,
        b.ward_id,
        b.status AS bed_status,
        b.current_patient_id,
        CASE 
            WHEN p.patient_id IS NOT NULL THEN CONCAT(p.first_name, ' ', p.last_name)
            ELSE NULL 
        END AS patient_name,
        adm.gender,
        p.dob,
        p.blood_group,
        p.allergies,
        adm.admission_id,
        adm.admitted_at,
        adm.admission_reason,
        CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS attending_doctor_name,
        dis.discharge_id,
        dis.status AS discharge_status,
        CASE
            WHEN b.current_patient_id IS NOT NULL THEN fn_patient_vitals_status(b.current_patient_id)
            ELSE NULL
        END AS vitals_status,
        (
            SELECT vl.bp FROM Vitals_Log vl 
            WHERE vl.patient_id = b.current_patient_id 
            ORDER BY vl.recorded_at DESC LIMIT 1
        ) AS latest_bp,
        (
            SELECT vl.pulse FROM Vitals_Log vl 
            WHERE vl.patient_id = b.current_patient_id 
            ORDER BY vl.recorded_at DESC LIMIT 1
        ) AS latest_pulse,
        (
            SELECT vl.temperature FROM Vitals_Log vl 
            WHERE vl.patient_id = b.current_patient_id 
            ORDER BY vl.recorded_at DESC LIMIT 1
        ) AS latest_temperature,
        (
            SELECT vl.spo2 FROM Vitals_Log vl 
            WHERE vl.patient_id = b.current_patient_id 
            ORDER BY vl.recorded_at DESC LIMIT 1
        ) AS latest_spo2,
        (
            SELECT vl.resp_rate FROM Vitals_Log vl 
            WHERE vl.patient_id = b.current_patient_id 
            ORDER BY vl.recorded_at DESC LIMIT 1
        ) AS latest_resp_rate,
        (
            SELECT CONCAT('BP: ', COALESCE(vl.bp, '--'), ', HR: ', COALESCE(vl.pulse, '--'), ', SpO2: ', COALESCE(CONCAT(vl.spo2, '%'), '--'))
            FROM Vitals_Log vl
            WHERE vl.patient_id = b.current_patient_id
            ORDER BY vl.recorded_at DESC
            LIMIT 1
        ) AS latest_vitals_summary,
        (
            SELECT vl.recorded_at FROM Vitals_Log vl 
            WHERE vl.patient_id = b.current_patient_id 
            ORDER BY vl.recorded_at DESC LIMIT 1
        ) AS latest_vitals_time
    FROM Beds b
    LEFT JOIN Patients p ON b.current_patient_id = p.patient_id
    LEFT JOIN Admissions adm ON (
        adm.patient_id = p.patient_id 
        AND (adm.bed_id = b.bed_id OR adm.status = 'Admitted')
    )
    LEFT JOIN Staff doc ON adm.admitted_doctor_id = doc.staff_id
    LEFT JOIN Discharges dis ON adm.admission_id = dis.admission_id
    WHERE b.ward_id = v_ward_id
    ORDER BY b.bed_number ASC;

    SELECT 
        w.ward_id, 
        w.ward_name, 
        w.total_beds,
        COUNT(CASE WHEN b.status = 'Occupied' THEN 1 END) AS occupied_beds,
        COUNT(CASE WHEN b.status = 'Available' THEN 1 END) AS available_beds
    FROM Wards w
    LEFT JOIN Beds b ON w.ward_id = b.ward_id
    GROUP BY w.ward_id, w.ward_name, w.total_beds
    ORDER BY w.ward_id ASC;
END //

DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_nurse_dashboard_stats //

CREATE PROCEDURE sp_get_nurse_dashboard_stats(
    IN p_nurse_user_id INT,
    IN p_ward_id INT
)
BEGIN
    DECLARE v_staff_id INT;
    DECLARE v_ward_id INT;
    DECLARE v_hour INT;
    DECLARE v_shift VARCHAR(50);

    SELECT staff_id INTO v_staff_id FROM Staff WHERE user_id = p_nurse_user_id;

    IF p_ward_id IS NOT NULL AND p_ward_id > 0 THEN
        SET v_ward_id = p_ward_id;
    ELSE
        SELECT ward_id INTO v_ward_id FROM Wards WHERE nurse_in_charge_id = v_staff_id ORDER BY ward_id ASC LIMIT 1;
        IF v_ward_id IS NULL THEN
            SELECT ward_id INTO v_ward_id FROM Wards ORDER BY ward_id ASC LIMIT 1;
        END IF;
    END IF;

    SET v_hour = HOUR(NOW());
    IF v_hour >= 7 AND v_hour < 15 THEN
        SET v_shift = 'Day (07:00 - 15:00)';
    ELSEIF v_hour >= 15 AND v_hour < 23 THEN
        SET v_shift = 'Evening (15:00 - 23:00)';
    ELSE
        SET v_shift = 'Night (23:00 - 07:00)';
    END IF;

    SELECT 
        w.ward_id,
        w.ward_name,
        w.total_beds,
        COUNT(DISTINCT CASE WHEN b.status = 'Occupied' THEN b.bed_id END) AS occupied_beds,
        COUNT(DISTINCT CASE WHEN b.status = 'Available' THEN b.bed_id END) AS available_beds,
        COUNT(DISTINCT CASE WHEN b.status = 'Cleaning' THEN b.bed_id END) AS cleaning_beds,
        v_shift AS active_shift,
        (
            SELECT COUNT(DISTINCT b2.current_patient_id)
            FROM Beds b2
            WHERE b2.ward_id = w.ward_id 
              AND b2.current_patient_id IS NOT NULL 
              AND fn_patient_vitals_status(b2.current_patient_id) = 'CRITICAL'
        ) AS critical_patients_count,
        (
            SELECT COUNT(*) 
            FROM Prescriptions rx
            INNER JOIN Medical_Records mr ON rx.record_id = mr.record_id
            INNER JOIN Beds b3 ON mr.patient_id = b3.current_patient_id
            WHERE b3.ward_id = w.ward_id AND rx.status = 'Active'
        ) AS medications_due_count,
        (
            SELECT COUNT(*) 
            FROM Doctor_Orders do2
            INNER JOIN Beds b4 ON do2.patient_id = b4.current_patient_id
            WHERE b4.ward_id = w.ward_id AND do2.status IN ('Pending', 'Acknowledged')
        ) AS pending_orders_count
    FROM Wards w
    LEFT JOIN Beds b ON w.ward_id = b.ward_id
    WHERE w.ward_id = v_ward_id
    GROUP BY w.ward_id, w.ward_name, w.total_beds;
END //

DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_bed_details //

CREATE PROCEDURE sp_get_bed_details(
    IN p_bed_id INT
)
BEGIN
    DECLARE v_patient_id INT;

    SELECT current_patient_id INTO v_patient_id FROM Beds WHERE bed_id = p_bed_id;

    SELECT 
        b.bed_id,
        b.bed_number,
        b.ward_id,
        w.ward_name,
        b.status AS bed_status,
        p.patient_id,
        CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
        p.dob,
        TIMESTAMPDIFF(YEAR, p.dob, CURDATE()) AS age,
        p.blood_group,
        p.emergency_contact,
        p.allergies,
        adm.admission_id,
        adm.admitted_at,
        adm.admission_reason,
        CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS attending_doctor,
        dis.discharge_id,
        dis.status AS discharge_status,
        dis.discharge_notes
    FROM Beds b
    INNER JOIN Wards w ON b.ward_id = w.ward_id
    LEFT JOIN Patients p ON b.current_patient_id = p.patient_id
    LEFT JOIN Admissions adm ON (
        adm.patient_id = p.patient_id 
        AND (adm.bed_id = b.bed_id OR adm.status = 'Admitted')
    )
    LEFT JOIN Staff doc ON adm.admitted_doctor_id = doc.staff_id
    LEFT JOIN Discharges dis ON adm.admission_id = dis.admission_id
    WHERE b.bed_id = p_bed_id;

    IF v_patient_id IS NOT NULL THEN
        SELECT 
            vl.vital_id,
            vl.patient_id,
            vl.bp,
            vl.pulse,
            vl.temperature,
            vl.spo2,
            vl.resp_rate,
            vl.blood_sugar,
            vl.weight,
            DATE_FORMAT(vl.recorded_at, '%Y-%m-%d %H:%i') AS recorded_at,
            CONCAT(s.first_name, ' ', s.last_name) AS recorded_by_name
        FROM Vitals_Log vl
        LEFT JOIN Staff s ON vl.recorded_by = s.staff_id
        WHERE vl.patient_id = v_patient_id
        ORDER BY vl.recorded_at DESC
        LIMIT 10;
    ELSE
        SELECT NULL LIMIT 0;
    END IF;
END //

DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_record_patient_vitals //

CREATE PROCEDURE sp_record_patient_vitals(
    IN p_bed_id INT,
    IN p_nurse_user_id INT,
    IN p_bp VARCHAR(20),
    IN p_pulse INT,
    IN p_temperature DECIMAL(5,2),
    IN p_spo2 INT,
    IN p_resp_rate INT,
    IN p_blood_sugar DECIMAL(5,2),
    IN p_weight DECIMAL(5,2)
)
BEGIN
    DECLARE v_staff_id INT;
    DECLARE v_patient_id INT;

    SELECT staff_id INTO v_staff_id FROM Staff WHERE user_id = p_nurse_user_id;
    IF v_staff_id IS NULL THEN
        SET v_staff_id = 3;
    END IF;

    SELECT current_patient_id INTO v_patient_id FROM Beds WHERE bed_id = p_bed_id;
    IF v_patient_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot record vitals: No patient currently assigned to this bed.';
    END IF;

    INSERT INTO Vitals_Log (patient_id, recorded_by, bp, pulse, temperature, spo2, resp_rate, blood_sugar, weight, recorded_at)
    VALUES (v_patient_id, v_staff_id, p_bp, p_pulse, p_temperature, p_spo2, p_resp_rate, p_blood_sugar, p_weight, NOW());

    SELECT 
        vl.vital_id,
        vl.patient_id,
        vl.bp,
        vl.pulse,
        vl.temperature,
        vl.spo2,
        vl.resp_rate,
        vl.blood_sugar,
        vl.weight,
        DATE_FORMAT(vl.recorded_at, '%Y-%m-%d %H:%i') AS recorded_at,
        CONCAT(s.first_name, ' ', s.last_name) AS recorded_by_name,
        fn_patient_vitals_status(v_patient_id) AS current_status
    FROM Vitals_Log vl
    LEFT JOIN Staff s ON vl.recorded_by = s.staff_id
    WHERE vl.vital_id = LAST_INSERT_ID();
END //

DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_patient_mar //

CREATE PROCEDURE sp_get_patient_mar(
    IN p_patient_id INT
)
BEGIN
    SELECT 
        rx.rx_id,
        rx.med_name,
        rx.dosage,
        rx.duration,
        rx.status AS rx_status,
        CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS doctor_name,
        fn_check_allergy_conflict(p_patient_id, rx.med_name) AS has_allergy_conflict,
        p.allergies AS patient_allergies,
        (
            SELECT mar.status 
            FROM Medication_Administration_Records mar 
            WHERE mar.rx_id = rx.rx_id 
            ORDER BY mar.administered_at DESC 
            LIMIT 1
        ) AS last_status,
        (
            SELECT DATE_FORMAT(mar.administered_at, '%Y-%m-%d %H:%i') 
            FROM Medication_Administration_Records mar 
            WHERE mar.rx_id = rx.rx_id 
            ORDER BY mar.administered_at DESC 
            LIMIT 1
        ) AS last_administered_at
    FROM Prescriptions rx
    INNER JOIN Medical_Records mr ON rx.record_id = mr.record_id
    INNER JOIN Patients p ON mr.patient_id = p.patient_id
    LEFT JOIN Staff doc ON mr.doctor_id = doc.staff_id
    WHERE mr.patient_id = p_patient_id AND rx.status = 'Active';

    SELECT 
        mar.mar_id,
        mar.rx_id,
        rx.med_name,
        rx.dosage,
        mar.status,
        mar.reason,
        mar.notes,
        DATE_FORMAT(mar.administered_at, '%Y-%m-%d %H:%i') AS administered_at,
        CONCAT(s.first_name, ' ', s.last_name) AS administered_by_name
    FROM Medication_Administration_Records mar
    INNER JOIN Prescriptions rx ON mar.rx_id = rx.rx_id
    LEFT JOIN Staff s ON mar.administered_by = s.staff_id
    WHERE mar.patient_id = p_patient_id
    ORDER BY mar.administered_at DESC
    LIMIT 20;
END //

DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_administer_medication //

CREATE PROCEDURE sp_administer_medication(
    IN p_rx_id INT,
    IN p_patient_id INT,
    IN p_nurse_user_id INT,
    IN p_status VARCHAR(20),
    IN p_reason TEXT,
    IN p_notes TEXT
)
BEGIN
    DECLARE v_staff_id INT;

    SELECT staff_id INTO v_staff_id FROM Staff WHERE user_id = p_nurse_user_id;
    IF v_staff_id IS NULL THEN
        SET v_staff_id = 3;
    END IF;

    INSERT INTO Medication_Administration_Records (rx_id, patient_id, administered_by, status, reason, notes, administered_at)
    VALUES (p_rx_id, p_patient_id, v_staff_id, p_status, p_reason, p_notes, NOW());

    SELECT 
        mar.mar_id,
        mar.rx_id,
        mar.patient_id,
        mar.status,
        mar.reason,
        mar.notes,
        DATE_FORMAT(mar.administered_at, '%Y-%m-%d %H:%i') AS administered_at,
        CONCAT(s.first_name, ' ', s.last_name) AS administered_by_name
    FROM Medication_Administration_Records mar
    LEFT JOIN Staff s ON mar.administered_by = s.staff_id
    WHERE mar.mar_id = LAST_INSERT_ID();
END //

DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_doctor_orders //

CREATE PROCEDURE sp_get_doctor_orders(
    IN p_patient_id INT
)
BEGIN
    SELECT 
        ord.order_id,
        ord.patient_id,
        ord.order_type,
        ord.instruction,
        ord.status,
        CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS doctor_name,
        ord.acknowledged_by,
        CONCAT(ack_nurse.first_name, ' ', ack_nurse.last_name) AS acknowledged_by_name,
        DATE_FORMAT(ord.acknowledged_at, '%Y-%m-%d %H:%i') AS acknowledged_at,
        ord.completed_by,
        DATE_FORMAT(ord.completed_at, '%Y-%m-%d %H:%i') AS completed_at,
        DATE_FORMAT(ord.created_at, '%Y-%m-%d %H:%i') AS created_at
    FROM Doctor_Orders ord
    INNER JOIN Staff doc ON ord.doctor_id = doc.staff_id
    LEFT JOIN Staff ack_nurse ON ord.acknowledged_by = ack_nurse.staff_id
    WHERE ord.patient_id = p_patient_id
    ORDER BY ord.created_at DESC;
END //

DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_acknowledge_doctor_order //

CREATE PROCEDURE sp_acknowledge_doctor_order(
    IN p_order_id INT,
    IN p_nurse_user_id INT,
    IN p_new_status VARCHAR(20)
)
BEGIN
    DECLARE v_staff_id INT;

    SELECT staff_id INTO v_staff_id FROM Staff WHERE user_id = p_nurse_user_id;
    IF v_staff_id IS NULL THEN
        SET v_staff_id = 3;
    END IF;

    IF p_new_status = 'Acknowledged' THEN
        UPDATE Doctor_Orders
        SET status = 'Acknowledged', acknowledged_by = v_staff_id, acknowledged_at = NOW()
        WHERE order_id = p_order_id;
    ELSEIF p_new_status = 'Done' THEN
        UPDATE Doctor_Orders
        SET status = 'Done', completed_by = v_staff_id, completed_at = NOW()
        WHERE order_id = p_order_id;
    ELSE
        UPDATE Doctor_Orders
        SET status = p_new_status
        WHERE order_id = p_order_id;
    END IF;

    SELECT order_id, status FROM Doctor_Orders WHERE order_id = p_order_id;
END //

DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_nursing_notes //

CREATE PROCEDURE sp_get_nursing_notes(
    IN p_patient_id INT
)
BEGIN
    SELECT 
        nn.note_id,
        nn.patient_id,
        nn.note_type,
        nn.subjective,
        nn.objective,
        nn.assessment,
        nn.plan,
        nn.content,
        DATE_FORMAT(nn.created_at, '%Y-%m-%d %H:%i') AS created_at,
        CONCAT(s.first_name, ' ', s.last_name) AS nurse_name
    FROM Nursing_Notes nn
    INNER JOIN Staff s ON nn.nurse_id = s.staff_id
    WHERE nn.patient_id = p_patient_id
    ORDER BY nn.created_at DESC;
END //

DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_add_nursing_note //

CREATE PROCEDURE sp_add_nursing_note(
    IN p_patient_id INT,
    IN p_nurse_user_id INT,
    IN p_note_type VARCHAR(20),
    IN p_subjective TEXT,
    IN p_objective TEXT,
    IN p_assessment TEXT,
    IN p_plan TEXT,
    IN p_content TEXT
)
BEGIN
    DECLARE v_staff_id INT;

    SELECT staff_id INTO v_staff_id FROM Staff WHERE user_id = p_nurse_user_id;
    IF v_staff_id IS NULL THEN
        SET v_staff_id = 3;
    END IF;

    INSERT INTO Nursing_Notes (patient_id, nurse_id, note_type, subjective, objective, assessment, plan, content, created_at)
    VALUES (p_patient_id, v_staff_id, p_note_type, p_subjective, p_objective, p_assessment, p_plan, p_content, NOW());

    SELECT 
        nn.note_id,
        nn.patient_id,
        nn.note_type,
        nn.subjective,
        nn.objective,
        nn.assessment,
        nn.plan,
        nn.content,
        DATE_FORMAT(nn.created_at, '%Y-%m-%d %H:%i') AS created_at,
        CONCAT(s.first_name, ' ', s.last_name) AS nurse_name
    FROM Nursing_Notes nn
    INNER JOIN Staff s ON nn.nurse_id = s.staff_id
    WHERE nn.note_id = LAST_INSERT_ID();
END //

DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_log_intake_output //

CREATE PROCEDURE sp_log_intake_output(
    IN p_patient_id INT,
    IN p_nurse_user_id INT,
    IN p_io_type VARCHAR(20),
    IN p_category VARCHAR(50),
    IN p_volume_ml INT,
    IN p_notes VARCHAR(255)
)
BEGIN
    DECLARE v_staff_id INT;

    SELECT staff_id INTO v_staff_id FROM Staff WHERE user_id = p_nurse_user_id;
    IF v_staff_id IS NULL THEN
        SET v_staff_id = 3;
    END IF;

    INSERT INTO Intake_Output_Logs (patient_id, recorded_by, io_type, category, volume_ml, notes, recorded_at)
    VALUES (p_patient_id, v_staff_id, p_io_type, p_category, p_volume_ml, p_notes, NOW());

    SELECT 
        io_id,
        patient_id,
        io_type,
        category,
        volume_ml,
        notes,
        DATE_FORMAT(recorded_at, '%Y-%m-%d %H:%i') AS recorded_at
    FROM Intake_Output_Logs
    WHERE io_id = LAST_INSERT_ID();
END //

DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_patient_io_summary //

CREATE PROCEDURE sp_get_patient_io_summary(
    IN p_patient_id INT,
    IN p_date DATE
)
BEGIN
    DECLARE v_target_date DATE;
    SET v_target_date = COALESCE(p_date, CURDATE());

    SELECT 
        v_target_date AS summary_date,
        COALESCE(SUM(CASE WHEN io_type = 'Intake' THEN volume_ml END), 0) AS total_intake_ml,
        COALESCE(SUM(CASE WHEN io_type = 'Output' THEN volume_ml END), 0) AS total_output_ml,
        fn_calc_patient_io_balance(p_patient_id, v_target_date) AS net_balance_ml
    FROM Intake_Output_Logs
    WHERE patient_id = p_patient_id AND DATE(recorded_at) = v_target_date;

    SELECT 
        io.io_id,
        io.io_type,
        io.category,
        io.volume_ml,
        io.notes,
        DATE_FORMAT(io.recorded_at, '%H:%i') AS entry_time,
        CONCAT(s.first_name, ' ', s.last_name) AS recorded_by_name
    FROM Intake_Output_Logs io
    LEFT JOIN Staff s ON io.recorded_by = s.staff_id
    WHERE io.patient_id = p_patient_id AND DATE(io.recorded_at) = v_target_date
    ORDER BY io.recorded_at DESC;
END //

DELIMITER ;



DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_ward_nurses //

CREATE PROCEDURE sp_get_ward_nurses()
BEGIN
    SELECT 
        s.staff_id,
        s.user_id,
        CONCAT(s.first_name, ' ', s.last_name) AS nurse_name,
        u.username,
        s.specialty
    FROM Staff s
    INNER JOIN Users u ON s.user_id = u.user_id
    WHERE u.role = 'nurse' AND u.is_active = 1
    ORDER BY s.first_name ASC;
END //

DELIMITER ;




DELIMITER //

DROP PROCEDURE IF EXISTS sp_update_bed_status //

CREATE PROCEDURE sp_update_bed_status(
    IN p_bed_id INT,
    IN p_new_status VARCHAR(20),
    IN p_nurse_user_id INT
)
BEGIN
    IF p_new_status NOT IN ('Available', 'Occupied', 'Cleaning') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid bed status value. Allowed: Available, Occupied, Cleaning.';
    END IF;

    IF p_new_status = 'Available' THEN
        UPDATE Beds
        SET status = p_new_status, current_patient_id = NULL
        WHERE bed_id = p_bed_id;
    ELSE
        UPDATE Beds
        SET status = p_new_status
        WHERE bed_id = p_bed_id;
    END IF;

    SELECT bed_id, bed_number, status, current_patient_id 
    FROM Beds 
    WHERE bed_id = p_bed_id;
END //

DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_complete_patient_discharge //

CREATE PROCEDURE sp_complete_patient_discharge(
    IN p_admission_id INT,
    IN p_nurse_user_id INT
)
BEGIN
    DECLARE v_bed_id INT;
    DECLARE v_patient_id INT;
    DECLARE v_discharge_id INT;
    DECLARE v_current_status VARCHAR(50);
    DECLARE v_pending_orders_count INT DEFAULT 0;

    SELECT discharge_id, status, admission_id
    INTO v_discharge_id, v_current_status, p_admission_id
    FROM Discharges
    WHERE admission_id = p_admission_id;

    IF v_discharge_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Discharge has not yet been authorized by the doctor.';
    END IF;

    IF v_current_status = 'Discharged' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Patient has already been discharged.';
    END IF;

    SELECT bed_id, patient_id INTO v_bed_id, v_patient_id 
    FROM Admissions 
    WHERE admission_id = p_admission_id;

    SELECT COUNT(*) INTO v_pending_orders_count
    FROM Doctor_Orders
    WHERE patient_id = v_patient_id AND status != 'Done';

    IF v_pending_orders_count > 0 THEN
        INSERT INTO Notifications (title, message, type, target_role, details, created_at)
        VALUES (
            'Pending Doctor Orders Alert',
            CONCAT('Cannot complete bed release for Patient ID #', v_patient_id, '. Outstanding Doctor Orders must be marked Done first.'),
            'DISCHARGE_ORDERS_PENDING',
            'nurse',
            JSON_OBJECT('admission_id', p_admission_id, 'patient_id', v_patient_id, 'pending_orders', v_pending_orders_count),
            NOW()
        );
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot release bed: Incomplete doctor orders exist. Mark all doctor orders as Done first.';
    END IF;

    START TRANSACTION;

    UPDATE Discharges
    SET status = 'Discharged',
        discharged_by = p_nurse_user_id,
        discharged_at = NOW()
    WHERE discharge_id = v_discharge_id;

    IF v_bed_id IS NOT NULL THEN
        UPDATE Beds
        SET status = 'Cleaning',
            current_patient_id = NULL
        WHERE bed_id = v_bed_id;
    END IF;

    UPDATE Admissions
    SET bed_id = NULL
    WHERE admission_id = p_admission_id;

    COMMIT;

    SELECT 
        v_discharge_id AS discharge_id,
        p_admission_id AS admission_id,
        'Discharged' AS status,
        v_bed_id AS freed_bed_id,
        'Discharge completed. Bed placed in Cleaning status.' AS message;
END //

DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_unassigned_admissions //

CREATE PROCEDURE sp_get_unassigned_admissions(
    IN p_ward_id INT
)
BEGIN
    SELECT 
        adm.admission_id,
        adm.patient_id,
        CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
        adm.gender,
        p.dob,
        p.blood_group,
        p.allergies,
        adm.admission_reason,
        adm.admitted_at,
        adm.guardian_name,
        adm.guardian_contact,
        CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS attending_doctor_name,
        adm.ward_id AS target_ward_id
    FROM Admissions adm
    INNER JOIN Patients p ON adm.patient_id = p.patient_id
    LEFT JOIN Staff doc ON adm.admitted_doctor_id = doc.staff_id
    WHERE adm.status = 'Pending'
      AND (adm.bed_id IS NULL OR adm.bed_id = 0)
      AND (p_ward_id IS NULL OR adm.ward_id = p_ward_id)
    ORDER BY adm.admitted_at ASC;
END //

DROP PROCEDURE IF EXISTS sp_nurse_assign_bed //

CREATE PROCEDURE sp_nurse_assign_bed(
    IN p_admission_id INT,
    IN p_bed_id INT,
    IN p_nurse_user_id INT
)
BEGIN
    DECLARE v_patient_id INT;
    DECLARE v_bed_ward_id INT;
    DECLARE v_adm_ward_id INT;
    DECLARE v_bed_status VARCHAR(20);
    DECLARE v_adm_status VARCHAR(20);

    SELECT status, ward_id INTO v_bed_status, v_bed_ward_id FROM Beds WHERE bed_id = p_bed_id;
    IF v_bed_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Specified bed does not exist.';
    END IF;

    IF v_bed_status != 'Available' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Bed is not available for patient assignment.';
    END IF;

    SELECT patient_id, ward_id, status INTO v_patient_id, v_adm_ward_id, v_adm_status 
    FROM Admissions 
    WHERE admission_id = p_admission_id;

    IF v_patient_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Specified admission record does not exist.';
    END IF;

    IF v_adm_status NOT IN ('Pending', 'Admitted') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Patient admission is not pending or active.';
    END IF;

    IF v_adm_ward_id IS NOT NULL AND v_bed_ward_id != v_adm_ward_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Patient can only be assigned to a bed within their designated ward.';
    END IF;

    START TRANSACTION;

    UPDATE Admissions 
    SET bed_id = p_bed_id, 
        ward_id = v_bed_ward_id, 
        status = 'Admitted',
        updated_at = NOW() 
    WHERE admission_id = p_admission_id;

    UPDATE Beds 
    SET current_patient_id = v_patient_id, 
        status = 'Occupied', 
        updated_at = NOW() 
    WHERE bed_id = p_bed_id;

    COMMIT;

    SELECT 
        p_admission_id AS admission_id,
        p_bed_id AS bed_id,
        v_patient_id AS patient_id,
        v_bed_ward_id AS ward_id,
        'Occupied' AS bed_status,
        'Admitted' AS admission_status,
        'Patient successfully assigned to bed.' AS message;
END //

DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_nurse_lab_orders //

CREATE PROCEDURE sp_get_nurse_lab_orders(
    IN p_status VARCHAR(20)
)
BEGIN
    SELECT 
        lo.lab_id,
        lo.patient_id,
        CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
        TIMESTAMPDIFF(YEAR, p.dob, CURDATE()) AS age,
        p.blood_group,
        p.allergies,
        p.emergency_contact,
        COALESCE(b.bed_number, 'Outpatient') AS bed_number,
        b.bed_id,
        adm.ward_id,
        COALESCE(w.ward_name, 'Outpatient Clinic') AS ward_name,
        lo.test_type,
        lo.status,
        lo.results_text,
        CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS doctor_name,
        lo.doctor_id,
        DATE_FORMAT(lo.ordered_at, '%Y-%m-%d %H:%i') AS ordered_at,
        DATE_FORMAT(lo.updated_at, '%Y-%m-%d %H:%i') AS updated_at
    FROM Lab_Orders lo
    INNER JOIN Patients p ON lo.patient_id = p.patient_id
    INNER JOIN Staff doc ON lo.doctor_id = doc.staff_id
    LEFT JOIN Admissions adm ON (adm.patient_id = p.patient_id AND adm.status = 'Admitted')
    LEFT JOIN Beds b ON adm.bed_id = b.bed_id
    LEFT JOIN Wards w ON adm.ward_id = w.ward_id
    WHERE (p_status IS NULL OR p_status = '' OR p_status = 'All' OR lo.status = p_status)
    ORDER BY lo.ordered_at DESC;
END //

DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_complete_lab_order //

CREATE PROCEDURE sp_complete_lab_order(
    IN p_lab_id INT,
    IN p_nurse_user_id INT,
    IN p_results_text TEXT
)
BEGIN
    DECLARE v_patient_id INT;
    DECLARE v_doctor_id INT;
    DECLARE v_test_type VARCHAR(100);
    DECLARE v_current_status VARCHAR(20);
    DECLARE v_patient_name VARCHAR(200);
    DECLARE v_doc_user_id INT;

    SELECT patient_id, doctor_id, test_type, status
    INTO v_patient_id, v_doctor_id, v_test_type, v_current_status
    FROM Lab_Orders
    WHERE lab_id = p_lab_id;

    IF v_patient_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lab order does not exist.';
    END IF;

    IF v_current_status = 'Completed' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lab order has already been completed.';
    END IF;

    UPDATE Lab_Orders
    SET status = 'Completed',
        results_text = p_results_text,
        updated_at = NOW()
    WHERE lab_id = p_lab_id;

    SELECT CONCAT(first_name, ' ', last_name) INTO v_patient_name
    FROM Patients
    WHERE patient_id = v_patient_id;

    SELECT user_id INTO v_doc_user_id
    FROM Staff
    WHERE staff_id = v_doctor_id;

    IF v_doc_user_id IS NOT NULL THEN
        INSERT INTO Notifications (title, message, type, target_role, target_user_id, details, created_at)
        VALUES (
            'LAB TEST COMPLETED',
            CONCAT('Results completed for ', v_test_type, ' (Patient: ', COALESCE(v_patient_name, CONCAT('ID #', v_patient_id)), ').'),
            'LAB_RESULT_COMPLETED',
            'doctor',
            v_doc_user_id,
            JSON_OBJECT('lab_id', p_lab_id, 'patient_id', v_patient_id, 'test_type', v_test_type),
            NOW()
        );
    END IF;

    SELECT 
        lab_id,
        patient_id,
        doctor_id,
        test_type,
        status,
        results_text,
        DATE_FORMAT(updated_at, '%Y-%m-%d %H:%i') AS updated_at
    FROM Lab_Orders
    WHERE lab_id = p_lab_id;
END //

DELIMITER ;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_pending_lab_count //

CREATE PROCEDURE sp_get_pending_lab_count()
BEGIN
    SELECT COUNT(*) AS pending_count
    FROM Lab_Orders
    WHERE status = 'Pending';
END //

DELIMITER ;



