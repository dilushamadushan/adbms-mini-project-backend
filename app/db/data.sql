INSERT INTO Departments (dept_name, parent_dept_id) VALUES
    ('Cardiology',          NULL),   -- 1
    ('General Medicine',    NULL),   -- 2
    ('Surgery',             NULL),   -- 3
    ('Orthopedics',         NULL),   -- 4
    ('Pediatrics',          NULL),   -- 5
    ('Obstetrics & Gynecology', NULL), -- 6
    ('Neurology',           NULL),   -- 7
    ('Oncology',            NULL),   -- 8
    ('Radiology',           NULL),   -- 9
    ('Emergency Medicine',  NULL),   -- 10
    ('Pharmacy',            NULL),   -- 11
    ('Administration',      NULL);   -- 12

INSERT INTO Departments (dept_name, parent_dept_id) VALUES
    ('Interventional Cardiology', 1),   -- sub of Cardiology
    ('Cardiac ICU',               1),   -- sub of Cardiology
    ('General Surgery',           3),   -- sub of Surgery
    ('Laparoscopic Surgery',      3),   -- sub of Surgery
    ('Neonatology',               5),   -- sub of Pediatrics
    ('Neuro Surgery',             7),   -- sub of Neurology
    ('Radiation Oncology',        8);   -- sub of Oncology

--   admin:             Admin@123
--   dr.smith:          Doctor@123
--   dr.emily:          Doctor@123
--   nurse.sarah:       Nurse@123
--   receptionist.john: Reception@123
--   patient.jane:      Patient@123
--   patient.bob:       Patient@123
INSERT INTO Users (user_id, username, email, password_hash, role, is_active) VALUES
    (1, 'admin',             'admin@hospital.com',        'e86f78a8a3caf0b60d8e74e5942aa6d86dc150cd3c03338aef25b7d2d7e3acc7', 'admin',        TRUE),
    (2, 'dr.smith',          'dr.smith@hospital.com',     '63bbe564aa5c0882355f6dcd6f2241b6f8d02d6f39725966ae564cd310f07850', 'doctor',       TRUE),
    (3, 'dr.emily',          'dr.emily@hospital.com',     '63bbe564aa5c0882355f6dcd6f2241b6f8d02d6f39725966ae564cd310f07850', 'doctor',       TRUE),
    (4, 'nurse.sarah',       'nurse.sarah@hospital.com',  '07429ac3dabe393512f2633b9514473ec7fc452dd202eb7735e60b900d273fd3', 'nurse',        TRUE),
    (5, 'receptionist.john', 'receptionist@hospital.com', '238f1cf33d39690fba3c171984fc1120a1181d236723d337e6a2fdc8d92ae88a', 'receptionist', TRUE),
    (6, 'patient.jane',      'jane.doe@example.com',      '6dff47814e92e3a14c9f021d2d3ddd353a03e5bf3b0f49d53e80a1a3606c86d6', 'patient',      TRUE),
    (7, 'patient.bob',       'bob.smith@example.com',     '6dff47814e92e3a14c9f021d2d3ddd353a03e5bf3b0f49d53e80a1a3606c86d6', 'patient',      TRUE);

INSERT INTO Staff (staff_id, user_id, dept_id, first_name, last_name, specialty) VALUES
    (1, 2, 1,  'John',  'Smith',    'Cardiologist'),
    (2, 3, 5,  'Emily', 'Stone',    'Pediatrician'),
    (3, 4, 10, 'Sarah', 'Connor',   'Critical Care Nurse'),
    (4, 5, 12, 'John',  'Reception', 'Front Desk Operations');

INSERT INTO Patients (patient_id, user_id, first_name, last_name, dob, blood_group, emergency_contact, allergies) VALUES
    (1, 6, 'Jane', 'Doe',   '1995-04-12', 'O+',  '9876543210', 'Penicillin'),
    (2, 7, 'Bob',  'Smith', '1988-11-23', 'A+',  '9123456780', 'None');

INSERT INTO Appointments (apt_id, patient_id, doctor_id, dept_id, apt_date, time_slot, status) VALUES
    (1, 1, 1, 1, '2026-10-10', '09:30:00', 'Completed'),
    (2, 2, 2, 5, '2026-10-12', '10:00:00', 'Scheduled'),
    (3, 1, 1, 1, '2026-10-20', '14:30:00', 'Scheduled'),
    (4, 2, 1, 1, '2026-10-08', '11:15:00', 'Cancelled');

INSERT INTO Medical_Records (record_id, patient_id, doctor_id, apt_id, diagnosis, clinical_notes) VALUES
    (1, 1, 1, 1, 'Mild Hypertension', 'Patient reported intermittent dizziness. Recommended low-sodium diet and lifestyle modification.'),
    (2, 2, 2, NULL, 'Seasonal Allergies', 'Patient presented with sneezing and nasal congestion. Prescribed antihistamines.');

INSERT INTO Prescriptions (rx_id, record_id, med_name, dosage, duration, status) VALUES
    (1, 1, 'Amlodipine', '5mg once daily', '30 days', 'Active'),
    (2, 1, 'Atorvastatin', '10mg once daily at bedtime', '30 days', 'Active'),
    (3, 2, 'Cetirizine', '10mg once daily', '7 days', 'Active'),
    (4, 2, 'Fluticasone Nasal Spray', '1 spray each nostril daily', '14 days', 'Inactive');

INSERT INTO Lab_Orders (lab_id, patient_id, doctor_id, test_type, status, results_text) VALUES
    (1, 1, 1, 'Lipid Profile', 'Completed', 'Total Cholesterol: 195 mg/dL, HDL: 48 mg/dL, LDL: 120 mg/dL, Triglycerides: 135 mg/dL.'),
    (2, 1, 1, 'Electrocardiogram (ECG)', 'Completed', 'Normal sinus rhythm with no ischemic changes detected.'),
    (3, 2, 2, 'Complete Blood Count (CBC)', 'Pending', NULL);

INSERT INTO Wards (ward_id, ward_name, total_beds, nurse_in_charge_id) VALUES
    (1, 'Cardiology Care Ward',   10, 3),
    (2, 'Pediatric Observation',   8, 3),
    (3, 'General Medicine Ward',  15, 3);

INSERT INTO Beds (bed_id, ward_id, bed_number, status, current_patient_id) VALUES
    (1, 1, 'CCW-101', 'Occupied',  1),
    (2, 1, 'CCW-102', 'Available', NULL),
    (3, 1, 'CCW-103', 'Cleaning',  NULL),
    (4, 2, 'POW-201', 'Occupied',  2),
    (5, 2, 'POW-202', 'Available', NULL),
    (6, 3, 'GMW-301', 'Available', NULL);

INSERT INTO Vitals_Log (vital_id, patient_id, recorded_by, bp, pulse, temperature, recorded_at) VALUES
    (1, 1, 3, '120/80', 74, 98.60, '2026-10-10 09:15:00'),
    (2, 1, 3, '125/82', 78, 98.40, '2026-10-10 17:30:00'),
    (3, 2, 3, '115/75', 82, 99.10, '2026-10-11 08:45:00');

INSERT INTO Audit_Logs (log_id, actor_id, action_type, resource_table, details, timestamp) VALUES
    (1, 1, 'INITIALIZE_DB', 'System', '{"message": "Database initialized with seed dataset"}', '2026-10-11 08:00:00'),
    (2, 1, 'CREATE_USER', 'Users', '{"username": "dr.smith", "role": "doctor"}', '2026-10-11 08:05:00'),
    (3, 2, 'CREATE_APPOINTMENT', 'Appointments', '{"apt_id": 1, "patient_id": 1, "doctor_id": 1}', '2026-10-10 09:00:00');

INSERT INTO Discharges (admission_id,discharge_authorized_by,discharge_authorized_at,discharge_notes,status,discharged_by,discharged_at) VALUES 
(4,2,'2026-10-17 10:00:00','Patient is stable and approved for discharge by the doctor.','Authorized',NULL,NULL);

INSERT INTO Admissions (admission_id, patient_id, ward_id, bed_id, admitted_doctor_id, admitted_by, admitted_at, admission_reason, guardian_name, guardian_relationship, guardian_contact, gender, status) VALUES 
(1, 3, 1, NULL, 1, 5, '2026-10-17 00:59:12', 'headache', 'Wimala', 'Mother', '0112235698', 'Female', 'Pending'), 
(2, 1, 2, NULL, 2, 5, '2026-10-17 01:01:36', 'knee', 'kamal', 'Sibling', '022356987', 'Male', 'Pending'), 
(3, 4, 3, NULL, 2, 5, '2026-10-17 01:18:27', 'accident', 'suresh', 'Father', '011225578', 'Male', 'Admitted'), 
(4, 5, 2, NULL, 2, 5, '2026-10-17 01:21:25', 'baby delivery', 'suhas', 'Legal guardian', '02266547', 'Female', 'Admitted');

INSERT INTO Discharges (admission_id, discharge_authorized_by, discharge_authorized_at, discharge_notes, status, discharged_by, discharged_at) VALUES 
(4, 2, '2026-10-17 10:00:00', 'Patient is stable and approved for discharge by the doctor.', 'Authorized', NULL, NULL);

