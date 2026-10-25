

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
-- 3. Procedure: Update Purchase Order Status
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
-- 4. Procedure: Receive and Restock Delivered Purchase Order
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
-- 5. Procedure: Get Stock Receipts History (Restock Audit Log)
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



