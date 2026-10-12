USE hms;

DELIMITER //

DROP FUNCTION IF EXISTS fn_is_token_active; //

CREATE FUNCTION fn_is_token_active(p_token_hash VARCHAR(255))
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_count INT;
    SELECT COUNT(*) INTO v_count
    FROM Refresh_Tokens
    WHERE token_hash = p_token_hash
      AND revoked = FALSE
      AND expires_at > NOW();
    RETURN (v_count > 0);
END //

DELIMITER ;

DELIMITER //

DROP FUNCTION IF EXISTS fn_get_active_session_count; //

CREATE FUNCTION fn_get_active_session_count(p_user_id INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_active_count INT;
    SELECT COUNT(*) INTO v_active_count
    FROM Refresh_Tokens
    WHERE user_id = p_user_id
      AND revoked = FALSE
      AND expires_at > NOW();
    RETURN v_active_count;
END //

DELIMITER ;

DELIMITER //

DROP FUNCTION IF EXISTS fn_get_department_depth; //

CREATE FUNCTION fn_get_department_depth(p_dept_id INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_depth INT DEFAULT 0;
    DECLARE v_current_parent INT;

    SELECT parent_dept_id INTO v_current_parent 
    FROM Departments 
    WHERE dept_id = p_dept_id;

    WHILE v_current_parent IS NOT NULL AND v_depth < 20 DO
        SET v_depth = v_depth + 1;
        SELECT parent_dept_id INTO v_current_parent 
        FROM Departments 
        WHERE dept_id = v_current_parent;
    END WHILE;

    RETURN v_depth;
END //

DELIMITER ;

DELIMITER //

DROP FUNCTION IF EXISTS fn_get_department_staff_count; //

CREATE FUNCTION fn_get_department_staff_count(p_dept_id INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_count INT DEFAULT 0;
    SELECT COUNT(*) INTO v_count FROM Staff WHERE dept_id = p_dept_id;
    RETURN v_count;
END //

DELIMITER ;


