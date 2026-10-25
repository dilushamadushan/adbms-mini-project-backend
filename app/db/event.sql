DROP EVENT IF EXISTS ev_purge_expired_tokens;
DROP EVENT IF EXISTS ev_check_overdue_orders;
DROP EVENT IF EXISTS ev_check_expired_medicines;
DROP EVENT IF EXISTS ev_daily_low_stock_alert;
DROP EVENT IF EXISTS ev_weekly_stale_orders_cleanup;

DELIMITER //

-- TG/1407 --

CREATE EVENT ev_purge_expired_tokens
ON SCHEDULE EVERY 1 DAY
STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 3 HOUR)
DO
BEGIN
    DELETE FROM Refresh_Tokens
    WHERE (revoked = TRUE OR expires_at < NOW())
      AND created_at < (NOW() - INTERVAL 7 DAY);
END //

-- thimira --

CREATE EVENT ev_check_overdue_orders
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO Notifications (title, message, type, target_role, details, created_at)
    SELECT 
        'Overdue Restock Delivery',
        CONCAT('Purchase Order #', po.order_number, ' from "', po.supplier_name, '" was expected on ', po.expected_delivery_date, ' but is overdue. Please follow up with supplier.'),
        'RESTOCK_OVERDUE',
        'pharmacist',
        JSON_OBJECT(
            'order_id', po.order_id, 
            'order_number', po.order_number, 
            'supplier', po.supplier_name, 
            'expected_date', po.expected_delivery_date
        ),
        NOW()
    FROM Purchase_Orders po
    WHERE po.status IN ('PENDING_APPROVAL', 'APPROVED', 'ORDERED')
      AND po.expected_delivery_date < CURDATE();
END //

CREATE EVENT ev_check_expired_medicines
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO Notifications (title, message, type, target_role, details, created_at)
    SELECT 
        'Urgent: Expired Medicines Detected',
        CONCAT('Medication "', med_name, '" (Batch expired on ', expiry_date, ') has reached expiry with ', stock_qty, ' units. Please isolate from active racks.'),
        'MEDICINE_EXPIRED',
        'pharmacist',
        JSON_OBJECT(
            'medicine_id', medicine_id, 
            'med_name', med_name, 
            'expired_qty', stock_qty, 
            'expiry_date', expiry_date
        ),
        NOW()
    FROM Medicines
    WHERE expiry_date <= CURDATE() 
      AND stock_qty > 0 
      AND is_active = TRUE;

    UPDATE Medicines
    SET is_active = FALSE
    WHERE expiry_date <= CURDATE() 
      AND stock_qty > 0;
END //

CREATE EVENT ev_daily_low_stock_alert
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO Notifications (title, message, type, target_role, details, created_at)
    SELECT 
        'Low Stock Warning: Reorder Required',
        CONCAT('Medication "', med_name, '" is below reorder level (Current: ', stock_qty, ' units, Min: ', reorder_level, '). Please place a purchase order.'),
        'LOW_STOCK_WARNING',
        'pharmacist',
        JSON_OBJECT(
            'medicine_id', medicine_id, 
            'med_name', med_name, 
            'stock_qty', stock_qty, 
            'reorder_level', reorder_level,
            'deficit', (reorder_level - stock_qty)
        ),
        NOW()
    FROM Medicines
    WHERE stock_qty <= reorder_level
      AND is_active = TRUE
      AND NOT EXISTS (
          SELECT 1 FROM Notifications n
          WHERE n.type = 'LOW_STOCK_WARNING'
            AND DATE(n.created_at) = CURDATE()
            AND JSON_EXTRACT(n.details, '$.medicine_id') = Medicines.medicine_id
      );
END //

CREATE EVENT ev_weekly_stale_orders_cleanup
ON SCHEDULE EVERY 1 WEEK
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    UPDATE Purchase_Orders
    SET status = 'CANCELLED'
    WHERE status IN ('PENDING_APPROVAL', 'DRAFT')
      AND order_date < DATE_SUB(CURDATE(), INTERVAL 60 DAY);
END //

DELIMITER ;