USE `hms`;

-- =====================================================
-- 1. Add a 'Discharged' status to admissions
--    (admissions keep their row after discharge; only the status changes)
-- =====================================================
ALTER TABLE `admissions`
  MODIFY COLUMN `status` ENUM('Admitted', 'Pending', 'Discharged') NOT NULL DEFAULT 'Pending';


-- =====================================================
-- 2. One admission can only have ONE discharge request
-- (run once; if the index already exists, skip this line)
-- =====================================================
ALTER TABLE `discharges` ADD UNIQUE KEY `uq_discharge_admission` (`admission_id`);

