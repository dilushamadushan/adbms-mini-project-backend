DROP PROCEDURE IF EXISTS sp_rotate_refresh_token;
DROP PROCEDURE IF EXISTS sp_revoke_all_user_sessions;
DROP PROCEDURE IF EXISTS sp_cleanup_expired_tokens;
DROP PROCEDURE IF EXISTS sp_get_department_hierarchy;
DROP PROCEDURE IF EXISTS sp_generate_workload_report;
DROP PROCEDURE IF EXISTS sp_get_hospital_kpi_overview;
DROP PROCEDURE IF EXISTS sp_recep_get_appointments;
DROP PROCEDURE IF EXISTS sp_recep_search_patients_by_name;

DROP PROCEDURE IF EXISTS sp_add_or_update_medicine;
DROP PROCEDURE IF EXISTS sp_receive_stock;
DROP PROCEDURE IF EXISTS sp_update_purchase_order_status;
DROP PROCEDURE IF EXISTS sp_receive_and_restock_purchase_order;
DROP PROCEDURE IF EXISTS sp_get_stock_receipts_history;
DROP PROCEDURE IF EXISTS sp_create_nurse_indexes;

DROP PROCEDURE IF EXISTS CheckDoctorExists;
DROP PROCEDURE IF EXISTS GetAppointmentsByDoctor;
DROP PROCEDURE IF EXISTS GetAppointmentHistoryByDoctor;
DROP PROCEDURE IF EXISTS sp_get_upcoming_appointments_by_doctor;
DROP PROCEDURE IF EXISTS sp_doctor_appointments;
DROP PROCEDURE IF EXISTS GetPatientDetails;
DROP PROCEDURE IF EXISTS get_patient_appointment_details;
DROP PROCEDURE IF EXISTS sp_create_admission_request;
DROP PROCEDURE IF EXISTS request_discharge;
DROP PROCEDURE IF EXISTS sp_create_prescription;
DROP PROCEDURE IF EXISTS sp_create_admitted_prescription;
DROP PROCEDURE IF EXISTS sp_create_lab_order;
DROP PROCEDURE IF EXISTS sp_get_doctor_current_schedule;
DROP PROCEDURE IF EXISTS sp_get_available_slots;
DROP PROCEDURE IF EXISTS sp_book_appointment;

DROP PROCEDURE IF EXISTS sp_get_nurse_ward_beds;
DROP PROCEDURE IF EXISTS sp_get_nurse_dashboard_stats;
DROP PROCEDURE IF EXISTS sp_get_bed_details;
DROP PROCEDURE IF EXISTS sp_record_patient_vitals;
DROP PROCEDURE IF EXISTS sp_get_patient_mar;
DROP PROCEDURE IF EXISTS sp_administer_medication;
DROP PROCEDURE IF EXISTS sp_get_doctor_orders;
DROP PROCEDURE IF EXISTS sp_acknowledge_doctor_order;
DROP PROCEDURE IF EXISTS sp_get_nursing_notes;
DROP PROCEDURE IF EXISTS sp_add_nursing_note;
DROP PROCEDURE IF EXISTS sp_log_intake_output;
DROP PROCEDURE IF EXISTS sp_get_patient_io_summary;
DROP PROCEDURE IF EXISTS sp_get_ward_nurses;
DROP PROCEDURE IF EXISTS sp_update_bed_status;
DROP PROCEDURE IF EXISTS sp_complete_patient_discharge;
DROP PROCEDURE IF EXISTS sp_get_unassigned_admissions;
DROP PROCEDURE IF EXISTS sp_nurse_assign_bed;
DROP PROCEDURE IF EXISTS sp_get_nurse_lab_orders;
DROP PROCEDURE IF EXISTS sp_complete_lab_order;
DROP PROCEDURE IF EXISTS sp_get_pending_lab_count;
DROP PROCEDURE IF EXISTS sp_extend_vitals_schema;
DROP PROCEDURE IF EXISTS sp_deactivate_prescription;
DROP PROCEDURE IF EXISTS sp_get_patient_rx_summary;
DROP PROCEDURE IF EXISTS sp_get_patient_medical_history;

DELIMITER //

-- TG/1407 --

CREATE PROCEDURE sp_rotate_refresh_token(
    IN p_old_token_hash VARCHAR(255),
    IN p_new_token_hash VARCHAR(255),
    IN p_new_expires_at DATETIME
)
BEGIN
    DECLARE v_token_id INT;
    DECLARE v_user_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT token_id, user_id INTO v_token_id, v_user_id
    FROM Refresh_Tokens
    WHERE token_hash = p_old_token_hash
      AND revoked = FALSE
      AND expires_at > NOW()
    FOR UPDATE;

    IF v_token_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Refresh token is invalid, revoked, or expired';
    END IF;

    UPDATE Refresh_Tokens
    SET revoked = TRUE
    WHERE token_id = v_token_id;

    INSERT INTO Refresh_Tokens (user_id, token_hash, expires_at, revoked)
    VALUES (v_user_id, p_new_token_hash, p_new_expires_at, FALSE);

    SELECT u.user_id, u.username, u.role
    FROM Users u
    WHERE u.user_id = v_user_id;

    COMMIT;
END //

CREATE PROCEDURE sp_revoke_all_user_sessions(
    IN p_user_id INT,
    OUT p_revoked_count INT
)
BEGIN
    DELETE FROM Refresh_Tokens
    WHERE user_id = p_user_id;

    SET p_revoked_count = ROW_COUNT();
END //

CREATE PROCEDURE sp_cleanup_expired_tokens(
    IN p_older_than_days INT,
    OUT p_deleted_count INT
)
BEGIN
    DELETE FROM Refresh_Tokens
    WHERE (revoked = TRUE OR expires_at < NOW())
      AND created_at < (NOW() - INTERVAL p_older_than_days DAY);

    SET p_deleted_count = ROW_COUNT();
END //

CREATE PROCEDURE sp_get_department_hierarchy()
BEGIN
    WITH RECURSIVE DepartmentHierarchy AS (
        SELECT 
            d.dept_id,
            d.dept_name,
            d.parent_dept_id,
            CAST(d.dept_name AS CHAR(500)) AS hierarchy_path,
            0 AS depth_level
        FROM Departments d
        WHERE d.parent_dept_id IS NULL

        UNION ALL

        SELECT 
            c.dept_id,
            c.dept_name,
            c.parent_dept_id,
            CONCAT(p.hierarchy_path, ' -> ', c.dept_name) AS hierarchy_path,
            p.depth_level + 1 AS depth_level
        FROM Departments c
        INNER JOIN DepartmentHierarchy p ON c.parent_dept_id = p.dept_id
    )
    SELECT 
        dh.dept_id,
        dh.dept_name,
        dh.parent_dept_id,
        dh.hierarchy_path,
        dh.depth_level,
        COUNT(s.staff_id) AS staff_count
    FROM DepartmentHierarchy dh
    LEFT JOIN Staff s ON dh.dept_id = s.dept_id
    GROUP BY dh.dept_id, dh.dept_name, dh.parent_dept_id, dh.hierarchy_path, dh.depth_level
    ORDER BY dh.hierarchy_path ASC;
END //

CREATE PROCEDURE sp_generate_workload_report(
    IN p_start_date DATE,
    IN p_end_date DATE,
    IN p_top_n INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        RESIGNAL;
    END;

    WITH DeptAggregates AS (
        SELECT 
            d.dept_id,
            d.dept_name,
            COUNT(DISTINCT s.staff_id) AS doctor_count,
            COUNT(a.apt_id) AS total_appointments,
            COUNT(DISTINCT a.patient_id) AS pts_seen,
            SUM(COUNT(a.apt_id)) OVER () AS hospital_total_appts
        FROM Departments d
        LEFT JOIN Staff s ON s.dept_id = d.dept_id
        LEFT JOIN Appointments a ON a.dept_id = d.dept_id
            AND (p_start_date IS NULL OR a.apt_date >= p_start_date)
            AND (p_end_date IS NULL OR a.apt_date <= p_end_date)
        GROUP BY d.dept_id, d.dept_name
    ),
    DeptWorkloadMetrics AS (
        SELECT 
            dept_id,
            dept_name,
            doctor_count,
            total_appointments,
            pts_seen,
            ROUND(
                COALESCE((total_appointments * 100.0) / NULLIF(hospital_total_appts, 0), 0),
                1
            ) AS workload_percentage,
            DENSE_RANK() OVER (ORDER BY total_appointments DESC) AS dept_rank
        FROM DeptAggregates
    )
    SELECT 
        dept_id,
        dept_name,
        doctor_count,
        total_appointments,
        pts_seen,
        workload_percentage,
        dept_rank,
        fn_get_workload_level(total_appointments, workload_percentage) AS workload_level
    FROM DeptWorkloadMetrics
    ORDER BY total_appointments DESC, dept_name ASC;

    WITH ProviderAggregates AS (
        SELECT 
            s.staff_id,
            CONCAT('Dr. ', s.first_name, ' ', s.last_name) AS provider_name,
            s.specialty,
            d.dept_name,
            COUNT(a.apt_id) AS pts_seen,
            fn_calculate_provider_avg_time(s.staff_id) AS avg_time_minutes,
            SUM(COUNT(a.apt_id)) OVER () AS total_provider_appts
        FROM Staff s
        LEFT JOIN Departments d ON s.dept_id = d.dept_id
        LEFT JOIN Appointments a ON a.doctor_id = s.staff_id
            AND (p_start_date IS NULL OR a.apt_date >= p_start_date)
            AND (p_end_date IS NULL OR a.apt_date <= p_end_date)
        GROUP BY s.staff_id, s.first_name, s.last_name, s.specialty, d.dept_name
    ),
    RankedProviders AS (
        SELECT 
            staff_id,
            provider_name,
            specialty,
            dept_name,
            pts_seen,
            avg_time_minutes,
            CONCAT(avg_time_minutes, 'm') AS avg_time_formatted,
            DENSE_RANK() OVER (ORDER BY pts_seen DESC) AS workload_rank,
            ROUND(
                COALESCE((pts_seen * 100.0) / NULLIF(total_provider_appts, 0), 0),
                1
            ) AS share_percentage
        FROM ProviderAggregates
    )
    SELECT 
        staff_id,
        provider_name,
        specialty,
        dept_name,
        pts_seen,
        avg_time_minutes,
        avg_time_formatted,
        workload_rank,
        share_percentage
    FROM RankedProviders
    WHERE pts_seen > 0
    ORDER BY workload_rank ASC, pts_seen DESC
    LIMIT p_top_n;

END //

CREATE PROCEDURE sp_get_hospital_kpi_overview(
    IN p_target_date DATE
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        RESIGNAL;
    END;

    IF p_target_date IS NULL THEN
        SET p_target_date = CURDATE();
    END IF;

    WITH ApptStats AS (
        SELECT
            COUNT(*)                                                 AS total_appointments,
            SUM(CASE WHEN status = 'Scheduled' THEN 1 ELSE 0 END)  AS scheduled_count,
            SUM(CASE WHEN status = 'Completed' THEN 1 ELSE 0 END)  AS completed_count,
            SUM(CASE WHEN status = 'Cancelled' THEN 1 ELSE 0 END)  AS cancelled_count,
            SUM(CASE WHEN status = 'No-Show'   THEN 1 ELSE 0 END)  AS no_show_count
        FROM Appointments
        WHERE apt_date = p_target_date
    )
    SELECT
        (SELECT COUNT(*) FROM Patients)                             AS total_patients,

        (SELECT COUNT(*) FROM Beds)                                 AS total_beds,
        (SELECT COUNT(*) FROM Beds WHERE status = 'Occupied')       AS occupied_beds,
        (SELECT COUNT(*) FROM Beds WHERE status = 'Available')      AS available_beds,
        (SELECT COUNT(*) FROM Beds WHERE status = 'Cleaning')       AS cleaning_beds,

        fn_bed_occupancy_pct(NULL)                                  AS bed_occupancy_pct,
        CONCAT(ROUND(fn_bed_occupancy_pct(NULL), 1), '%')           AS bed_occupancy_formatted,

        a.total_appointments                                        AS todays_appointments,
        a.scheduled_count                                           AS scheduled_today,
        a.completed_count                                           AS completed_today,
        a.cancelled_count                                           AS cancelled_today,
        a.no_show_count                                             AS no_show_today,

        p_target_date                                               AS target_date
    FROM ApptStats a;

END //

-- Chavi --

CREATE PROCEDURE sp_recep_get_appointments(
    IN p_appointment_id INT,
    IN p_patient_id INT,
    IN p_appointment_date DATE,
    IN p_patient_name VARCHAR(201)
)
BEGIN
    SELECT apt_id, patient_id, patient_name, doctor_id, doctor_name,
           dept_id, dept_name, apt_date, time_slot, status
    FROM vw_recep_appointments
    WHERE (p_appointment_id IS NULL OR apt_id = p_appointment_id)
      AND (p_patient_id IS NULL OR patient_id = p_patient_id)
      AND (p_appointment_date IS NULL OR apt_date = p_appointment_date)
      AND (
          p_patient_name IS NULL
          OR TRIM(p_patient_name) = ''
          OR patient_name LIKE CONCAT('%', TRIM(p_patient_name), '%')
      )
    ORDER BY apt_date, time_slot;
END //

CREATE PROCEDURE sp_recep_search_patients_by_name(IN p_name VARCHAR(201))
BEGIN
    DECLARE v_name VARCHAR(201);
    DECLARE v_first_name VARCHAR(100);
    DECLARE v_last_name VARCHAR(100);

    SET v_name = TRIM(p_name);
    SET v_first_name = SUBSTRING_INDEX(v_name, ' ', 1);
    SET v_last_name = TRIM(SUBSTRING(v_name, CHAR_LENGTH(v_first_name) + 1));

    SELECT p.patient_id, p.user_id, u.username, u.email,
           p.first_name, p.last_name, p.dob, p.blood_group,
           p.emergency_contact, p.allergies
    FROM Patients p
    JOIN Users u ON u.user_id = p.user_id
    WHERE LOWER(u.role) = 'patient'
      AND (
          (
              p.first_name LIKE CONCAT(v_first_name, '%')
              AND (v_last_name = '' OR p.last_name LIKE CONCAT(v_last_name, '%'))
          )
          OR (
              v_last_name = ''
              AND p.last_name LIKE CONCAT(v_first_name, '%')
          )
      )
    ORDER BY p.last_name, p.first_name;
END //

-- thimira --

CREATE PROCEDURE sp_add_or_update_medicine(
    IN p_medicine_id INT,
    IN p_med_name VARCHAR(100),
    IN p_generic_name VARCHAR(100),
    IN p_unit_price DECIMAL(10,2),
    IN p_stock_qty INT,
    IN p_reorder_level INT,
    IN p_expiry_date DATE,
    IN p_is_active BOOLEAN,
    OUT p_out_id INT
)
BEGIN
    IF p_medicine_id IS NULL OR p_medicine_id = 0 THEN
        INSERT INTO Medicines (
            med_name, generic_name, unit_price, stock_qty, 
            reorder_level, expiry_date, is_active
        ) VALUES (
            p_med_name, p_generic_name, p_unit_price, COALESCE(p_stock_qty, 0),
            COALESCE(p_reorder_level, 20), p_expiry_date, COALESCE(p_is_active, TRUE)
        );
        SET p_out_id = LAST_INSERT_ID();
    ELSE
        UPDATE Medicines
        SET 
            med_name = p_med_name,
            generic_name = p_generic_name,
            unit_price = p_unit_price,
            stock_qty = COALESCE(p_stock_qty, stock_qty),
            reorder_level = COALESCE(p_reorder_level, reorder_level),
            expiry_date = COALESCE(p_expiry_date, expiry_date),
            is_active = COALESCE(p_is_active, is_active)
        WHERE medicine_id = p_medicine_id;
        SET p_out_id = p_medicine_id;
    END IF;
END //

CREATE PROCEDURE sp_receive_stock(
    IN p_medicine_id INT,
    IN p_quantity INT,
    IN p_expiry_date DATE,
    IN p_received_by INT,
    OUT p_receipt_id INT
)
BEGIN
    IF p_quantity <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Quantity received must be greater than zero.';
    END IF;

    INSERT INTO Stock_Receipts (
        medicine_id, quantity, expiry_date, received_by, received_at
    ) VALUES (
        p_medicine_id, p_quantity, p_expiry_date, p_received_by, NOW()
    );

    SET p_receipt_id = LAST_INSERT_ID();
END //

CREATE PROCEDURE sp_update_purchase_order_status(
    IN p_order_id INT,
    IN p_status VARCHAR(30)
)
BEGIN
    DECLARE v_order_date DATETIME;
    DECLARE v_expected_date DATE;

    IF p_status = 'RECEIVED' THEN
        SELECT order_date, expected_delivery_date 
        INTO v_order_date, v_expected_date
        FROM Purchase_Orders
        WHERE order_id = p_order_id;

        IF DATEDIFF(CURDATE(), DATE(v_order_date)) < 1 AND CURDATE() < v_expected_date THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot confirm stock receipt before 1 day from the order date. The order is still in transit from the supplier.';
        END IF;
    END IF;

    UPDATE Purchase_Orders
    SET status = p_status
    WHERE order_id = p_order_id;
END //

CREATE PROCEDURE sp_receive_and_restock_purchase_order(
    IN p_order_id INT,
    IN p_staff_id INT,
    IN p_batch_expiry_date DATE
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_med_id INT;
    DECLARE v_qty INT;
    DECLARE v_order_num VARCHAR(50);
    DECLARE v_cur_status VARCHAR(30);
    DECLARE v_order_date DATETIME;
    DECLARE v_expected_date DATE;

    DECLARE cur_items CURSOR FOR 
        SELECT medicine_id, requested_quantity 
        FROM Purchase_Order_Items 
        WHERE order_id = p_order_id;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    SELECT order_number, status, order_date, expected_delivery_date 
    INTO v_order_num, v_cur_status, v_order_date, v_expected_date
    FROM Purchase_Orders
    WHERE order_id = p_order_id;

    IF v_cur_status = 'RECEIVED' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'This purchase order has already been received and restocked.';
    END IF;

    IF DATEDIFF(CURDATE(), DATE(v_order_date)) < 1 AND CURDATE() < v_expected_date THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot confirm stock receipt before 1 day from the order date. The order is still in transit from the supplier.';
    END IF;

    SET p_batch_expiry_date = COALESCE(p_batch_expiry_date, DATE_ADD(CURDATE(), INTERVAL 1 YEAR));

    OPEN cur_items;

    read_loop: LOOP
        FETCH cur_items INTO v_med_id, v_qty;
        IF done THEN
            LEAVE read_loop;
        END IF;

        INSERT INTO Stock_Receipts (medicine_id, quantity, expiry_date, received_by, received_at)
        VALUES (v_med_id, v_qty, p_batch_expiry_date, p_staff_id, NOW());
    END LOOP;

    CLOSE cur_items;

    UPDATE Purchase_Orders
    SET status = 'RECEIVED'
    WHERE order_id = p_order_id;

    INSERT INTO Notifications (title, message, type, target_role, details, created_at)
    VALUES (
        'Order Restocked',
        CONCAT('Restock order "', v_order_num, '" has been verified and items added to active inventory.'),
        'STOCK_RESTOCKED',
        'pharmacist',
        JSON_OBJECT('order_id', p_order_id, 'order_number', v_order_num),
        NOW()
    );
END //

CREATE PROCEDURE sp_get_stock_receipts_history(
    IN p_limit INT
)
BEGIN
    SET p_limit = COALESCE(p_limit, 50);

    SELECT 
        sr.receipt_id,
        sr.medicine_id,
        m.med_name,
        m.generic_name,
        sr.quantity,
        sr.expiry_date,
        sr.received_by,
        CONCAT(s.first_name, ' ', s.last_name) AS received_by_name,
        sr.received_at
    FROM Stock_Receipts sr
    JOIN Medicines m ON sr.medicine_id = m.medicine_id
    LEFT JOIN Staff s ON sr.received_by = s.staff_id
    ORDER BY sr.received_at DESC
    LIMIT p_limit;
END //







-- ishan --

-- =========================================================
-- DOCTOR APPOINTMENT MANAGEMENT
-- =========================================================

-- check if doctor exists
CREATE PROCEDURE CheckDoctorExists(
    IN p_doctor_id INT
)
BEGIN
    SELECT COUNT(*) AS doctor_count
    FROM staff
    WHERE staff_id = p_doctor_id;
END //

-- =========================================================
-- 1. GET TODAY'S APPOINTMENTS FOR A DOCTOR
-- =========================================================
CREATE PROCEDURE GetAppointmentsByDoctor(
    IN p_doctor_id INT
)
BEGIN
    SELECT
        a.apt_id,
        a.patient_id,
        CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
        p.dob,
        p.blood_group,
        p.allergies,
        a.dept_id,
        d.dept_name,
        a.apt_date,
        TIME_FORMAT(a.time_slot, '%H:%i') AS time_slot,
        a.status
    FROM Appointments AS a
    INNER JOIN Patients AS p
        ON a.patient_id = p.patient_id
    INNER JOIN Departments AS d
        ON a.dept_id = d.dept_id
    WHERE a.doctor_id = p_doctor_id
      AND DATE(a.apt_date) = CURDATE()
    ORDER BY
        a.apt_date ASC,
        a.time_slot ASC;
END //

-- =========================================================
-- 2. GET APPOINTMENT HISTORY FOR A DOCTOR
-- =========================================================
CREATE PROCEDURE GetAppointmentHistoryByDoctor(
    IN p_doctor_id INT
)
BEGIN
    SELECT
        a.apt_id,
        a.patient_id,
        CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
        p.dob,
        p.blood_group,
        p.allergies,
        a.dept_id,
        d.dept_name,
        a.apt_date,
        TIME_FORMAT(a.time_slot, '%H:%i') AS time_slot,
        a.status
    FROM Appointments AS a
    INNER JOIN Patients AS p
        ON a.patient_id = p.patient_id
    INNER JOIN Departments AS d
        ON a.dept_id = d.dept_id
    WHERE a.doctor_id = p_doctor_id
      AND a.apt_date < CURDATE()
    ORDER BY
        a.apt_date DESC,
        a.time_slot DESC;
END //

-- =========================================================
-- 3. GET UPCOMING APPOINTMENTS FOR A DOCTOR
-- =========================================================
CREATE PROCEDURE sp_get_upcoming_appointments_by_doctor(
    IN p_doctor_id INT
)
BEGIN
    SELECT
        a.apt_id,
        p.patient_id,
        CONCAT(p.first_name, ' ', p.last_name) AS patient_name,

        TIMESTAMPDIFF(YEAR, p.dob, CURDATE()) AS age,

        a.apt_date,
        a.time_slot,
        a.status,

        d.dept_name AS reason

    FROM Appointments a

    JOIN Patients p
        ON a.patient_id = p.patient_id

    JOIN Departments d
        ON a.dept_id = d.dept_id

    WHERE a.doctor_id = p_doctor_id
      AND a.status = 'Scheduled'
      AND TIMESTAMP(a.apt_date, a.time_slot) > NOW()

    ORDER BY
        a.apt_date ASC,
        a.time_slot ASC;

END //

-- =========================================================
-- 3b. GET APPOINTMENTS GROUPED (TODAY, UPCOMING, PAST) BY DOCTOR USER ID
-- =========================================================
CREATE PROCEDURE sp_doctor_appointments(IN p_user_id INT)
BEGIN
    SELECT a.apt_id,
           p.patient_id,
           CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
           a.apt_date,
           TIME_FORMAT(a.time_slot, '%h:%i %p')   AS appointment_time,
           a.status,
           CASE
               WHEN a.apt_date = CURDATE() THEN 'Today'
               WHEN a.apt_date > CURDATE() THEN 'Upcoming'
               ELSE 'Past'
           END AS day_group
    FROM appointments a
    JOIN patients p ON p.patient_id = a.patient_id
    JOIN staff s    ON s.staff_id   = a.doctor_id
    WHERE s.user_id = p_user_id
    ORDER BY
        CASE WHEN a.apt_date = CURDATE() THEN 0
             WHEN a.apt_date > CURDATE() THEN 1
             ELSE 2 END,                                   -- Today, Upcoming, Past
        CASE WHEN a.apt_date >= CURDATE() THEN a.apt_date END ASC,   -- future: nearest first
        CASE WHEN a.apt_date <  CURDATE() THEN a.apt_date END DESC,  -- past: latest first
        a.time_slot ASC;
END //

-- get full details of one patient
CREATE PROCEDURE GetPatientDetails(
    IN p_patient_id INT
)
BEGIN
    SELECT p.patient_id,
           CONCAT(p.first_name, ' ', p.last_name)            AS patient_name,
           (SELECT ad.gender
              FROM admissions ad
             WHERE ad.patient_id = p.patient_id
             ORDER BY ad.admitted_at DESC
             LIMIT 1)                                        AS gender,
           TIMESTAMPDIFF(YEAR, p.dob, CURDATE())             AS age,
           DATE_FORMAT(p.dob, '%d %b %Y')                    AS dob,
           p.emergency_contact                               AS phone,
           p.blood_group,
           COALESCE(NULLIF(p.allergies, ''), 'None recorded') AS allergies
    FROM patients p
    WHERE p.patient_id = p_patient_id;
END //

-- get appointment overview (date, time, reason)
CREATE PROCEDURE get_patient_appointment_details(
    IN p_apt_id INT
)
BEGIN
    SELECT DATE_FORMAT(a.apt_date, '%a, %d %b %Y') AS apt_date,
           TIME_FORMAT(a.time_slot, '%h:%i %p')    AS apt_time,
           d.dept_name                             AS reason
    FROM appointments a
    JOIN departments d ON d.dept_id = a.dept_id
    WHERE a.apt_id = p_apt_id;
END //

CREATE PROCEDURE sp_create_admission_request(
    IN p_patient_id INT,
    IN p_gender     VARCHAR(10),
    IN p_ward_id    INT,
    IN p_reason     TEXT,
    IN p_doctor_id  INT,    -- attending doctor's staff_id
    IN p_user_id    INT     -- logged-in user sending the request
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM patients WHERE patient_id = p_patient_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Patient not found';
    END IF;

    -- NEW: patient already has a waiting request
    IF EXISTS (SELECT 1
                 FROM admissions
                WHERE patient_id = p_patient_id
                  AND status = 'Pending') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Patient already has a pending admission request';
    END IF;

    -- NEW: patient is currently admitted (admitted and not yet discharged)
    IF EXISTS (SELECT 1
                 FROM admissions a
                 LEFT JOIN discharges d
                        ON d.admission_id = a.admission_id
                       AND d.status = 'Discharged'
                WHERE a.patient_id = p_patient_id
                  AND a.status = 'Admitted'
                  AND d.discharge_id IS NULL) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Patient is already admitted';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM wards WHERE ward_id = p_ward_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ward not found';
    END IF;

    IF NOT EXISTS (SELECT 1
                     FROM staff s
                     JOIN users u ON u.user_id = s.user_id
                    WHERE s.staff_id = p_doctor_id
                      AND u.role = 'doctor') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Doctor not found';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_user_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User not found';
    END IF;

    IF p_gender NOT IN ('Female', 'Male') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Gender must be Female or Male';
    END IF;

    IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reason for admission is required';
    END IF;

    INSERT INTO admissions
        (patient_id, ward_id, admitted_doctor_id, admitted_by,
         admission_reason, gender, guardian_name, guardian_contact)
    VALUES
        (p_patient_id, p_ward_id, p_doctor_id, p_user_id,
         TRIM(p_reason), p_gender, '', '');

    SELECT LAST_INSERT_ID() AS admission_id;
END //

-- =====================================================
-- 4. PROCEDURE - ONE-STEP DISCHARGE
--    Fills authorization AND final discharge details instantly
-- =====================================================
CREATE PROCEDURE request_discharge(
  IN p_admission_id INT,
  IN p_user_id INT,
  IN p_notes TEXT
)
BEGIN
  DECLARE v_doctor_staff_id INT DEFAULT NULL;

  -- Find the doctor Staff ID from the logged-in User ID
  SELECT s.staff_id
  INTO v_doctor_staff_id
  FROM Users AS u
  INNER JOIN Staff AS s
    ON s.user_id = u.user_id
  WHERE u.user_id = p_user_id
    AND LOWER(u.role) = 'doctor'
    AND u.is_active = TRUE
  LIMIT 1;

  -- Stop if the user is not an active doctor
  IF v_doctor_staff_id IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Active doctor user not found';
  END IF;

  -- 1. Check if admission is valid and not already discharged
  IF NOT EXISTS (SELECT 1 FROM `admissions`
                 WHERE admission_id = p_admission_id AND status <> 'Discharged') THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Admission not found or already discharged';
  END IF;

  -- 2. Insert into discharges WITH the final completion details included
  INSERT INTO `discharges` (
    admission_id, 
    discharge_authorized_by, 
    discharge_notes,
    status,           
    discharged_by,    
    discharged_at     
  )
  VALUES (
    p_admission_id, 
    v_doctor_staff_id,
    p_notes,
    'Authorized',
    p_user_id,
    NULL
  );
END //

-- It checks the data, then saves the medical record and
-- all the medicines together. If anything is wrong, it
-- saves nothing and shows an error message.
-- =====================================================
CREATE PROCEDURE sp_create_prescription(
  IN p_patient_id INT,        -- which patient
  IN p_apt_id INT,            -- which appointment
  IN p_doctor_id INT,         -- the doctor's staff_id
  IN p_diagnosis TEXT,        -- what is wrong
  IN p_clinical_notes TEXT,   -- doctor's notes
  IN p_medicines JSON         -- list of medicines from the form
)
BEGIN
  DECLARE v_record_id INT;

  -- If any error happens, undo everything and show the error
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  -- CHECK 1: diagnosis must not be empty
  IF p_diagnosis IS NULL OR TRIM(p_diagnosis) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Diagnosis is required';
  END IF;

  -- CHECK 2: there must be at least one medicine
  IF p_medicines IS NULL OR JSON_LENGTH(p_medicines) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'At least one medicine is required';
  END IF;

  -- CHECK 3: the doctor must be a real doctor
  IF NOT EXISTS (SELECT 1 FROM staff s JOIN users u ON u.user_id = s.user_id
                 WHERE s.staff_id = p_doctor_id AND u.role = 'doctor') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Doctor not found';
  END IF;

  -- CHECK 4: the appointment must belong to this doctor and this patient
  IF NOT EXISTS (SELECT 1 FROM appointments
                 WHERE apt_id = p_apt_id AND patient_id = p_patient_id
                   AND doctor_id = p_doctor_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Appointment not found for this doctor and patient';
  END IF;

  -- CHECK 5: the patient must NOT be admitted right now
  IF EXISTS (SELECT 1 FROM admissions
             WHERE patient_id = p_patient_id AND status = 'Admitted') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Patient is currently admitted. Use the admission flow.';
  END IF;

  START TRANSACTION;   -- from here, everything is saved together or not at all

  -- SAVE 1: the medical record (this fires the trigger in section 4)
  INSERT INTO medical_records (patient_id, doctor_id, apt_id, diagnosis, clinical_notes)
  VALUES (p_patient_id, p_doctor_id, p_apt_id, TRIM(p_diagnosis), p_clinical_notes);
  SET v_record_id = LAST_INSERT_ID();   -- remember the new record_id

  -- SAVE 2: one prescription row for each medicine
  -- med_name comes from the medicines table (so the spelling is always right)
  -- dosage = dose + frequency, for example "500 mg, Three times daily"
  INSERT INTO prescriptions (record_id, med_name, dosage, duration)
  SELECT v_record_id, m.med_name,
         CONCAT(TRIM(j.dose), ', ', TRIM(j.frequency)), TRIM(j.duration)
  FROM JSON_TABLE(p_medicines, '$[*]' COLUMNS (
         medicine_id INT          PATH '$.medicine_id',
         dose        VARCHAR(50)  PATH '$.dose',
         frequency   VARCHAR(50)  PATH '$.frequency',
         duration    VARCHAR(50)  PATH '$.duration')) AS j
  JOIN medicines m ON m.medicine_id = j.medicine_id
  WHERE TRIM(COALESCE(j.dose, '')) <> ''
    AND TRIM(COALESCE(j.frequency, '')) <> ''
    AND TRIM(COALESCE(j.duration, '')) <> '';

  -- CHECK 6: every medicine sent must have been saved
  -- (if one had an empty dose or a wrong medicine_id, the counts differ)
  IF ROW_COUNT() <> JSON_LENGTH(p_medicines) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Each medicine needs a valid medicine, dose, frequency and duration';
  END IF;

  COMMIT;                              -- make it permanent
  SELECT v_record_id AS record_id;     -- send the new record_id back
END //

-- WHY:  Runs when the doctor clicks "Save for admission" for an admitted patient.
-- WHAT: Checks the data first. If all is fine, it saves 4 things together:
--         1. medical_records                     (diagnosis + notes)
--         2. prescriptions                       (one row per medicine)
--         3. medication_administration_records   (one row per medicine, status Not Given)
--         4. doctor_orders                       (nurse instructions, status Pending)
--       If anything is wrong, it saves nothing and shows an error.
CREATE PROCEDURE sp_create_admitted_prescription(
  IN p_patient_id INT,
  IN p_apt_id INT,
  IN p_doctor_id INT,
  IN p_diagnosis TEXT,
  IN p_clinical_notes TEXT,
  IN p_medicines JSON,
  IN p_nurse_orders JSON
)
BEGIN
  DECLARE v_record_id INT;

  -- If any error happens, undo everything and show the error
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  -- CHECK 1: diagnosis must not be empty
  IF p_diagnosis IS NULL OR TRIM(p_diagnosis) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Diagnosis is required';
  END IF;

  -- CHECK 2: at least one medicine is required
  IF p_medicines IS NULL OR JSON_LENGTH(p_medicines) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'At least one medicine is required';
  END IF;

  -- CHECK 3: the same medicine cannot be listed twice
  IF (
    SELECT COUNT(DISTINCT d.medicine_id)
    FROM JSON_TABLE(
      p_medicines,
      '$[*]' COLUMNS (medicine_id INT PATH '$.medicine_id')
    ) AS d
  ) <> JSON_LENGTH(p_medicines) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The same medicine is listed more than once';
  END IF;

  -- CHECK 4: doctor must exist
  IF NOT EXISTS (
    SELECT 1
    FROM staff s
    INNER JOIN users u ON u.user_id = s.user_id
    WHERE s.staff_id = p_doctor_id
      AND LOWER(u.role) = 'doctor'
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Doctor not found';
  END IF;

  -- CHECK 5: appointment must belong to this doctor and patient
  IF NOT EXISTS (
    SELECT 1
    FROM appointments
    WHERE apt_id = p_apt_id
      AND patient_id = p_patient_id
      AND doctor_id = p_doctor_id
  ) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Appointment not found for this doctor and patient';
  END IF;

  -- CHECK 6: patient must currently be admitted
  IF NOT EXISTS (
    SELECT 1
    FROM admissions
    WHERE patient_id = p_patient_id
      AND status = 'Admitted'
  ) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Patient is not admitted. Use the normal prescription.';
  END IF;

  START TRANSACTION;   -- everything below is saved together or not at all

  -- SAVE 1: Medical record
  INSERT INTO medical_records (patient_id, doctor_id, apt_id, diagnosis, clinical_notes)
  VALUES (p_patient_id, p_doctor_id, p_apt_id, TRIM(p_diagnosis), p_clinical_notes);

  SET v_record_id = LAST_INSERT_ID();

  -- SAVE 2: Prescriptions (one row per medicine)
  INSERT INTO prescriptions (record_id, med_name, dosage, duration)
  SELECT
    v_record_id,
    m.med_name,
    CONCAT(TRIM(j.dose), ', ', TRIM(j.frequency)),
    TRIM(j.duration)
  FROM JSON_TABLE(
    p_medicines,
    '$[*]' COLUMNS (
      medicine_id INT PATH '$.medicine_id',
      dose        VARCHAR(50) PATH '$.dose',
      frequency   VARCHAR(50) PATH '$.frequency',
      duration    VARCHAR(50) PATH '$.duration'
    )
  ) AS j
  INNER JOIN medicines m ON m.medicine_id = j.medicine_id
  WHERE TRIM(COALESCE(j.dose, '')) <> ''
    AND TRIM(COALESCE(j.frequency, '')) <> ''
    AND TRIM(COALESCE(j.duration, '')) <> '';

  -- CHECK 7: every medicine must be saved
  IF ROW_COUNT() <> JSON_LENGTH(p_medicines) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Each medicine needs a valid medicine, dose, frequency and duration';
  END IF;

  -- SAVE 3: Dose-tracking rows, status Not Given (nurse updates later)
  INSERT INTO medication_administration_records (
    rx_id, patient_id, administered_by, scheduled_time, status, notes
  )
  SELECT
    rx.rx_id,
    p_patient_id,
    p_doctor_id,
    COALESCE(NULLIF(TRIM(j.first_dose), ''), '08:00'),
    'Not Given',
    NULLIF(TRIM(j.notes), '')
  FROM JSON_TABLE(
    p_medicines,
    '$[*]' COLUMNS (
      medicine_id INT PATH '$.medicine_id',
      first_dose  VARCHAR(20) PATH '$.first_dose',
      notes       TEXT PATH '$.notes'
    )
  ) AS j
  INNER JOIN medicines m ON m.medicine_id = j.medicine_id
  INNER JOIN prescriptions rx
    ON rx.med_name = m.med_name
   AND rx.record_id = v_record_id;

  -- CHECK 8: every prescription needs a dose row
  IF ROW_COUNT() <> JSON_LENGTH(p_medicines) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Could not create the dose tracking rows';
  END IF;

  -- SAVE 4: Nurse instructions (optional), status Pending
  IF p_nurse_orders IS NOT NULL AND JSON_LENGTH(p_nurse_orders) > 0 THEN

    INSERT INTO doctor_orders (patient_id, doctor_id, order_type, instruction)
    SELECT p_patient_id, p_doctor_id, o.order_type, TRIM(o.instruction)
    FROM JSON_TABLE(
      p_nurse_orders,
      '$[*]' COLUMNS (
        order_type  VARCHAR(20) PATH '$.order_type',
        instruction TEXT PATH '$.instruction'
      )
    ) AS o
    WHERE o.order_type IN ('Medication','Lab','Diet','IV_Fluids','Nursing_Care','Special')
      AND TRIM(COALESCE(o.instruction, '')) <> '';

    -- CHECK 9: every nurse instruction must be saved
    IF ROW_COUNT() <> JSON_LENGTH(p_nurse_orders) THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Each nurse instruction needs a valid order type and instruction';
    END IF;

  END IF;

  COMMIT;                            -- make it permanent
  SELECT v_record_id AS record_id;   -- send the new record_id back
END //

-- Creates a new pending lab order with an empty result.
CREATE PROCEDURE sp_create_lab_order(
    IN p_patient_id INT,
    IN p_doctor_id INT,
    IN p_test_type VARCHAR(100)
)
BEGIN
    DECLARE v_lab_id INT;

    IF NOT EXISTS (
        SELECT 1
        FROM Patients
        WHERE patient_id = p_patient_id
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Patient not found';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM Staff s
        INNER JOIN Users u
            ON u.user_id = s.user_id
        WHERE s.staff_id = p_doctor_id
          AND LOWER(u.role) = 'doctor'
          AND u.is_active = TRUE
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Active doctor not found';
    END IF;

    IF p_test_type IS NULL OR TRIM(p_test_type) = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Test type is required';
    END IF;

    INSERT INTO Lab_Orders (
        patient_id,
        doctor_id,
        test_type,
        status,
        results_text
    )
    VALUES (
        p_patient_id,
        p_doctor_id,
        TRIM(p_test_type),
        'Pending',
        ''
    );

    SET v_lab_id = LAST_INSERT_ID();

    SELECT
        lab_id,
        patient_id,
        doctor_id,
        test_type,
        status,
        results_text,
        ordered_at,
        updated_at
    FROM Lab_Orders
    WHERE lab_id = v_lab_id;
END //

-- =========================================================
-- PROCEDURE: GET CURRENT DAY SCHEDULE FOR A DOCTOR
-- =========================================================
-- Notes:
--   - The procedure automatically uses CURRENT_DATE.
--   - It returns both booked and open slots.
--   - Appointment slots are generated from 09:00 AM to 04:30 PM.
--   - The lunch period from 12:00 PM to 12:30 PM is excluded.
CREATE PROCEDURE sp_get_doctor_current_schedule(
    IN p_doctor_id INT
)
BEGIN

    -- =====================================================
    -- Validate that the supplied doctor exists.
    -- =====================================================
    IF NOT EXISTS (
        SELECT 1
        FROM Staff
        WHERE staff_id = p_doctor_id
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Doctor not found.';
    END IF;


    -- =====================================================
    -- Define the standard clinic appointment slots.
    -- =====================================================
    WITH ClinicSlots AS (

        -- Morning appointment slots
        SELECT TIME('09:00:00') AS slot_time
        UNION ALL SELECT TIME('09:30:00')
        UNION ALL SELECT TIME('10:00:00')
        UNION ALL SELECT TIME('10:30:00')
        UNION ALL SELECT TIME('11:00:00')
        UNION ALL SELECT TIME('11:30:00')

        -- Afternoon appointment slots
        UNION ALL SELECT TIME('13:00:00')
        UNION ALL SELECT TIME('13:30:00')
        UNION ALL SELECT TIME('14:00:00')
        UNION ALL SELECT TIME('14:30:00')
        UNION ALL SELECT TIME('15:00:00')
        UNION ALL SELECT TIME('15:30:00')
        UNION ALL SELECT TIME('16:00:00')
        UNION ALL SELECT TIME('16:30:00')
    )


    -- =====================================================
    -- Return today's complete schedule.
    -- =====================================================
    SELECT

        -- Current database date
        CURRENT_DATE AS appointment_date,

        -- Convert the slot time into a readable format
        TIME_FORMAT(
            slots.slot_time,
            '%h:%i %p'
        ) AS appointment_time,

        -- Identify whether the slot is booked or available
        CASE
            WHEN appointments.apt_id IS NULL THEN 'OPEN'
            ELSE 'BOOKED'
        END AS slot_status,

        -- Return the patient's full name for booked slots
        CASE
            WHEN appointments.apt_id IS NULL THEN NULL
            ELSE CONCAT(
                patients.first_name,
                ' ',
                patients.last_name
            )
        END AS patient_name,

        -- Return the appointment status
        appointments.status AS appointment_status

    FROM ClinicSlots AS slots

    -- Match the clinic slots with today's doctor appointments
    LEFT JOIN Appointments AS appointments
        ON appointments.doctor_id = p_doctor_id
        AND appointments.apt_date = CURRENT_DATE
        AND appointments.time_slot = slots.slot_time
        AND appointments.status = 'Scheduled'

    -- Get patient information for booked appointments
    LEFT JOIN Patients AS patients
        ON patients.patient_id = appointments.patient_id

    -- Display the schedule in chronological order
    ORDER BY slots.slot_time ASC;

END //

-- ----------------------- patient ------------------------------------------

-- =========================================================
-- 4. GET AVAILABLE SLOTS BY DOCTOR NAME, DEPARTMENT & DATE
--    : slot must be at least 2 hours from now
-- =========================================================
CREATE PROCEDURE sp_get_available_slots(
    IN p_doctor_name VARCHAR(150),
    IN p_dept_name   VARCHAR(100),
    IN p_apt_date    DATE
)
BEGIN
    DECLARE v_doctor_id  INT DEFAULT NULL;
    DECLARE v_dept_id    INT DEFAULT NULL;
    DECLARE v_clean_name VARCHAR(150);

    -- 1. Date validation: cannot be a past date
    IF p_apt_date < CURDATE() THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Appointment date cannot be in the past.';
    END IF;

    -- Clean prefix 'Dr.' or 'Dr ' if provided
    SET v_clean_name = TRIM(REPLACE(REPLACE(p_doctor_name, 'Dr. ', ''), 'Dr ', ''));

    -- 2. Resolve Department ID if department name is provided
    IF p_dept_name IS NOT NULL AND TRIM(p_dept_name) != '' THEN
        SELECT dept_id INTO v_dept_id
        FROM Departments
        WHERE LOWER(TRIM(dept_name)) = LOWER(TRIM(p_dept_name))
        LIMIT 1;

        IF v_dept_id IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Department not found.';
        END IF;
    END IF;

    -- 3. Resolve Doctor ID by doctor name (and department if specified)
    SELECT s.staff_id, s.dept_id INTO v_doctor_id, v_dept_id
    FROM Staff s
    WHERE (v_dept_id IS NULL OR s.dept_id = v_dept_id)
      AND (
          LOWER(CONCAT(s.first_name, ' ', s.last_name)) = LOWER(v_clean_name)
          OR LOWER(CONCAT(s.first_name, ' ', s.last_name)) = LOWER(TRIM(p_doctor_name))
          OR LOWER(CONCAT('Dr. ', s.first_name, ' ', s.last_name)) = LOWER(TRIM(p_doctor_name))
          OR LOWER(s.last_name) = LOWER(v_clean_name)
      )
    LIMIT 1;

    IF v_doctor_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Doctor not found with the specified name and department.';
    END IF;

    -- 4. Return slots that are 2+ hours from now AND have no overlapping 'Scheduled' appointment
    WITH ClinicSlots AS (
        SELECT TIME('09:00:00') AS slot_time UNION ALL
        SELECT TIME('09:30:00') UNION ALL
        SELECT TIME('10:00:00') UNION ALL
        SELECT TIME('10:30:00') UNION ALL
        SELECT TIME('11:00:00') UNION ALL
        SELECT TIME('11:30:00') UNION ALL
        SELECT TIME('13:00:00') UNION ALL
        SELECT TIME('13:30:00') UNION ALL
        SELECT TIME('14:00:00') UNION ALL
        SELECT TIME('14:30:00') UNION ALL
        SELECT TIME('15:00:00') UNION ALL
        SELECT TIME('15:30:00') UNION ALL
        SELECT TIME('16:00:00') UNION ALL
        SELECT TIME('16:30:00')
    )
    SELECT 
        TIME_FORMAT(s.slot_time, '%h:%i %p') AS available_slot
    FROM ClinicSlots s
    WHERE TIMESTAMP(p_apt_date, s.slot_time) >= DATE_ADD(NOW(), INTERVAL 2 HOUR)
      AND NOT EXISTS (
        SELECT 1 
        FROM Appointments a
        WHERE a.doctor_id = v_doctor_id
          AND a.dept_id = v_dept_id
          AND a.apt_date = p_apt_date
          AND a.status = 'Scheduled'
          -- Condition 1: slot starts before existing appointment ends (+15 min)
          AND s.slot_time < ADDTIME(a.time_slot, '00:15:00')
          -- Condition 2: slot ends (+15 min) after existing appointment starts
          AND ADDTIME(s.slot_time, '00:15:00') > a.time_slot
    )
    ORDER BY s.slot_time ASC;

END //

-- =========================================================
-- 5. BOOK APPOINTMENT BY PATIENT (ALWAYS STATUS 'Scheduled')
--     must be booked at least 2 hours in advance
-- =========================================================
CREATE PROCEDURE sp_book_appointment(
    IN p_patient_id INT,
    IN p_doctor_id  INT,
    IN p_dept_id    INT,
    IN p_apt_date   DATE,
    IN p_time_slot  TIME
)
BEGIN
    DECLARE v_actual_patient_id INT DEFAULT NULL;

    -- 1. Time validation: must be at least 2 hours from now
    IF TIMESTAMP(p_apt_date, p_time_slot) < DATE_ADD(NOW(), INTERVAL 2 HOUR) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Appointment must be booked at least 2 hours in advance.';
    END IF;

    -- 2. Validate patient: checks patient_id OR user_id
    SELECT patient_id INTO v_actual_patient_id
    FROM Patients
    WHERE patient_id = p_patient_id OR user_id = p_patient_id
    LIMIT 1;

    IF v_actual_patient_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Patient record not found.';
    END IF;

    -- 3. Validate doctor and department
    IF NOT EXISTS (
        SELECT 1 
        FROM Staff 
        WHERE staff_id = p_doctor_id 
          AND (p_dept_id IS NULL OR dept_id = p_dept_id)
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Doctor not found in the specified department.';
    END IF;

    -- 4. Overlap check: ensure no 'Scheduled' appointment collides (15-min interval)
    IF EXISTS (
        SELECT 1 
        FROM Appointments a
        WHERE a.doctor_id = p_doctor_id
          AND a.apt_date = p_apt_date
          AND a.status = 'Scheduled'
          -- Condition 1: new slot starts before existing appointment ends (+15 min)
          AND p_time_slot < ADDTIME(a.time_slot, '00:15:00')
          -- Condition 2: new slot ends (+15 min) after existing appointment starts
          AND ADDTIME(p_time_slot, '00:15:00') > a.time_slot
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Selected time slot is already booked. Please choose another time slot.';
    END IF;

    -- 5. Insert into Appointments table (status is ALWAYS 'Scheduled')
    INSERT INTO Appointments (
        patient_id,
        doctor_id,
        dept_id,
        apt_date,
        time_slot,
        status
    ) VALUES (
        v_actual_patient_id,
        p_doctor_id,
        p_dept_id,
        p_apt_date,
        p_time_slot,
        'Scheduled'
    );

    -- 6. Return the newly created appointment details
    SELECT 
        a.apt_id,
        a.patient_id,
        a.doctor_id,
        a.dept_id,
        a.apt_date,
        TIME_FORMAT(a.time_slot, '%H:%i') AS time_slot,
        a.status,
        a.created_at
    FROM Appointments a
    WHERE a.apt_id = LAST_INSERT_ID();

END //

-- nimhara --

CREATE PROCEDURE sp_create_nurse_indexes()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.statistics 
        WHERE table_schema = DATABASE() AND table_name = 'Beds' AND index_name = 'idx_beds_ward_status'
    ) THEN
        CREATE INDEX idx_beds_ward_status ON Beds (ward_id, status);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.statistics 
        WHERE table_schema = DATABASE() AND table_name = 'Admissions' AND index_name = 'idx_admissions_ward_status'
    ) THEN
        CREATE INDEX idx_admissions_ward_status ON Admissions (ward_id, status);
    END IF;
END //

CALL sp_create_nurse_indexes() //
DROP PROCEDURE IF EXISTS sp_create_nurse_indexes //

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

CREATE PROCEDURE sp_get_pending_lab_count()
BEGIN
    SELECT COUNT(*) AS pending_count
    FROM Lab_Orders
    WHERE status = 'Pending';
END //

CREATE PROCEDURE sp_extend_vitals_schema()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = DATABASE() AND table_name = 'Vitals_Log' AND column_name = 'spo2'
    ) THEN
        ALTER TABLE Vitals_Log ADD COLUMN spo2 INT NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = DATABASE() AND table_name = 'Vitals_Log' AND column_name = 'resp_rate'
    ) THEN
        ALTER TABLE Vitals_Log ADD COLUMN resp_rate INT NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = DATABASE() AND table_name = 'Vitals_Log' AND column_name = 'blood_sugar'
    ) THEN
        ALTER TABLE Vitals_Log ADD COLUMN blood_sugar DECIMAL(5,2) NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = DATABASE() AND table_name = 'Vitals_Log' AND column_name = 'weight'
    ) THEN
        ALTER TABLE Vitals_Log ADD COLUMN weight DECIMAL(5,2) NULL;
    END IF;
END //

CALL sp_extend_vitals_schema() //
DROP PROCEDURE IF EXISTS sp_extend_vitals_schema //

-- maleesha --

CREATE PROCEDURE sp_get_patient_medical_history(
    IN p_patient_id INT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM `Patients`
        WHERE `patient_id` = p_patient_id OR `user_id` = p_patient_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Patient not found with the specified ID.';
    END IF;

    SELECT 
        mr.record_id,
        mr.patient_id,
        CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
        mr.doctor_id,
        CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS doctor_name,
        doc.specialty AS doctor_specialty,
        d.dept_name AS department_name,
        mr.apt_id,
        a.apt_date,
        a.time_slot,
        mr.diagnosis,
        mr.clinical_notes,
        mr.created_at,
        mr.updated_at
    FROM `Medical_Records` mr
    JOIN `Patients` p ON mr.patient_id = p.patient_id
    LEFT JOIN `Staff` doc ON mr.doctor_id = doc.staff_id
    LEFT JOIN `Departments` d ON doc.dept_id = d.dept_id
    LEFT JOIN `Appointments` a ON mr.apt_id = a.apt_id
    WHERE (mr.patient_id = p_patient_id OR p.user_id = p_patient_id)
    ORDER BY mr.created_at DESC, mr.record_id DESC;
END //

CREATE PROCEDURE sp_get_patient_rx_summary(
    IN p_patient_id INT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM `Patients`
        WHERE `patient_id` = p_patient_id OR `user_id` = p_patient_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Patient not found with the specified ID.';
    END IF;

    SELECT 
        COUNT(rx.rx_id) AS total_prescriptions,
        SUM(CASE WHEN LOWER(rx.status) = 'active' THEN 1 ELSE 0 END) AS active_prescriptions,
        SUM(CASE WHEN LOWER(rx.status) != 'active' THEN 1 ELSE 0 END) AS inactive_prescriptions
    FROM `Prescriptions` rx
    JOIN `Medical_Records` mr ON rx.record_id = mr.record_id
    JOIN `Patients` p ON mr.patient_id = p.patient_id
    WHERE (mr.patient_id = p_patient_id OR p.user_id = p_patient_id);

    SELECT 
        rx.rx_id,
        rx.record_id,
        rx.med_name,
        rx.dosage,
        rx.duration,
        rx.status,
        CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS prescribing_doctor,
        mr.diagnosis,
        rx.created_at,
        rx.updated_at
    FROM `Prescriptions` rx
    JOIN `Medical_Records` mr ON rx.record_id = mr.record_id
    JOIN `Patients` p ON mr.patient_id = p.patient_id
    LEFT JOIN `Staff` doc ON mr.doctor_id = doc.staff_id
    WHERE (mr.patient_id = p_patient_id OR p.user_id = p_patient_id)
    ORDER BY rx.created_at DESC, rx.rx_id DESC;
END //

CREATE PROCEDURE sp_deactivate_prescription(
    IN p_rx_id INT,
    IN p_actor_user_id INT
)
proc_label: BEGIN
    DECLARE v_current_status VARCHAR(50);
    DECLARE v_record_id      INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Transaction failed: unable to deactivate prescription.';
    END;

    SELECT status, record_id INTO v_current_status, v_record_id
    FROM `Prescriptions`
    WHERE `rx_id` = p_rx_id
    LIMIT 1;

    IF v_current_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Prescription not found with the specified ID.';
    END IF;

    IF v_current_status = 'Inactive' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Prescription is already inactive.';
    END IF;

    START TRANSACTION;

        UPDATE `Prescriptions`
        SET `status` = 'Inactive',
            `updated_at` = NOW()
        WHERE `rx_id` = p_rx_id;

        INSERT INTO `Audit_Logs` (
            actor_id,
            action_type,
            resource_table,
            details,
            timestamp
        )
        VALUES (
            p_actor_user_id,
            'PRESCRIPTION_DEACTIVATED',
            'Prescriptions',
            JSON_OBJECT(
                'rx_id', p_rx_id,
                'record_id', v_record_id,
                'previous_status', v_current_status,
                'new_status', 'Inactive'
            ),
            NOW()
        );

    COMMIT;

    SELECT p_rx_id AS rx_id, 'Inactive' AS status, 'Prescription deactivated successfully' AS message;
END //

DELIMITER ;