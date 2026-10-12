USE hms;

DELIMITER //

DROP PROCEDURE IF EXISTS GetAllPatients; //

CREATE PROCEDURE GetAllPatients()
BEGIN
    SELECT 
        p.patient_id,
        p.first_name,
        p.last_name,
        p.dob,
        p.blood_group,
        p.emergency_contact,
        p.allergies,
        u.user_id,
        u.username,
        u.email,
        u.role,
        u.is_active,
        p.created_at,
        p.updated_at
    FROM Patients p
    INNER JOIN Users u ON p.user_id = u.user_id;
END //

DELIMITER ;

DELIMITER //

DROP PROCEDURE IF EXISTS GetAllStaff; //

CREATE PROCEDURE GetAllStaff()
BEGIN
    SELECT 
        s.staff_id,
        s.first_name,
        s.last_name,
        s.dept_id,
        s.specialty,
        u.user_id,
        u.username,
        u.email,
        u.role,
        u.is_active
    FROM Staff s
    INNER JOIN Users u ON s.user_id = u.user_id;
END //

DELIMITER ;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_rotate_refresh_token; //

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

DELIMITER ;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_revoke_all_user_sessions; //

CREATE PROCEDURE sp_revoke_all_user_sessions(
    IN p_user_id INT,
    OUT p_revoked_count INT
)
BEGIN
    DELETE FROM Refresh_Tokens
    WHERE user_id = p_user_id;

    SET p_revoked_count = ROW_COUNT();
END //

DELIMITER ;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_cleanup_expired_tokens; //

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

DELIMITER ;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_department_hierarchy; //

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

DELIMITER ;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_delete_department; //

CREATE PROCEDURE sp_delete_department(
    IN p_dept_id INT
)
BEGIN
    DECLARE v_sub_count INT DEFAULT 0;
    DECLARE v_staff_count INT DEFAULT 0;
    DECLARE v_exists INT DEFAULT 0;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_exists FROM Departments WHERE dept_id = p_dept_id;
    IF v_exists = 0 THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Department does not exist';
    END IF;

    SELECT COUNT(*) INTO v_sub_count FROM Departments WHERE parent_dept_id = p_dept_id;
    IF v_sub_count > 0 THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot delete: Sub-departments depend on this department';
    END IF;

    SELECT COUNT(*) INTO v_staff_count FROM Staff WHERE dept_id = p_dept_id;
    IF v_staff_count > 0 THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot delete: Staff members are assigned to this department';
    END IF;

    DELETE FROM Departments WHERE dept_id = p_dept_id;

    COMMIT;
END //

DELIMITER ;