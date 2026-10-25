-- TG/1407 --

DROP PROCEDURE IF EXISTS sp_rotate_refresh_token;
DROP PROCEDURE IF EXISTS sp_revoke_all_user_sessions;
DROP PROCEDURE IF EXISTS sp_cleanup_expired_tokens;
DROP PROCEDURE IF EXISTS sp_get_department_hierarchy;
DROP PROCEDURE IF EXISTS sp_generate_workload_report;
DROP PROCEDURE IF EXISTS sp_get_hospital_kpi_overview;

DELIMITER //

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

DELIMITER ;