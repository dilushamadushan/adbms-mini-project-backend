-- TG/1407 --

DROP FUNCTION IF EXISTS fn_is_token_active;
DROP FUNCTION IF EXISTS fn_calculate_provider_avg_time; 
DROP FUNCTION IF EXISTS fn_get_workload_level; 
DROP FUNCTION IF EXISTS fn_get_audit_risk; 
DROP FUNCTION IF EXISTS fn_bed_occupancy_pct; 

DELIMITER //

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



CREATE FUNCTION fn_calculate_provider_avg_time(p_doctor_id INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_dept_name VARCHAR(100);
    DECLARE v_specialty VARCHAR(100);

    SELECT d.dept_name, s.specialty INTO v_dept_name, v_specialty
    FROM Staff s
    LEFT JOIN Departments d ON s.dept_id = d.dept_id
    WHERE s.staff_id = p_doctor_id;

    IF v_dept_name = 'Emergency Medicine' OR v_specialty LIKE '%Emergency%' THEN
        RETURN 18;
    ELSEIF v_dept_name = 'Cardiology' OR v_specialty LIKE '%Cardio%' THEN
        RETURN 22;
    ELSEIF v_dept_name = 'General Medicine' OR v_specialty LIKE '%Physician%' OR v_specialty LIKE '%General%' THEN
        RETURN 15;
    ELSEIF v_dept_name = 'Orthopedics' THEN
        RETURN 20;
    ELSE
        RETURN 15 + (p_doctor_id * 3) % 12;
    END IF;
END //

CREATE FUNCTION fn_get_workload_level(p_count INT, p_pct DECIMAL(5,2))
RETURNS VARCHAR(20)
DETERMINISTIC
CONTAINS SQL
BEGIN
    IF p_pct >= 30.0 OR p_count >= 100 THEN
        RETURN 'Critical';
    ELSEIF p_pct >= 20.0 OR p_count >= 50 THEN
        RETURN 'High';
    ELSEIF p_pct >= 10.0 OR p_count >= 20 THEN
        RETURN 'Moderate';
    ELSE
        RETURN 'Low';
    END IF;
END //

CREATE FUNCTION fn_get_audit_risk(p_action VARCHAR(100), p_details JSON)
RETURNS VARCHAR(10)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_risk_override VARCHAR(10);
    DECLARE v_action_upper VARCHAR(100);

    IF p_details IS NOT NULL THEN
        SET v_risk_override = UPPER(TRIM(BOTH '"' FROM JSON_UNQUOTE(JSON_EXTRACT(p_details, '$.risk'))));
        IF v_risk_override IN ('HIGH', 'MEDIUM', 'LOW') THEN
            RETURN v_risk_override;
        END IF;
    END IF;

    SET v_action_upper = UPPER(COALESCE(p_action, ''));

    IF v_action_upper LIKE '%DELETE%' 
       OR v_action_upper LIKE '%DROP%' 
       OR v_action_upper LIKE '%REVOKE%'
       OR v_action_upper LIKE '%PURGE%'
       OR v_action_upper LIKE '%UNAUTHORIZED%'
       OR v_action_upper LIKE '%BREACH%'
       OR v_action_upper LIKE '%FAIL%' THEN
        RETURN 'HIGH';

    ELSEIF v_action_upper LIKE '%UPDATE%' 
       OR v_action_upper LIKE '%MODIFY%' 
       OR v_action_upper LIKE '%PASSWORD%'
       OR v_action_upper LIKE '%ROLE%'
       OR v_action_upper LIKE '%STATUS%'
       OR v_action_upper LIKE '%USER%'
       OR v_action_upper LIKE '%DIAGNOSIS%'
       OR v_action_upper LIKE '%PRESCRIPTION%'
       OR v_action_upper LIKE '%CREATE%' THEN
        RETURN 'MEDIUM';

    ELSE
        RETURN 'LOW';
    END IF;
END //

CREATE FUNCTION fn_bed_occupancy_pct(p_ward_id INT)
RETURNS DECIMAL(5,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_occupied INT DEFAULT 0;

    IF p_ward_id IS NOT NULL THEN
        SELECT COUNT(*) INTO v_total FROM Beds WHERE ward_id = p_ward_id;
        SELECT COUNT(*) INTO v_occupied FROM Beds WHERE ward_id = p_ward_id AND status = 'Occupied';
    ELSE
        SELECT COUNT(*) INTO v_total FROM Beds;
        SELECT COUNT(*) INTO v_occupied FROM Beds WHERE status = 'Occupied';
    END IF;

    IF v_total = 0 THEN
        RETURN 0.00;
    END IF;

    RETURN ROUND((v_occupied * 100.0) / v_total, 2);
END //

DELIMITER ;

