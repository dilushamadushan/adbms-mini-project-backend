USE hms;

DELIMITER //

DROP TRIGGER IF EXISTS trg_audit_refresh_token_issued; //

CREATE TRIGGER trg_audit_refresh_token_issued
AFTER INSERT ON Refresh_Tokens
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Logs (actor_id, action_type, resource_table, details)
    VALUES (
        NEW.user_id,
        'LOGIN_SESSION_CREATED',
        'Refresh_Tokens',
        JSON_OBJECT(
            'token_id', NEW.token_id,
            'user_id', NEW.user_id,
            'expires_at', NEW.expires_at,
            'created_at', NOW()
        )
    );
END //

DELIMITER ;

DELIMITER //

DROP TRIGGER IF EXISTS trg_audit_refresh_token_revoked; //

CREATE TRIGGER trg_audit_refresh_token_revoked
AFTER UPDATE ON Refresh_Tokens
FOR EACH ROW
BEGIN
    IF OLD.revoked = FALSE AND NEW.revoked = TRUE THEN
        INSERT INTO Audit_Logs (actor_id, action_type, resource_table, details)
        VALUES (
            NEW.user_id,
            'TOKEN_REVOKED',
            'Refresh_Tokens',
            JSON_OBJECT(
                'token_id', NEW.token_id,
                'user_id', NEW.user_id,
                'action', 'LOGOUT_OR_ROTATION',
                'revoked_at', NOW()
            )
        );
    END IF;
END //

DELIMITER ;

DELIMITER //

DROP TRIGGER IF EXISTS trg_audit_refresh_token_deleted; //

CREATE TRIGGER trg_audit_refresh_token_deleted
AFTER DELETE ON Refresh_Tokens
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Logs (actor_id, action_type, resource_table, details)
    VALUES (
        OLD.user_id,
        'TOKEN_DELETED_ON_LOGOUT',
        'Refresh_Tokens',
        JSON_OBJECT(
            'token_id', OLD.token_id,
            'user_id', OLD.user_id,
            'action', 'REMOVED_FROM_DB_ON_LOGOUT',
            'timestamp', NOW()
        )
    );
END //

DELIMITER ;

DELIMITER //

DROP TRIGGER IF EXISTS trg_prevent_department_self_parent; //

CREATE TRIGGER trg_prevent_department_self_parent
BEFORE UPDATE ON Departments
FOR EACH ROW
BEGIN
    IF NEW.parent_dept_id IS NOT NULL AND NEW.parent_dept_id = NEW.dept_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Integrity violation: A department cannot be set as its own parent';
    END IF;
END //

DELIMITER ;

DELIMITER //

DROP TRIGGER IF EXISTS trg_audit_department_created; //

CREATE TRIGGER trg_audit_department_created
AFTER INSERT ON Departments
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Logs (actor_id, action_type, resource_table, details, timestamp)
    VALUES (
        NULL,
        'DEPARTMENT_CREATED',
        'Departments',
        JSON_OBJECT(
            'dept_id', NEW.dept_id,
            'dept_name', NEW.dept_name,
            'parent_dept_id', NEW.parent_dept_id
        ),
        NOW()
    );
END //

DELIMITER ;

DELIMITER //

DROP TRIGGER IF EXISTS trg_audit_department_deleted; //

CREATE TRIGGER trg_audit_department_deleted
AFTER DELETE ON Departments
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Logs (actor_id, action_type, resource_table, details, timestamp)
    VALUES (
        NULL,
        'DEPARTMENT_DELETED',
        'Departments',
        JSON_OBJECT(
            'dept_id', OLD.dept_id,
            'dept_name', OLD.dept_name,
            'parent_dept_id', OLD.parent_dept_id
        ),
        NOW()
    );
END //

DELIMITER ;

DELIMITER //

DROP TRIGGER IF EXISTS trg_notify_staff_created; //

CREATE TRIGGER trg_notify_staff_created
AFTER INSERT ON Staff
FOR EACH ROW
BEGIN
    DECLARE v_dept_name VARCHAR(100);
    SELECT dept_name INTO v_dept_name FROM Departments WHERE dept_id = NEW.dept_id;

    INSERT INTO Notifications (title, message, type, target_role, details, created_at)
    VALUES (
        'New Staff Member Added',
        CONCAT(
            'Staff member ', NEW.first_name, ' ', NEW.last_name,
            IF(NEW.specialty IS NOT NULL AND NEW.specialty != '', CONCAT(' (', NEW.specialty, ')'), ''),
            ' was assigned to department ', COALESCE(v_dept_name, CONCAT('ID #', NEW.dept_id)), '.'
        ),
        'STAFF_ADDED',
        'admin',
        JSON_OBJECT(
            'staff_id', NEW.staff_id,
            'user_id', NEW.user_id,
            'dept_id', NEW.dept_id,
            'dept_name', v_dept_name,
            'name', CONCAT(NEW.first_name, ' ', NEW.last_name),
            'specialty', NEW.specialty
        ),
        NOW()
    );
END //

DELIMITER ;

DELIMITER //

DROP TRIGGER IF EXISTS trg_notify_department_created; //

CREATE TRIGGER trg_notify_department_created
AFTER INSERT ON Departments
FOR EACH ROW
BEGIN
    INSERT INTO Notifications (title, message, type, target_role, details, created_at)
    VALUES (
        'New Department Created',
        CONCAT('New department "', NEW.dept_name, '" (ID #', NEW.dept_id, ') has been established in the hospital.'),
        'DEPARTMENT_ADDED',
        'admin',
        JSON_OBJECT(
            'dept_id', NEW.dept_id,
            'dept_name', NEW.dept_name,
            'parent_dept_id', NEW.parent_dept_id
        ),
        NOW()
    );
END //

DELIMITER ;

DELIMITER //

DROP TRIGGER IF EXISTS trg_notify_department_deleted; //

CREATE TRIGGER trg_notify_department_deleted
AFTER DELETE ON Departments
FOR EACH ROW
BEGIN
    INSERT INTO Notifications (title, message, type, target_role, details, created_at)
    VALUES (
        'Department Removed',
        CONCAT('Department "', OLD.dept_name, '" (ID #', OLD.dept_id, ') has been removed.'),
        'DEPARTMENT_DELETED',
        'admin',
        JSON_OBJECT(
            'dept_id', OLD.dept_id,
            'dept_name', OLD.dept_name
        ),
        NOW()
    );
END //

DELIMITER ;



