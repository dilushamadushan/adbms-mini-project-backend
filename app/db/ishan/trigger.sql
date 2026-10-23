
-- =====================================================
-- Disable the old discharge trigger.
-- The discharge procedure now creates an 'Authorized' request only.
-- It must not change beds or admission status.
-- =====================================================
DROP TRIGGER IF EXISTS `trg_discharge_after_insert`;