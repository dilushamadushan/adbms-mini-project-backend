USE hms;


DELIMITER //

DROP PROCEDURE IF EXISTS sp_extend_vitals_schema //

CREATE PROCEDURE sp_extend_vitals_schema()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = DATABASE() AND table_name = 'Vitals_Log' AND column_name = 'spo2'
    ) THEN
        ALTER TABLE Vitals_Log ADD COLUMN spo2 INT NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = DATABASE() AND table_name = 'Vitals_Log' AND column_name = 'resp_rate'
    ) THEN
        ALTER TABLE Vitals_Log ADD COLUMN resp_rate INT NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = DATABASE() AND table_name = 'Vitals_Log' AND column_name = 'blood_sugar'
    ) THEN
        ALTER TABLE Vitals_Log ADD COLUMN blood_sugar DECIMAL(5,2) NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = DATABASE() AND table_name = 'Vitals_Log' AND column_name = 'weight'
    ) THEN
        ALTER TABLE Vitals_Log ADD COLUMN weight DECIMAL(5,2) NULL;
    END IF;
END //

DELIMITER ;

CALL sp_extend_vitals_schema();
DROP PROCEDURE IF EXISTS sp_extend_vitals_schema;


CREATE TABLE IF NOT EXISTS Medication_Administration_Records (
    mar_id INT AUTO_INCREMENT PRIMARY KEY,
    rx_id INT NOT NULL,
    patient_id INT NOT NULL,
    administered_by INT NOT NULL,
    scheduled_time VARCHAR(20) DEFAULT '08:00',
    status ENUM('Given', 'Not Given', 'Refused', 'Held') NOT NULL DEFAULT 'Given',
    reason TEXT NULL,
    notes TEXT NULL,
    administered_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (rx_id) REFERENCES Prescriptions(rx_id) ON DELETE CASCADE,
    FOREIGN KEY (patient_id) REFERENCES Patients(patient_id),
    FOREIGN KEY (administered_by) REFERENCES Staff(staff_id)
);


CREATE TABLE IF NOT EXISTS Doctor_Orders (
    order_id INT AUTO_INCREMENT PRIMARY KEY,
    patient_id INT NOT NULL,
    doctor_id INT NOT NULL,
    order_type ENUM('Medication', 'Lab', 'Diet', 'IV_Fluids', 'Nursing_Care', 'Special') NOT NULL,
    instruction TEXT NOT NULL,
    status ENUM('Pending', 'Acknowledged', 'In_Progress', 'Done') NOT NULL DEFAULT 'Pending',
    acknowledged_by INT NULL,
    acknowledged_at DATETIME NULL,
    completed_by INT NULL,
    completed_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES Patients(patient_id),
    FOREIGN KEY (doctor_id) REFERENCES Staff(staff_id),
    FOREIGN KEY (acknowledged_by) REFERENCES Staff(staff_id),
    FOREIGN KEY (completed_by) REFERENCES Staff(staff_id)
);


CREATE TABLE IF NOT EXISTS Nursing_Notes (
    note_id INT AUTO_INCREMENT PRIMARY KEY,
    patient_id INT NOT NULL,
    nurse_id INT NOT NULL,
    note_type ENUM('SOAP', 'General', 'CarePlan', 'WoundCare', 'Diet') NOT NULL DEFAULT 'SOAP',
    subjective TEXT NULL,
    objective TEXT NULL,
    assessment TEXT NULL,
    plan TEXT NULL,
    content TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES Patients(patient_id),
    FOREIGN KEY (nurse_id) REFERENCES Staff(staff_id)
);


CREATE TABLE IF NOT EXISTS Intake_Output_Logs (
    io_id INT AUTO_INCREMENT PRIMARY KEY,
    patient_id INT NOT NULL,
    recorded_by INT NOT NULL,
    io_type ENUM('Intake', 'Output') NOT NULL,
    category VARCHAR(50) NOT NULL,
    volume_ml INT NOT NULL,
    notes VARCHAR(255) NULL,
    recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES Patients(patient_id),
    FOREIGN KEY (recorded_by) REFERENCES Staff(staff_id)
);
