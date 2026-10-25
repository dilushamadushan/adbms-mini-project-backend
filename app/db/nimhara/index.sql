USE hms;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_create_nurse_indexes //

CREATE PROCEDURE sp_create_nurse_indexes()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.statistics 
        WHERE table_schema = DATABASE() AND table_name = 'Beds' AND index_name = 'idx_beds_ward_status'
    ) THEN
        CREATE INDEX idx_beds_ward_status ON Beds (ward_id, status);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.statistics 
        WHERE table_schema = DATABASE() AND table_name = 'Admissions' AND index_name = 'idx_admissions_ward_status'
    ) THEN
        CREATE INDEX idx_admissions_ward_status ON Admissions (ward_id, status);
    END IF;
END //

DELIMITER ;

CALL sp_create_nurse_indexes();
DROP PROCEDURE IF EXISTS sp_create_nurse_indexes;
