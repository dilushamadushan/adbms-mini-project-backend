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

DELIMITER ;