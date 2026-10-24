USE hms;


CREATE OR REPLACE VIEW vw_nurse_ward_overview AS
SELECT 
    w.ward_id,
    w.ward_name,
    w.total_beds,
    w.nurse_in_charge_id,
    CONCAT(s.first_name, ' ', s.last_name) AS nurse_name,
    COUNT(CASE WHEN b.status = 'Occupied' THEN 1 END) AS occupied_beds,
    COUNT(CASE WHEN b.status = 'Available' THEN 1 END) AS available_beds,
    COUNT(CASE WHEN b.status = 'Cleaning' THEN 1 END) AS cleaning_beds,
    ROUND(
        COALESCE(
            (COUNT(CASE WHEN b.status = 'Occupied' THEN 1 END) * 100.0) / NULLIF(w.total_beds, 0),
            0
        ),
        1
    ) AS occupancy_rate
FROM Wards w
LEFT JOIN Staff s ON w.nurse_in_charge_id = s.staff_id
LEFT JOIN Beds b ON w.ward_id = b.ward_id
GROUP BY w.ward_id, w.ward_name, w.total_beds, w.nurse_in_charge_id, s.first_name, s.last_name;


CREATE OR REPLACE VIEW vw_nurse_ward_beds AS
SELECT 
    b.bed_id,
    b.bed_number,
    b.ward_id,
    w.ward_name,
    w.nurse_in_charge_id,
    b.status AS bed_status,
    b.current_patient_id,
    CASE 
        WHEN p.patient_id IS NOT NULL THEN CONCAT(p.first_name, ' ', p.last_name)
        ELSE NULL
    END AS patient_name,
    p.dob,
    p.blood_group,
    p.allergies,
    adm.admission_id,
    adm.admitted_at,
    adm.admission_reason,
    CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS attending_doctor_name,
    dis.discharge_id,
    dis.status AS discharge_status,
    (
        SELECT vl.bp 
        FROM Vitals_Log vl 
        WHERE vl.patient_id = b.current_patient_id 
        ORDER BY vl.recorded_at DESC 
        LIMIT 1
    ) AS latest_bp,
    (
        SELECT vl.pulse 
        FROM Vitals_Log vl 
        WHERE vl.patient_id = b.current_patient_id 
        ORDER BY vl.recorded_at DESC 
        LIMIT 1
    ) AS latest_pulse,
    (
        SELECT vl.temperature 
        FROM Vitals_Log vl 
        WHERE vl.patient_id = b.current_patient_id 
        ORDER BY vl.recorded_at DESC 
        LIMIT 1
    ) AS latest_temperature,
    (
        SELECT vl.spo2 
        FROM Vitals_Log vl 
        WHERE vl.patient_id = b.current_patient_id 
        ORDER BY vl.recorded_at DESC 
        LIMIT 1
    ) AS latest_spo2,
    (
        SELECT vl.recorded_at 
        FROM Vitals_Log vl 
        WHERE vl.patient_id = b.current_patient_id 
        ORDER BY vl.recorded_at DESC 
        LIMIT 1
    ) AS latest_vitals_time
FROM Beds b
INNER JOIN Wards w ON b.ward_id = w.ward_id
LEFT JOIN Patients p ON b.current_patient_id = p.patient_id
LEFT JOIN Admissions adm ON (
    adm.patient_id = p.patient_id 
    AND (adm.bed_id = b.bed_id OR adm.status = 'Admitted')
)
LEFT JOIN Staff doc ON adm.admitted_doctor_id = doc.staff_id
LEFT JOIN Discharges dis ON adm.admission_id = dis.admission_id;


CREATE OR REPLACE VIEW vw_nurse_admitted_patients AS
SELECT 
    p.patient_id,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
    p.dob,
    TIMESTAMPDIFF(YEAR, p.dob, CURDATE()) AS age,
    p.blood_group,
    p.emergency_contact,
    p.allergies,
    adm.admission_id,
    adm.admitted_at,
    adm.admission_reason,
    adm.status AS admission_status,
    w.ward_id,
    w.ward_name,
    w.nurse_in_charge_id,
    b.bed_id,
    b.bed_number,
    b.status AS bed_status,
    CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS attending_doctor,
    dis.discharge_id,
    dis.status AS discharge_status,
    dis.discharge_notes
FROM Admissions adm
INNER JOIN Patients p ON adm.patient_id = p.patient_id
INNER JOIN Wards w ON adm.ward_id = w.ward_id
LEFT JOIN Beds b ON adm.bed_id = b.bed_id
LEFT JOIN Staff doc ON adm.admitted_doctor_id = doc.staff_id
LEFT JOIN Discharges dis ON adm.admission_id = dis.admission_id
WHERE adm.status = 'Admitted';


CREATE OR REPLACE VIEW vw_patient_active_prescriptions AS
SELECT 
    rx.rx_id,
    rx.record_id,
    mr.patient_id,
    rx.med_name,
    rx.dosage,
    rx.duration,
    rx.status AS rx_status,
    CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS prescribing_doctor,
    fn_check_allergy_conflict(mr.patient_id, rx.med_name) AS has_allergy_conflict,
    p.allergies AS patient_allergies,
    (
        SELECT mar.status 
        FROM Medication_Administration_Records mar 
        WHERE mar.rx_id = rx.rx_id 
        ORDER BY mar.administered_at DESC 
        LIMIT 1
    ) AS latest_admin_status,
    (
        SELECT mar.administered_at 
        FROM Medication_Administration_Records mar 
        WHERE mar.rx_id = rx.rx_id 
        ORDER BY mar.administered_at DESC 
        LIMIT 1
    ) AS latest_admin_time
FROM Prescriptions rx
INNER JOIN Medical_Records mr ON rx.record_id = mr.record_id
INNER JOIN Patients p ON mr.patient_id = p.patient_id
LEFT JOIN Staff doc ON mr.doctor_id = doc.staff_id
WHERE rx.status = 'Active';


CREATE OR REPLACE VIEW vw_nurse_doctor_orders AS
SELECT 
    ord.order_id,
    ord.patient_id,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
    b.bed_id,
    b.bed_number,
    ord.doctor_id,
    CONCAT('Dr. ', doc.first_name, ' ', doc.last_name) AS doctor_name,
    ord.order_type,
    ord.instruction,
    ord.status,
    ord.acknowledged_by,
    CONCAT(ack_nurse.first_name, ' ', ack_nurse.last_name) AS acknowledged_by_name,
    ord.acknowledged_at,
    ord.completed_by,
    ord.completed_at,
    ord.created_at
FROM Doctor_Orders ord
INNER JOIN Patients p ON ord.patient_id = p.patient_id
LEFT JOIN Admissions adm ON (adm.patient_id = p.patient_id AND adm.status = 'Admitted')
LEFT JOIN Beds b ON adm.bed_id = b.bed_id
INNER JOIN Staff doc ON ord.doctor_id = doc.staff_id
LEFT JOIN Staff ack_nurse ON ord.acknowledged_by = ack_nurse.staff_id;

