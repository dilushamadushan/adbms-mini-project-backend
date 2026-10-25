USE hms;



-- 1. Speeds up low stock alerts and dashboard inventory valuation
CREATE INDEX idx_medicines_stock_reorder 
ON Medicines (is_active, stock_qty, reorder_level);

-- 2. Speeds up finding expiring and expired medicines
CREATE INDEX idx_medicines_active_expiry 
ON Medicines (is_active, expiry_date);

-- 3. Speeds up searching medicines by generic name
CREATE INDEX idx_medicines_generic_active 
ON Medicines (generic_name, is_active);

-- 4. Speeds up direct expiry date lookups
CREATE INDEX idx_med_expiry 
ON Medicines (expiry_date);

-- 5. Speeds up stock quantity and reorder threshold checks
CREATE INDEX idx_med_stock 
ON Medicines (stock_qty, reorder_level);

-- 6. Speeds up daily dispensing reports and revenue summaries
CREATE INDEX idx_dispensations_date_med 
ON Dispensations (dispensed_at, medicine_id);

-- 7. Speeds up viewing dispensing history by pharmacist
CREATE INDEX idx_disp_pharmacist 
ON Dispensations (pharmacist_id, dispensed_at);

-- 8. Speeds up tracking frequently dispensed medicines
CREATE INDEX idx_disp_medicine 
ON Dispensations (medicine_id, dispensed_at);

-- 9. Speeds up auditing incoming medicine restock receipts
CREATE INDEX idx_receipts_med_date 
ON Stock_Receipts (medicine_id, received_at);

-- 10. Speeds up tracking purchase orders and overdue delivery alerts
CREATE INDEX idx_po_status_delivery 
ON Purchase_Orders (status, expected_delivery_date);

-- 11. Speeds up filtering purchase orders by order date
CREATE INDEX idx_order_date 
ON Purchase_Orders (order_date);

-- 12. Speeds up filtering purchase orders by approval/delivery status
CREATE INDEX idx_order_status 
ON Purchase_Orders (status);
