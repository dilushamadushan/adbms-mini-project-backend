-- =====================================================================
-- Clinical & Patient Module: Performance Indexes
-- Composite & Covering Indexes for Patient Records, Prescriptions & Alerts
-- Database Engine: MySQL 8.0+ (InnoDB)
-- =====================================================================

USE `hms`;

-- ---------------------------------------------------------------------
-- Index 1: Optimize Patient Medical Records Chronological Retrieval
-- Covers: Searching medical records by patient_id ordered by created_at DESC
-- ---------------------------------------------------------------------
CREATE INDEX `idx_mr_patient_created`
ON `Medical_Records` (`patient_id`, `created_at` DESC);


-- ---------------------------------------------------------------------
-- Index 2: Optimize Prescription Lookups by Medical Record & Status
-- Covers: Quick resolution of attached active/inactive prescriptions
-- ---------------------------------------------------------------------
CREATE INDEX `idx_rx_record_status`
ON `Prescriptions` (`record_id`, `status`);


-- ---------------------------------------------------------------------
-- Index 3: Optimize Active Medication Expiry Scans
-- Covers: Background event scans for active medications by created_at
-- ---------------------------------------------------------------------
CREATE INDEX `idx_rx_status_created`
ON `Prescriptions` (`status`, `created_at`);


-- ---------------------------------------------------------------------
-- Index 4: Optimize Patient Unread Notification Retrieval
-- Covers: Fast unread badges and notification feed queries for patients
-- ---------------------------------------------------------------------
CREATE INDEX `idx_notif_patient_unread`
ON `Notifications` (`target_role`, `target_user_id`, `is_read`, `created_at` DESC);
