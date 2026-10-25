-- Speeds up the check "is this patient admitted?"
CREATE INDEX idx_admissions_patient_status ON admissions (patient_id, status);

-- Speeds up the night job that looks for Active medicines
CREATE INDEX idx_rx_status_created ON prescriptions (status, created_at);






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