-- TG/1407 --

DELIMITER //

DROP EVENT IF EXISTS ev_purge_expired_tokens; //

CREATE EVENT ev_purge_expired_tokens
ON SCHEDULE EVERY 1 DAY
STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 3 HOUR)
DO
BEGIN
    DELETE FROM Refresh_Tokens
    WHERE (revoked = TRUE OR expires_at < NOW())
      AND created_at < (NOW() - INTERVAL 7 DAY);
END //

DELIMITER ;
