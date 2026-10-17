
-- =========================================================
-- DOCTOR APPOINTMENT MANAGEMENT
-- =========================================================

--check if doctor exists
DELIMITER //

CREATE PROCEDURE CheckDoctorExists(
    IN p_doctor_id INT
)
BEGIN
    SELECT COUNT(*) AS doctor_count
    FROM staff
    WHERE staff_id = p_doctor_id;
END //

DELIMITER ;













DELIMITER //


-- =========================================================
-- 1. GET TODAY'S APPOINTMENTS FOR A DOCTOR
-- =========================================================

DROP PROCEDURE IF EXISTS GetAppointmentsByDoctor //

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

DROP PROCEDURE IF EXISTS GetAppointmentHistoryByDoctor //

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


DELIMITER //

CREATE PROCEDURE IF NOT EXISTS sp_get_upcoming_appointments_by_doctor(
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

DELIMITER ;



-----------------------patient------------------------------------------







-- =========================================================
-- 4. GET AVAILABLE SLOTS BY DOCTOR NAME, DEPARTMENT & DATE
--    : slot must be at least 2 hours from now
-- =========================================================
DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_available_slots //

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

DELIMITER ;


-- =========================================================
-- 5. BOOK APPOINTMENT BY PATIENT (ALWAYS STATUS 'Scheduled')
--     must be booked at least 2 hours in advance
-- =========================================================
DELIMITER //

DROP PROCEDURE IF EXISTS sp_book_appointment //

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

DELIMITER ;