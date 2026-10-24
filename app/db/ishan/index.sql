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