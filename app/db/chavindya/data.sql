INSERT INTO Admissions (admission_id, patient_id, ward_id, bed_id, admitted_doctor_id, admitted_by, admitted_at, admission_reason, guardian_name, guardian_relationship, guardian_contact, gender, status) VALUES 
(1, 3, 1, NULL, 1, 5, '2026-10-17 00:59:12', 'headache', 'Wimala', 'Mother', '0112235698', 'Female', 'Pending'), 
(2, 1, 2, NULL, 2, 5, '2026-10-17 01:01:36', 'knee', 'kamal', 'Sibling', '022356987', 'Male', 'Pending'), 
(3, 4, 3, NULL, 2, 5, '2026-10-17 01:18:27', 'accident', 'suresh', 'Father', '011225578', 'Male', 'Admitted'), 
(4, 5, 2, NULL, 2, 5, '2026-10-17 01:21:25', 'baby delivery', 'suhas', 'Legal guardian', '02266547', 'Female', 'Admitted');

INSERT INTO Discharges (admission_id, discharge_authorized_by, discharge_authorized_at, discharge_notes, status, discharged_by, discharged_at) VALUES 
(4, 2, '2026-10-17 10:00:00', 'Patient is stable and approved for discharge by the doctor.', 'Authorized', NULL, NULL);
