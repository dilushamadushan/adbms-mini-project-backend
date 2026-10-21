USE hms;


INSERT IGNORE INTO Beds (bed_id, ward_id, bed_number, status, current_patient_id) VALUES
    (7,  1, 'CCW-104', 'Occupied',  2),
    (8,  1, 'CCW-105', 'Cleaning',  NULL),
    (9,  1, 'CCW-106', 'Occupied',  3),
    (10, 1, 'CCW-107', 'Available', NULL),
    (11, 1, 'CCW-108', 'Available', NULL),
    (12, 1, 'CCW-109', 'Available', NULL),
    (13, 1, 'CCW-110', 'Available', NULL);

INSERT IGNORE INTO Admissions (admission_id, patient_id, ward_id, bed_id, admitted_doctor_id, admitted_by, admitted_at, admission_reason, guardian_name, guardian_relationship, guardian_contact, gender, status)
VALUES 
    (1, 1, 1, 1, 1, 1, '2026-10-20 09:30:00', 'Chest pain and arrhythmia monitoring', 'John Doe', 'Spouse', '0771234567', 'Female', 'Admitted'),
    (2, 2, 1, 7, 1, 1, '2026-10-20 14:00:00', 'Hypertension observation', 'Mary Smith', 'Mother', '0779876543', 'Male', 'Admitted'),
    (3, 3, 1, 9, 1, 1, '2026-10-21 10:15:00', 'Acute Asthma Exacerbation & Bronchospasm', 'Sarah Smith', 'Sister', '0773344556', 'Male', 'Admitted')
ON DUPLICATE KEY UPDATE status=VALUES(status);

INSERT IGNORE INTO Discharges (discharge_id, admission_id, discharge_authorized_by, discharge_authorized_at, discharge_notes, status, discharged_by, discharged_at)
VALUES 
    (1, 2, 1, '2026-10-21 11:00:00', 'Vitals stabilized. Approved for home discharge with prescription.', 'Authorized', NULL, NULL)
ON DUPLICATE KEY UPDATE status=VALUES(status);

INSERT IGNORE INTO Vitals_Log (vital_id, patient_id, recorded_by, bp, pulse, temperature, spo2, resp_rate, blood_sugar, weight, recorded_at) VALUES
    (10, 1, 3, '118/78', 70, 98.40, 98, 16, 105.0, 68.5, '2026-10-21 08:00:00'),
    (11, 2, 3, '142/92', 96, 99.80, 96, 20, 130.0, 74.0, '2026-10-21 08:30:00')
ON DUPLICATE KEY UPDATE spo2=VALUES(spo2), resp_rate=VALUES(resp_rate);

INSERT IGNORE INTO Medication_Administration_Records (mar_id, rx_id, patient_id, administered_by, scheduled_time, status, reason, notes, administered_at) VALUES
    (1, 1, 1, 3, '08:00', 'Given', NULL, 'Administered with water after breakfast.', '2026-10-21 08:15:00'),
    (2, 2, 1, 3, '20:00', 'Given', NULL, 'Administered at bedtime.', '2026-10-20 20:30:00'),
    (3, 3, 2, 3, '09:00', 'Given', NULL, 'Oral tablet tolerated well.', '2026-10-21 09:00:00');

INSERT IGNORE INTO Doctor_Orders (order_id, patient_id, doctor_id, order_type, instruction, status, acknowledged_by, acknowledged_at, created_at) VALUES
    (1, 1, 1, 'Diet', 'Low-sodium, heart-healthy diet. Fluid restriction to 1.5L / 24 hours.', 'Acknowledged', 3, '2026-10-21 08:30:00', '2026-10-20 10:00:00'),
    (2, 1, 1, 'Nursing_Care', 'Check vitals every 4 hours. Continuous SpO2 and ECG telemetry.', 'Acknowledged', 3, '2026-10-21 08:30:00', '2026-10-20 10:15:00'),
    (3, 1, 1, 'Lab', 'Morning fasting lipid profile and basic metabolic panel.', 'Pending', NULL, NULL, '2026-10-21 07:00:00'),
    (4, 2, 1, 'Special', 'Patient approved for home discharge. Deliver prescription education and remove IV cannula.', 'Acknowledged', 3, '2026-10-21 11:15:00', '2026-10-21 11:00:00');

INSERT IGNORE INTO Nursing_Notes (note_id, patient_id, nurse_id, note_type, subjective, objective, assessment, plan, content, created_at) VALUES
    (1, 1, 3, 'SOAP', 
     'Patient denies active chest pressure; slept comfortably overnight.', 
     'BP 118/78, HR 70 regular, SpO2 98% on room air. Lungs clear to auscultation.', 
     'Hemodynamically stable post-admission.', 
     'Continue scheduled telemetry monitoring and low sodium diet.', 
     'Patient is alert and oriented x4. Morning meds given as scheduled.', 
     '2026-10-21 09:00:00'),
    (2, 2, 3, 'CarePlan', 
     NULL, NULL, NULL, NULL, 
     'Encourage ambulation in hallway twice daily with assistance. Ice pack to right knee as needed.', 
     '2026-10-21 10:00:00');

INSERT IGNORE INTO Intake_Output_Logs (io_id, patient_id, recorded_by, io_type, category, volume_ml, notes, recorded_at) VALUES
    (1, 1, 3, 'Intake', 'Oral', 350, 'Water with breakfast', '2026-10-21 08:30:00'),
    (2, 1, 3, 'Intake', 'IV Fluids', 500, 'Normal Saline infusion (0.9%)', '2026-10-21 10:00:00'),
    (3, 1, 3, 'Output', 'Urine', 450, 'Clear pale yellow', '2026-10-21 10:30:00'),
    (4, 1, 3, 'Intake', 'Oral', 200, 'Soup with lunch', '2026-10-21 12:30:00'),
    (5, 1, 3, 'Output', 'Urine', 300, 'Clear', '2026-10-21 13:00:00');

INSERT IGNORE INTO Shift_Handovers (handover_id, ward_id, outgoing_nurse_id, incoming_nurse_id, shift_type, handover_date, summary_notes, critical_patients_count, pending_tasks_count, status, accepted_at, created_at) VALUES
    (1, 1, 3, NULL, 'Day', '2026-10-21', 
     'Ward Census: 2 patients in beds CCW-101 (Jane Doe) and CCW-104 (Bob Smith). Jane Doe is stable on telemetry. Bob Smith has doctor authorization for discharge pending nurse completion.', 
     0, 1, 'Pending_Acceptance', NULL, '2026-10-21 14:45:00');
