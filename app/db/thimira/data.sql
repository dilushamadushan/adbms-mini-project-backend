-- ==============================================================================
-- Pharmacy Management Seed Data (Thimira)
-- Module: 26 Comprehensive Essential Medicines with Realistic LKR (Rs.) Pricing
-- ==============================================================================

USE hms;

INSERT INTO Medicines (medicine_id, med_name, generic_name, unit_price, stock_qty, reorder_level, expiry_date, is_active) VALUES
    (1,  'Amlodipine 5mg',          'Amlodipine Besylate',       12.00,  150, 30, '2027-06-30', TRUE),
    (2,  'Atorvastatin 10mg',       'Atorvastatin Calcium',      22.00,   85, 25, '2027-04-15', TRUE),
    (3,  'Cetirizine 10mg',         'Cetirizine Hydrochloride',   8.00,  200, 40, '2026-12-31', TRUE),
    (4,  'Fluticasone Nasal Spray', 'Fluticasone Propionate',   450.00,   15, 20, '2026-11-30', TRUE),
    (5,  'Amoxicillin 500mg',       'Amoxicillin Trihydrate',    25.00,  120, 30, '2027-08-20', TRUE),
    (6,  'Paracetamol 500mg',       'Acetaminophen',              5.00,  400, 50, '2028-01-15', TRUE),
    (7,  'Metformin 500mg',         'Metformin Hydrochloride',   10.00,   18, 25, '2027-03-10', TRUE),
    (8,  'Omeprazole 20mg',         'Omeprazole Magnesium',      18.00,   90, 20, '2027-09-05', TRUE),
    (9,  'Ibuprofen 400mg',         'Ibuprofen',                 12.00,  250, 35, '2027-10-12', TRUE),
    (10, 'Azithromycin 250mg',      'Azithromycin Dihydrate',    65.00,   60, 15, '2026-10-25', TRUE),
    (11, 'Losartan Potassium 50mg', 'Losartan Potassium',        18.00,  180, 40, '2027-05-15', TRUE),
    (12, 'Ciprofloxacin 500mg',     'Ciprofloxacin HCl',         32.00,   95, 30, '2027-02-28', TRUE),
    (13, 'Salbutamol Inhaler 100mcg','Salbutamol Sulfate',      850.00,   12, 20, '2026-11-15', TRUE),
    (14, 'Insulin Glargine 100IU',  'Insulin Glargine',        2450.00,   25, 10, '2027-08-10', TRUE),
    (15, 'Diclofenac Sodium 50mg',  'Diclofenac Sodium',          8.00,  300, 50, '2027-11-20', TRUE),
    (16, 'Clopidogrel 75mg',        'Clopidogrel Bisulfate',     45.00,  140, 30, '2027-04-12', TRUE),
    (17, 'Pantoprazole 40mg',       'Pantoprazole Sodium',       28.00,  210, 40, '2028-03-01', TRUE),
    (18, 'Doxycycline 100mg',       'Doxycycline Hyclate',       16.00,    8, 25, '2026-12-05', TRUE),
    (19, 'Furosemide 40mg',         'Furosemide',                 6.00,  250, 40, '2027-09-18', TRUE),
    (20, 'Montelukast 10mg',        'Montelukast Sodium',        38.00,  110, 25, '2027-06-22', TRUE),
    (21, 'Ceftriaxone 1g Injection','Ceftriaxone Sodium',       620.00,   50, 15, '2027-11-30', TRUE),
    (22, 'Tramadol 50mg',           'Tramadol Hydrochloride',    22.00,   80, 20, '2027-07-14', TRUE),
    (23, 'Glibenclamide 5mg',       'Glibenclamide',              7.00,  160, 30, '2027-12-10', TRUE),
    (24, 'Levothyroxine 50mcg',     'Levothyroxine Sodium',      14.00,  320, 50, '2028-02-15', TRUE),
    (25, 'Prednisolone 5mg',        'Prednisolone',               5.00,  450, 60, '2027-10-05', TRUE),
    (26, 'ORS Hydration Sachet',    'Oral Rehydration Salts',    45.00,  500, 80, '2028-06-30', TRUE)
ON DUPLICATE KEY UPDATE
    med_name = VALUES(med_name),
    generic_name = VALUES(generic_name),
    unit_price = VALUES(unit_price),
    stock_qty = VALUES(stock_qty),
    reorder_level = VALUES(reorder_level),
    expiry_date = VALUES(expiry_date),
    is_active = VALUES(is_active);
