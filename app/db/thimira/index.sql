-- ==============================================================================
-- Pharmacy Management Performance Indexes (Thimira)
-- Module: Inventory Optimization Indexes
-- ==============================================================================

USE hms;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_create_index_safe //

CREATE PROCEDURE sp_create_index_safe(
    IN p_table_name VARCHAR(64),
    IN p_index_name VARCHAR(64),
    IN p_index_cols VARCHAR(255)
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.statistics 
        WHERE table_schema = DATABASE() 
          AND table_name = p_table_name 
          AND index_name = p_index_name
    ) THEN
        SET @s = CONCAT('CREATE INDEX ', p_index_name, ' ON ', p_table_name, ' (', p_index_cols, ')');
        PREPARE stmt FROM @s;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END //

DELIMITER ;

CALL sp_create_index_safe('Medicines', 'idx_medicines_stock_reorder', 'is_active, stock_qty, reorder_level');
CALL sp_create_index_safe('Medicines', 'idx_medicines_active_expiry', 'is_active, expiry_date');
CALL sp_create_index_safe('Dispensations', 'idx_dispensations_date_med', 'dispensed_at, medicine_id');
CALL sp_create_index_safe('Stock_Receipts', 'idx_receipts_med_date', 'medicine_id, received_at');

DROP PROCEDURE IF EXISTS sp_create_index_safe;
