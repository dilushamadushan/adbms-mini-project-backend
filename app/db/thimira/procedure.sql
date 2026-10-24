

USE hms;

-- ------------------------------------------------------------------------------
-- 1. Procedure: Add or Update Medicine Details
-- Inserts a new medicine or updates existing details.
-- ------------------------------------------------------------------------------
DELIMITER //

DROP PROCEDURE IF EXISTS sp_add_or_update_medicine //

CREATE PROCEDURE sp_add_or_update_medicine(
    IN p_medicine_id INT,
    IN p_med_name VARCHAR(100),
    IN p_generic_name VARCHAR(100),
    IN p_unit_price DECIMAL(10,2),
    IN p_stock_qty INT,
    IN p_reorder_level INT,
    IN p_expiry_date DATE,
    IN p_is_active BOOLEAN,
    OUT p_out_id INT
)
BEGIN
    IF p_medicine_id IS NULL OR p_medicine_id = 0 THEN
        -- Insert new medicine
        INSERT INTO Medicines (
            med_name, generic_name, unit_price, stock_qty, 
            reorder_level, expiry_date, is_active
        ) VALUES (
            p_med_name, p_generic_name, p_unit_price, COALESCE(p_stock_qty, 0),
            COALESCE(p_reorder_level, 20), p_expiry_date, COALESCE(p_is_active, TRUE)
        );
        SET p_out_id = LAST_INSERT_ID();
    ELSE
        -- Update existing medicine
        UPDATE Medicines
        SET 
            med_name = p_med_name,
            generic_name = p_generic_name,
            unit_price = p_unit_price,
            stock_qty = COALESCE(p_stock_qty, stock_qty),
            reorder_level = COALESCE(p_reorder_level, reorder_level),
            expiry_date = COALESCE(p_expiry_date, expiry_date),
            is_active = COALESCE(p_is_active, is_active)
        WHERE medicine_id = p_medicine_id;
        SET p_out_id = p_medicine_id;
    END IF;
END //

DELIMITER ;


-- ------------------------------------------------------------------------------
-- 2. Procedure: Receive Stock (Restocking batch)
-- Records a stock receipt (which automatically triggers stock increment).
-- ------------------------------------------------------------------------------
DELIMITER //

DROP PROCEDURE IF EXISTS sp_receive_stock //

CREATE PROCEDURE sp_receive_stock(
    IN p_medicine_id INT,
    IN p_quantity INT,
    IN p_expiry_date DATE,
    IN p_received_by INT,
    OUT p_receipt_id INT
)
BEGIN
    IF p_quantity <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Quantity received must be greater than zero.';
    END IF;

    -- Insert into Stock_Receipts; trigger automatically updates Medicines stock & audit log
    INSERT INTO Stock_Receipts (
        medicine_id, quantity, expiry_date, received_by, received_at
    ) VALUES (
        p_medicine_id, p_quantity, p_expiry_date, p_received_by, NOW()
    );

    SET p_receipt_id = LAST_INSERT_ID();
END //

DELIMITER ;


-- ------------------------------------------------------------------------------
-- 3. Procedure: Get Low Stock Medicine Alerts
-- Fetches all medicines at or below their defined reorder threshold.
-- ------------------------------------------------------------------------------
DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_low_stock_alerts //

CREATE PROCEDURE sp_get_low_stock_alerts()
BEGIN
    SELECT 
        medicine_id,
        med_name,
        generic_name,
        stock_qty,
        reorder_level,
        unit_price,
        expiry_date,
        (reorder_level - stock_qty) AS deficit_quantity
    FROM Medicines
    WHERE stock_qty <= reorder_level
      AND is_active = TRUE
    ORDER BY stock_qty ASC;
END //

DELIMITER ;


-- ------------------------------------------------------------------------------
-- 4. Procedure: Get Expired / Near-Expiry Medicines
-- Fetches medicines expiring within a given number of days or already expired.
-- ------------------------------------------------------------------------------
DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_expiring_medicines //

CREATE PROCEDURE sp_get_expiring_medicines(
    IN p_days_threshold INT
)
BEGIN
    SET p_days_threshold = COALESCE(p_days_threshold, 30);

    SELECT 
        medicine_id,
        med_name,
        generic_name,
        stock_qty,
        unit_price,
        expiry_date,
        DATEDIFF(expiry_date, CURDATE()) AS days_left,
        CASE 
            WHEN expiry_date <= CURDATE() THEN 'EXPIRED'
            ELSE 'EXPIRING_SOON'
        END AS urgency_status
    FROM Medicines
    WHERE expiry_date <= DATE_ADD(CURDATE(), INTERVAL p_days_threshold DAY)
      AND stock_qty > 0
      AND is_active = TRUE
    ORDER BY expiry_date ASC;
END //

DELIMITER ;


-- ------------------------------------------------------------------------------
-- 5. Procedure: Get Frequently Dispensed Medicines (Top N)
-- Identifies highest-volume medications dispensed.
-- ------------------------------------------------------------------------------
DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_frequently_dispensed_medicines //

CREATE PROCEDURE sp_get_frequently_dispensed_medicines(
    IN p_limit INT
)
BEGIN
    SET p_limit = COALESCE(p_limit, 10);

    SELECT 
        m.medicine_id,
        m.med_name,
        m.generic_name,
        m.stock_qty AS current_stock,
        COUNT(d.dispense_id) AS total_dispense_events,
        COALESCE(SUM(d.quantity), 0) AS total_units_dispensed,
        COALESCE(SUM(d.quantity * d.unit_price_at_sale), 0.00) AS total_revenue_generated
    FROM Medicines m
    LEFT JOIN Dispensations d ON m.medicine_id = d.medicine_id
    GROUP BY m.medicine_id, m.med_name, m.generic_name, m.stock_qty
    ORDER BY total_units_dispensed DESC
    LIMIT p_limit;
END //

DELIMITER ;


-- ------------------------------------------------------------------------------
-- 6. Procedure: Get Daily Dispensing and Revenue Report
-- Summarizes dispensing by day within a given date range.
-- ------------------------------------------------------------------------------
DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_daily_dispensing_report //

CREATE PROCEDURE sp_get_daily_dispensing_report(
    IN p_start_date DATE,
    IN p_end_date DATE
)
BEGIN
    SET p_start_date = COALESCE(p_start_date, DATE_SUB(CURDATE(), INTERVAL 30 DAY));
    SET p_end_date   = COALESCE(p_end_date, CURDATE());

    SELECT 
        DATE(d.dispensed_at) AS report_date,
        COUNT(d.dispense_id) AS total_dispensations,
        COALESCE(SUM(d.quantity), 0) AS total_units,
        COALESCE(SUM(d.quantity * d.unit_price_at_sale), 0.00) AS total_revenue
    FROM Dispensations d
    WHERE DATE(d.dispensed_at) BETWEEN p_start_date AND p_end_date
    GROUP BY DATE(d.dispensed_at)
    ORDER BY report_date DESC;
END //

DELIMITER ;


-- ------------------------------------------------------------------------------
-- 7. Procedure: Get Pharmacy Dashboard Overview KPIs
-- Aggregates high-level metrics for quick display on pharmacist dashboard.
-- ------------------------------------------------------------------------------
DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_pharmacy_dashboard_kpis //

CREATE PROCEDURE sp_get_pharmacy_dashboard_kpis()
BEGIN
    SELECT 
        (SELECT COUNT(*) FROM Medicines WHERE is_active = TRUE) AS total_medicines,
        (SELECT COALESCE(SUM(stock_qty), 0) FROM Medicines WHERE is_active = TRUE) AS total_stock_units,
        (SELECT COUNT(*) FROM Medicines WHERE stock_qty <= reorder_level AND is_active = TRUE) AS low_stock_count,
        (SELECT COUNT(*) FROM Medicines WHERE expiry_date <= CURDATE() AND stock_qty > 0 AND is_active = TRUE) AS expired_count,
        (SELECT COUNT(*) FROM Medicines WHERE expiry_date > CURDATE() AND expiry_date <= DATE_ADD(CURDATE(), INTERVAL 30 DAY) AND stock_qty > 0 AND is_active = TRUE) AS expiring_soon_count,
        (SELECT fn_get_total_inventory_value()) AS total_inventory_valuation,
        (SELECT COALESCE(SUM(quantity), 0) FROM Dispensations WHERE DATE(dispensed_at) = CURDATE()) AS today_units_dispensed,
        (SELECT COALESCE(SUM(quantity * unit_price_at_sale), 0.00) FROM Dispensations WHERE DATE(dispensed_at) = CURDATE()) AS today_revenue;
END //

DELIMITER ;


-- ------------------------------------------------------------------------------
-- 8. Procedure: List Purchase Orders with Items & Pharmacist Details
-- ------------------------------------------------------------------------------
DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_purchase_orders //

CREATE PROCEDURE sp_get_purchase_orders()
BEGIN
    SELECT 
        po.order_id,
        po.order_number,
        po.supplier_name,
        po.order_date,
        po.expected_delivery_date,
        DATEDIFF(po.expected_delivery_date, DATE(po.order_date)) AS lead_time_days,
        po.total_cost,
        po.status,
        po.notes,
        po.pharmacist_id,
        CONCAT(s.first_name, ' ', s.last_name) AS pharmacist_name,
        COUNT(poi.item_id) AS total_items,
        GROUP_CONCAT(DISTINCT CONCAT(m.med_name, ' (', poi.requested_quantity, ' units)') SEPARATOR ', ') AS ordered_medicines
    FROM Purchase_Orders po
    LEFT JOIN Staff s ON po.pharmacist_id = s.staff_id
    LEFT JOIN Purchase_Order_Items poi ON po.order_id = poi.order_id
    LEFT JOIN Medicines m ON poi.medicine_id = m.medicine_id
    GROUP BY po.order_id, po.order_number, po.supplier_name, po.order_date, 
             po.expected_delivery_date, po.total_cost, po.status, po.notes, 
             po.pharmacist_id, s.first_name, s.last_name
    ORDER BY po.order_date DESC;
END //

DELIMITER ;


-- ------------------------------------------------------------------------------
-- 9. Procedure: Update Purchase Order Status
-- ------------------------------------------------------------------------------
DELIMITER //

DROP PROCEDURE IF EXISTS sp_update_purchase_order_status //

CREATE PROCEDURE sp_update_purchase_order_status(
    IN p_order_id INT,
    IN p_status VARCHAR(30)
)
BEGIN
    DECLARE v_order_date DATETIME;
    DECLARE v_expected_date DATE;

    IF p_status = 'RECEIVED' THEN
        SELECT order_date, expected_delivery_date 
        INTO v_order_date, v_expected_date
        FROM Purchase_Orders
        WHERE order_id = p_order_id;

        IF DATEDIFF(CURDATE(), DATE(v_order_date)) < 1 AND CURDATE() < v_expected_date THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot confirm stock receipt before 1 day from the order date. The order is still in transit from the supplier.';
        END IF;
    END IF;

    UPDATE Purchase_Orders
    SET status = p_status
    WHERE order_id = p_order_id;
END //

DELIMITER ;


-- ------------------------------------------------------------------------------
-- 10. Procedure: Receive and Restock Delivered Purchase Order
-- Updates order status to RECEIVED and automatically inserts into Stock_Receipts
-- for each ordered item, thereby triggering automatic stock increases in Medicines.
-- ------------------------------------------------------------------------------
DELIMITER //

DROP PROCEDURE IF EXISTS sp_receive_and_restock_purchase_order //

CREATE PROCEDURE sp_receive_and_restock_purchase_order(
    IN p_order_id INT,
    IN p_staff_id INT,
    IN p_batch_expiry_date DATE
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_med_id INT;
    DECLARE v_qty INT;
    DECLARE v_order_num VARCHAR(50);
    DECLARE v_cur_status VARCHAR(30);
    DECLARE v_order_date DATETIME;
    DECLARE v_expected_date DATE;

    -- Cursor to iterate through all medicines in the order
    DECLARE cur_items CURSOR FOR 
        SELECT medicine_id, requested_quantity 
        FROM Purchase_Order_Items 
        WHERE order_id = p_order_id;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    -- Check current order status and transit lead time
    SELECT order_number, status, order_date, expected_delivery_date 
    INTO v_order_num, v_cur_status, v_order_date, v_expected_date
    FROM Purchase_Orders
    WHERE order_id = p_order_id;

    IF v_cur_status = 'RECEIVED' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'This purchase order has already been received and restocked.';
    END IF;

    -- Enforce 1-day delivery transit before receiving
    IF DATEDIFF(CURDATE(), DATE(v_order_date)) < 1 AND CURDATE() < v_expected_date THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot confirm stock receipt before 1 day from the order date. The order is still in transit from the supplier.';
    END IF;

    SET p_batch_expiry_date = COALESCE(p_batch_expiry_date, DATE_ADD(CURDATE(), INTERVAL 1 YEAR));

    OPEN cur_items;

    read_loop: LOOP
        FETCH cur_items INTO v_med_id, v_qty;
        IF done THEN
            LEAVE read_loop;
        END IF;

        -- Insert into Stock_Receipts (this fires trg_after_stock_receipt_insert to increase stock)
        INSERT INTO Stock_Receipts (medicine_id, quantity, expiry_date, received_by, received_at)
        VALUES (v_med_id, v_qty, p_batch_expiry_date, p_staff_id, NOW());
    END LOOP;

    CLOSE cur_items;

    -- Mark order as RECEIVED
    UPDATE Purchase_Orders
    SET status = 'RECEIVED'
    WHERE order_id = p_order_id;

    -- Notify pharmacist that restock is completed
    INSERT INTO Notifications (title, message, type, target_role, details, created_at)
    VALUES (
        'Order Restocked',
        CONCAT('Restock order "', v_order_num, '" has been verified and items added to active inventory.'),
        'STOCK_RESTOCKED',
        'pharmacist',
        JSON_OBJECT('order_id', p_order_id, 'order_number', v_order_num),
        NOW()
    );
END //

DELIMITER ;


-- ------------------------------------------------------------------------------
-- 11. Procedure: Get Stock Receipts History (Restock Audit Log)
-- Returns full audit history of stock batches received into inventory.
-- ------------------------------------------------------------------------------
DELIMITER //

DROP PROCEDURE IF EXISTS sp_get_stock_receipts_history //

CREATE PROCEDURE sp_get_stock_receipts_history(
    IN p_limit INT
)
BEGIN
    SET p_limit = COALESCE(p_limit, 50);

    SELECT 
        sr.receipt_id,
        sr.medicine_id,
        m.med_name,
        m.generic_name,
        sr.quantity,
        sr.expiry_date,
        sr.received_by,
        CONCAT(s.first_name, ' ', s.last_name) AS received_by_name,
        sr.received_at
    FROM Stock_Receipts sr
    JOIN Medicines m ON sr.medicine_id = m.medicine_id
    LEFT JOIN Staff s ON sr.received_by = s.staff_id
    ORDER BY sr.received_at DESC
    LIMIT p_limit;
END //

DELIMITER ;



