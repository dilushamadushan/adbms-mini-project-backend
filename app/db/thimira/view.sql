-- ==============================================================================
-- Pharmacy Management Views (Thimira)
-- Module: Inventory & Dispensing Analytics Views
-- ==============================================================================

USE hms;

-- ------------------------------------------------------------------------------
-- 1. View: Comprehensive Medicine Inventory View
-- Combines stock quantity, pricing, status, and days to expiry
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_medicine_inventory AS
SELECT 
    m.medicine_id,
    m.med_name,
    m.generic_name,
    m.unit_price,
    m.stock_qty,
    m.reorder_level,
    m.expiry_date,
    DATEDIFF(m.expiry_date, CURDATE()) AS days_to_expiry,
    fn_calculate_medicine_status(m.stock_qty, m.reorder_level, m.expiry_date) AS stock_status,
    (m.unit_price * m.stock_qty) AS inventory_value,
    m.is_active,
    m.created_at,
    m.updated_at
FROM Medicines m;


-- ------------------------------------------------------------------------------
-- 2. View: Near-Expiry & Expired Medicines Alert View
-- Filters out medicines needing immediate replacement or disposal
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_near_expiry_alerts AS
SELECT 
    m.medicine_id,
    m.med_name,
    m.generic_name,
    m.stock_qty,
    m.unit_price,
    m.expiry_date,
    DATEDIFF(m.expiry_date, CURDATE()) AS days_remaining,
    CASE 
        WHEN m.expiry_date <= CURDATE() THEN 'EXPIRED'
        ELSE 'EXPIRING_SOON'
    END AS urgency_level
FROM Medicines m
WHERE m.expiry_date <= DATE_ADD(CURDATE(), INTERVAL 30 DAY)
  AND m.is_active = TRUE
ORDER BY m.expiry_date ASC;


-- ------------------------------------------------------------------------------
-- 3. View: Daily Dispensing & Revenue Summary View
-- Aggregates dispensing activities by day
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_daily_dispensing_summary AS
SELECT 
    DATE(d.dispensed_at) AS dispense_date,
    COUNT(d.dispense_id) AS total_transactions,
    SUM(d.quantity) AS total_units_dispensed,
    SUM(d.quantity * d.unit_price_at_sale) AS total_revenue,
    COUNT(DISTINCT d.pharmacist_id) AS pharmacists_on_duty
FROM Dispensations d
GROUP BY DATE(d.dispensed_at)
ORDER BY dispense_date DESC;
