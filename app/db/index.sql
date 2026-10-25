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




-- ishan --

-- Speeds up the check "is this patient admitted?"
CREATE INDEX idx_admissions_patient_status 
ON admissions (patient_id, status);

-- Speeds up the night job that looks for Active medicines
CREATE INDEX idx_rx_status_created 
ON prescriptions (status, created_at);

-- Finds old Pending nurse orders quickly (used by the reminder event)
CREATE INDEX idx_orders_status_created 
ON doctor_orders (status, created_at);

-- Finds the doses of a prescription quickly (nurse screens)
CREATE INDEX idx_mar_rx_time 
ON medication_administration_records (rx_id, administered_at);

-- Checks "was a reminder already sent?" quickly
CREATE INDEX idx_notifications_type 
ON notifications (type);

-- Speeds up loading lab results for one patient.
CREATE INDEX idx_lab_orders_patient_date 
ON Lab_Orders (patient_id, ordered_at);

-- Speeds up finding pending lab orders.
CREATE INDEX idx_lab_orders_status 
ON Lab_Orders (status);

-- Speeds up finding a patient's appointments by date.
CREATE INDEX idx_appointments_patient_date 
ON Appointments (patient_id, apt_date);

-- Speeds up filtering appointments by patient and status.
CREATE INDEX idx_appointments_patient_status 
ON Appointments (patient_id, status);

-- Speeds up searching audit logs by action and latest time.
CREATE INDEX idx_audit_logs_action_time 
ON Audit_Logs (action_type, timestamp);

-- Speeds up searching audit logs for a specific table.
CREATE INDEX idx_audit_logs_resource_time 
ON Audit_Logs (resource_table, timestamp);

-- maleesha --

CREATE INDEX `idx_mr_patient_created`
ON `Medical_Records` (`patient_id`, `created_at` DESC);

CREATE INDEX `idx_rx_record_status`
ON `Prescriptions` (`record_id`, `status`);

CREATE INDEX `idx_notif_patient_unread`
ON `Notifications` (`target_role`, `target_user_id`, `is_read`, `created_at` DESC);
