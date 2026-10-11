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
