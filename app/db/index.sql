-- TG/1407 --

CREATE INDEX idx_tokens_expires_revoked 
ON Refresh_Tokens (expires_at, revoked);

CREATE INDEX idx_tokens_user_revoked 
ON Refresh_Tokens (user_id, revoked, expires_at);

CREATE INDEX idx_departments_hierarchy 
ON Departments (parent_dept_id, dept_name);

CREATE INDEX idx_appt_doctor_status 
ON Appointments (doctor_id, status);

CREATE INDEX idx_appt_dept_date 
ON Appointments (dept_id, apt_date);

CREATE INDEX idx_staff_dept 
ON Staff (dept_id);

CREATE INDEX idx_audit_actor_action 
ON Audit_Logs (actor_id, action_type);

-- Chavi --

CREATE INDEX idx_patients_first_name 
ON Patients (first_name);

CREATE INDEX idx_patients_last_name 
ON Patients (last_name);

-- thimira --

CREATE INDEX idx_medicines_stock_reorder 
ON Medicines (is_active, stock_qty, reorder_level);

CREATE INDEX idx_medicines_active_expiry 
ON Medicines (is_active, expiry_date);

CREATE INDEX idx_medicines_generic_active 
ON Medicines (generic_name, is_active);

CREATE INDEX idx_med_expiry 
ON Medicines (expiry_date);

CREATE INDEX idx_med_stock 
ON Medicines (stock_qty, reorder_level);

CREATE INDEX idx_dispensations_date_med 
ON Dispensations (dispensed_at, medicine_id);

CREATE INDEX idx_disp_pharmacist 
ON Dispensations (pharmacist_id, dispensed_at);

CREATE INDEX idx_disp_medicine 
ON Dispensations (medicine_id, dispensed_at);

CREATE INDEX idx_receipts_med_date 
ON Stock_Receipts (medicine_id, received_at);

CREATE INDEX idx_po_status_delivery 
ON Purchase_Orders (status, expected_delivery_date);

CREATE INDEX idx_order_date 
ON Purchase_Orders (order_date);

CREATE INDEX idx_order_status 
ON Purchase_Orders (status);
