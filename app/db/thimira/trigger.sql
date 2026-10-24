

USE hms;

-- ------------------------------------------------------------------------------
-- 1. Trigger: Auto Increase Stock on Receipt
-- Updates stock quantity and adjusts expiry date when new stock arrives.
-- ------------------------------------------------------------------------------
DELIMITER //

DROP TRIGGER IF EXISTS trg_after_stock_receipt_insert //

CREATE TRIGGER trg_after_stock_receipt_insert
AFTER INSERT ON Stock_Receipts
FOR EACH ROW
BEGIN
    -- Increase stock quantity, update expiry date to the newly received batch, and reactivate
    UPDATE Medicines
    SET 
        stock_qty = stock_qty + NEW.quantity,
        expiry_date = COALESCE(NEW.expiry_date, expiry_date),
        is_active = TRUE
    WHERE medicine_id = NEW.medicine_id;

    -- Log to audit
    INSERT INTO Audit_Logs (actor_id, action_type, resource_table, details, timestamp)
    VALUES (
        NEW.received_by,
        'STOCK_RECEIVED',
        'Medicines',
        JSON_OBJECT(
            'medicine_id', NEW.medicine_id,
            'received_qty', NEW.quantity,
            'receipt_id', NEW.receipt_id
        ),
        NOW()
    );
END //

DELIMITER ;


-- ------------------------------------------------------------------------------
-- 2. Trigger: Prevent Dispensing if Stock is Insufficient
-- Ensures we cannot dispense more than available inventory.
-- ------------------------------------------------------------------------------
DELIMITER //

DROP TRIGGER IF EXISTS trg_before_dispensation_insert //

CREATE TRIGGER trg_before_dispensation_insert
BEFORE INSERT ON Dispensations
FOR EACH ROW
BEGIN
    DECLARE current_stock INT DEFAULT 0;

    SELECT stock_qty INTO current_stock
    FROM Medicines
    WHERE medicine_id = NEW.medicine_id;

    IF current_stock < NEW.quantity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Insufficient stock available for this medication';
    END IF;
END //

DELIMITER ;


-- ------------------------------------------------------------------------------
-- 3. Trigger: Auto Deduct Stock on Dispensation & Trigger Low Stock Alert
-- Deducts stock quantity and generates a notification if stock drops below reorder level.
-- ------------------------------------------------------------------------------
DELIMITER //

DROP TRIGGER IF EXISTS trg_after_dispensation_insert //

CREATE TRIGGER trg_after_dispensation_insert
AFTER INSERT ON Dispensations
FOR EACH ROW
BEGIN
    DECLARE remaining_stock INT;
    DECLARE reorder_lvl INT;
    DECLARE med_title VARCHAR(100);

    -- Deduct stock
    UPDATE Medicines
    SET stock_qty = stock_qty - NEW.quantity
    WHERE medicine_id = NEW.medicine_id;

    -- Check updated stock level
    SELECT stock_qty, reorder_level, med_name 
    INTO remaining_stock, reorder_lvl, med_title
    FROM Medicines
    WHERE medicine_id = NEW.medicine_id;

    -- Generate low-stock notification if below reorder level
    IF remaining_stock <= reorder_lvl THEN
        INSERT INTO Notifications (title, message, type, target_role, details, created_at)
        VALUES (
            'Low Stock Alert',
            CONCAT('Warning: Medicine "', med_title, '" stock is low (Remaining: ', remaining_stock, ', Threshold: ', reorder_lvl, ').'),
            'LOW_STOCK',
            'pharmacist',
            JSON_OBJECT(
                'medicine_id', NEW.medicine_id,
                'remaining_stock', remaining_stock,
                'reorder_level', reorder_lvl
            ),
            NOW()
        );
    END IF;
END //

DELIMITER ;


-- ------------------------------------------------------------------------------
-- 4. Trigger: Restock Lead Time Validation
-- Restock order must have expected delivery date at least 1 day in the future.
-- ------------------------------------------------------------------------------
DELIMITER //

DROP TRIGGER IF EXISTS trg_check_po_delivery_lead_time //

CREATE TRIGGER trg_check_po_delivery_lead_time
BEFORE INSERT ON Purchase_Orders
FOR EACH ROW
BEGIN
    IF NEW.expected_delivery_date < DATE_ADD(CURDATE(), INTERVAL 1 DAY) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Restock lead time must be at least 1 day. Expected delivery date must be at least 1 day in advance.';
    END IF;
END //

DELIMITER ;


-- ------------------------------------------------------------------------------
-- 5. Trigger: Enforce 1-Day Transit Before Marking Order as RECEIVED
-- Prevents purchase orders from being marked as RECEIVED before 1 day has passed.
-- ------------------------------------------------------------------------------
DELIMITER //

DROP TRIGGER IF EXISTS trg_check_po_receive_lead_time //

CREATE TRIGGER trg_check_po_receive_lead_time
BEFORE UPDATE ON Purchase_Orders
FOR EACH ROW
BEGIN
    IF NEW.status = 'RECEIVED' AND OLD.status != 'RECEIVED' THEN
        IF DATEDIFF(CURDATE(), DATE(OLD.order_date)) < 1 AND CURDATE() < OLD.expected_delivery_date THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot confirm stock receipt before 1 day from the order date. The order is still in transit from the supplier.';
        END IF;
    END IF;
END //

DELIMITER ;
