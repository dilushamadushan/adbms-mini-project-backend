-- ==============================================================================
-- Pharmacy Management Table Schemas (Thimira)
-- Module: Medicine Inventory, Stock Receipts, Dispensations, and Purchase Orders
-- ==============================================================================

USE hms;

-- ------------------------------------------------------------------------------
-- 1. Medicines Table
-- Stores pharmaceutical drugs, pricing in LKR (Rs.), stock levels, and expiry.
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Medicines (
    medicine_id    INT AUTO_INCREMENT PRIMARY KEY,
    med_name       VARCHAR(100) NOT NULL UNIQUE,
    generic_name   VARCHAR(100) NULL,
    unit_price     DECIMAL(10,2) NOT NULL COMMENT 'Unit price in Rupees (Rs.)',
    stock_qty      INT NOT NULL DEFAULT 0,
    reorder_level  INT NOT NULL DEFAULT 20,
    expiry_date    DATE NULL,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_med_stock_nonneg   CHECK (stock_qty >= 0),
    CONSTRAINT chk_med_price_positive CHECK (unit_price > 0),
    CONSTRAINT chk_med_reorder_nonneg CHECK (reorder_level >= 0),
    INDEX idx_med_expiry (expiry_date),
    INDEX idx_med_stock  (stock_qty, reorder_level),
    FULLTEXT KEY ft_med_name (med_name, generic_name)
);

-- ------------------------------------------------------------------------------
-- 2. Stock_Receipts Table
-- Records incoming medicine shipments, restocking quantities, and new batch expiries.
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Stock_Receipts (
    receipt_id   INT AUTO_INCREMENT PRIMARY KEY,
    medicine_id  INT NOT NULL,
    quantity     INT NOT NULL,
    expiry_date  DATE NOT NULL,
    received_by  INT NOT NULL,
    received_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_receipt_qty_positive CHECK (quantity > 0),
    FOREIGN KEY (medicine_id) REFERENCES Medicines(medicine_id),
    FOREIGN KEY (received_by) REFERENCES Staff(staff_id),
    INDEX idx_receipt_medicine (medicine_id, received_at)
);

-- ------------------------------------------------------------------------------
-- 3. Dispensations Table
-- Records medications dispensed to patients against doctor prescriptions.
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Dispensations (
    dispense_id        INT AUTO_INCREMENT PRIMARY KEY,
    rx_id              INT NOT NULL,
    medicine_id        INT NOT NULL,
    pharmacist_id      INT NOT NULL,
    admission_id       INT NULL,
    quantity           INT NOT NULL,
    unit_price_at_sale DECIMAL(10,2) NOT NULL COMMENT 'Sale unit price in Rupees (Rs.)',
    dispensed_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_disp_qty_positive CHECK (quantity > 0),
    UNIQUE KEY uq_one_dispense_per_rx (rx_id),
    FOREIGN KEY (rx_id)         REFERENCES Prescriptions(rx_id),
    FOREIGN KEY (medicine_id)   REFERENCES Medicines(medicine_id),
    FOREIGN KEY (pharmacist_id) REFERENCES Staff(staff_id),
    FOREIGN KEY (admission_id)  REFERENCES Admissions(admission_id),
    INDEX idx_disp_pharmacist (pharmacist_id, dispensed_at),
    INDEX idx_disp_medicine   (medicine_id, dispensed_at)
);

-- ------------------------------------------------------------------------------
-- 4. Purchase_Orders Table (Restock Orders)
-- Stores official procurement requisitions with minimum 3-day lead time.
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Purchase_Orders (
    order_id               INT AUTO_INCREMENT PRIMARY KEY,
    order_number           VARCHAR(50) NOT NULL UNIQUE,
    pharmacist_id          INT NOT NULL,
    supplier_name          VARCHAR(150) NOT NULL DEFAULT 'State Pharmaceuticals Corporation',
    order_date             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expected_delivery_date DATE NOT NULL,
    total_cost             DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    status                 ENUM('PENDING_APPROVAL', 'APPROVED', 'ORDERED', 'RECEIVED', 'CANCELLED') NOT NULL DEFAULT 'PENDING_APPROVAL',
    notes                  TEXT NULL,
    created_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (pharmacist_id) REFERENCES Staff(staff_id),
    INDEX idx_order_date (order_date),
    INDEX idx_order_status (status)
);

-- ------------------------------------------------------------------------------
-- 5. Purchase_Order_Items Table
-- Stores individual medicines and requested quantities within a purchase order.
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Purchase_Order_Items (
    item_id            INT AUTO_INCREMENT PRIMARY KEY,
    order_id           INT NOT NULL,
    medicine_id        INT NOT NULL,
    requested_quantity INT NOT NULL,
    unit_price         DECIMAL(10,2) NOT NULL,
    subtotal           DECIMAL(10,2) NOT NULL,
    CONSTRAINT chk_po_qty_positive CHECK (requested_quantity > 0),
    FOREIGN KEY (order_id) REFERENCES Purchase_Orders(order_id) ON DELETE CASCADE,
    FOREIGN KEY (medicine_id) REFERENCES Medicines(medicine_id)
);
