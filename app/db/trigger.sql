-- TG/1407 --

DROP TRIGGER IF EXISTS trg_audit_refresh_token_issued;
DROP TRIGGER IF EXISTS trg_audit_refresh_token_revoked;
DROP TRIGGER IF EXISTS trg_audit_refresh_token_deleted; 
DROP TRIGGER IF EXISTS trg_prevent_department_self_parent;
DROP TRIGGER IF EXISTS trg_audit_department_created;
DROP TRIGGER IF EXISTS trg_audit_department_deleted; 
DROP TRIGGER IF EXISTS trg_notify_staff_created;
DROP TRIGGER IF EXISTS trg_notify_department_created;
DROP TRIGGER IF EXISTS trg_prevent_duplicate_admission_assignment;
DROP TRIGGER IF EXISTS trg_notify_admission_created; 
DROP TRIGGER IF EXISTS trg_prevent_duplicate_open_admission; 
DROP TRIGGER IF EXISTS trg_notify_admission_confirmed; 
DROP TRIGGER IF EXISTS trg_notify_admission_inserted;
DROP TRIGGER IF EXISTS trg_notify_department_deleted;

DELIMITER //

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

CREATE TRIGGER trg_prevent_department_self_parent
BEFORE UPDATE ON Departments
FOR EACH ROW
BEGIN
    IF NEW.parent_dept_id IS NOT NULL AND NEW.parent_dept_id = NEW.dept_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Integrity violation: A department cannot be set as its own parent';
    END IF;
END //

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

CREATE TRIGGER trg_notify_department_created
AFTER INSERT ON Departments
FOR EACH ROW
BEGIN
    INSERT INTO Notifications (title, message, type, target_role, details, created_at)
    VALUES (
        'New Department Created',
        CONCAT('New department "', NEW.dept_name, '" (ID #', NEW.dept_id, ') has been established in the hospital.'),
        'DEPARTMENT_ADDED',
        'all',
        JSON_OBJECT(
            'dept_id', NEW.dept_id,
            'dept_name', NEW.dept_name,
            'parent_dept_id', NEW.parent_dept_id
        ),
        NOW()
    );
END //

CREATE TRIGGER trg_notify_department_deleted
AFTER DELETE ON Departments
FOR EACH ROW
BEGIN
    INSERT INTO Notifications (title, message, type, target_role, details, created_at)
    VALUES (
        'Department Removed',
        CONCAT('Department "', OLD.dept_name, '" (ID #', OLD.dept_id, ') has been removed.'),
        'DEPARTMENT_DELETED',
        'all',
        JSON_OBJECT(
            'dept_id', OLD.dept_id,
            'dept_name', OLD.dept_name
        ),
        NOW()
    );
END //

-- TG/13 --

CREATE TRIGGER trg_prevent_duplicate_open_admission
BEFORE INSERT ON Admissions
FOR EACH ROW
BEGIN
    DECLARE v_locked_patient_id INT;
    DECLARE v_open_admission_id INT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_open_admission_id = NULL;

    SELECT patient_id
    INTO v_locked_patient_id
    FROM Patients
    WHERE patient_id = NEW.patient_id
    FOR UPDATE;

    SELECT a.admission_id
    INTO v_open_admission_id
    FROM Admissions a
    LEFT JOIN Discharges d ON d.admission_id = a.admission_id
    WHERE a.patient_id = NEW.patient_id
      AND (d.admission_id IS NULL OR d.status <> 'Discharged')
    LIMIT 1;

    IF v_open_admission_id IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Patient already has an open admission. Complete discharge before admitting again.';
    END IF;
END //

CREATE TRIGGER trg_prevent_duplicate_admission_assignment
BEFORE UPDATE ON Admissions
FOR EACH ROW
BEGIN
    DECLARE v_open_admission_id INT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_open_admission_id = NULL;

    IF NEW.status = 'Admitted' AND OLD.status <> 'Admitted' THEN
        SELECT a.admission_id
        INTO v_open_admission_id
        FROM Admissions a
        LEFT JOIN Discharges d ON d.admission_id = a.admission_id
        WHERE a.patient_id = NEW.patient_id
          AND a.admission_id <> NEW.admission_id
          AND (d.admission_id IS NULL OR d.status <> 'Discharged')
        LIMIT 1;

        IF v_open_admission_id IS NOT NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Patient already has an open admission. Complete discharge before admitting again.';
        END IF;
    END IF;
END //

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
