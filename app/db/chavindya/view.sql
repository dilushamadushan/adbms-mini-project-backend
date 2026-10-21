USE hms;

CREATE OR REPLACE VIEW vw_recep_appointments AS
SELECT a.apt_id, a.patient_id,
       CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
       a.doctor_id, CONCAT('Dr. ', s.first_name, ' ', s.last_name) AS doctor_name,
       a.dept_id, d.dept_name,
       a.apt_date,
       TIME_FORMAT(a.time_slot, '%H:%i') AS time_slot,
       a.status
FROM Appointments a
JOIN Patients p ON p.patient_id = a.patient_id
JOIN Staff s ON s.staff_id = a.doctor_id
JOIN Departments d ON d.dept_id = a.dept_id;