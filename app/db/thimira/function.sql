-- ==============================================================================
-- Pharmacy Management Functions (Thimira)
-- Module: Inventory Status & Valuation Functions
-- ==============================================================================

USE hms;

-- ------------------------------------------------------------------------------
-- 1. Function: Calculate Medicine Status
-- Evaluates stock quantity and expiry date to produce a health status string
-- ------------------------------------------------------------------------------
DELIMITER //

DROP FUNCTION IF EXISTS fn_calculate_medicine_status //

CREATE FUNCTION fn_calculate_medicine_status(
    p_stock INT,
    p_reorder INT,
    p_expiry DATE
)
RETURNS VARCHAR(30)
DETERMINISTIC
NO SQL
BEGIN
    IF p_stock <= 0 THEN
        RETURN 'OUT_OF_STOCK';
    ELSEIF p_expiry <= CURDATE() THEN
        RETURN 'EXPIRED';
    ELSEIF p_expiry <= DATE_ADD(CURDATE(), INTERVAL 30 DAY) THEN
        RETURN 'EXPIRING_SOON';
    ELSEIF p_stock <= p_reorder THEN
        RETURN 'LOW_STOCK';
    ELSE
        RETURN 'IN_STOCK';
    END IF;
END //

DELIMITER ;


-- ------------------------------------------------------------------------------
-- 2. Function: Get Total Pharmacy Inventory Valuation
-- Calculates current financial valuation of all active medicines in stock
-- ------------------------------------------------------------------------------
DELIMITER //

DROP FUNCTION IF EXISTS fn_get_total_inventory_value //

CREATE FUNCTION fn_get_total_inventory_value()
RETURNS DECIMAL(12,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE total_val DECIMAL(12,2) DEFAULT 0.00;

    SELECT COALESCE(SUM(unit_price * stock_qty), 0.00)
    INTO total_val
    FROM Medicines
    WHERE is_active = TRUE;

    RETURN total_val;
END //

DELIMITER ;
