
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


-- =========================================================
-- 3b. GET APPOINTMENTS GROUPED (TODAY, UPCOMING, PAST) BY DOCTOR USER ID
-- =========================================================

DELIMITER //


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

DELIMITER ;



-- get full details of one patient

	DELIMITER //

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

	DELIMITER ;

	

    -- get appointment overview (date, time, reason)

DELIMITER //

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

DELIMITER ;



DELIMITER //

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

DELIMITER ;




-- =====================================================
-- 4. PROCEDURE - ONE-STEP DISCHARGE
--    Fills authorization AND final discharge details instantly
-- =====================================================
DROP PROCEDURE IF EXISTS `request_discharge`;

DELIMITER $$
CREATE PROCEDURE `request_discharge`(
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
END$$
DELIMITER ;









-- It checks the data, then saves the medical record and
-- all the medicines together. If anything is wrong, it
-- saves nothing and shows an error message.
-- =====================================================
DROP PROCEDURE IF EXISTS `sp_create_prescription`;
DELIMITER $$
CREATE PROCEDURE `sp_create_prescription`(
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
END$$
DELIMITER ;













USE `hms`;

-- WHY:  Runs when the doctor clicks "Save for admission" for an admitted patient.
-- WHAT: Checks the data first. If all is fine, it saves 4 things together:
--         1. medical_records                     (diagnosis + notes)
--         2. prescriptions                       (one row per medicine)
--         3. medication_administration_records   (one row per medicine, status Not Given)
--         4. doctor_orders                       (nurse instructions, status Pending)
--       If anything is wrong, it saves nothing and shows an error.

DROP PROCEDURE IF EXISTS `sp_create_admitted_prescription`;

DELIMITER $$

CREATE PROCEDURE `sp_create_admitted_prescription`(
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
END$$

DELIMITER ;






-- Creates a new pending lab order with an empty result.

DROP PROCEDURE IF EXISTS sp_create_lab_order;

DELIMITER $$

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
END$$

DELIMITER ;





-----------------------patient------------------------------------------








-- =========================================================
-- 4. GET AVAILABLE SLOTS BY DOCTOR NAME, DEPARTMENT & DATE
--    : slot must be at least 2 hours from now
-- =========================================================
DELIMITER //


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