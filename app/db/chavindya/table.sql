USE hms;

CREATE TABLE IF NOT EXISTS Admissions (
    admission_id INT AUTO_INCREMENT PRIMARY KEY,
    patient_id INT NOT NULL,
    ward_id INT NOT NULL,
    bed_id INT ,
    admitted_doctor_id INT NOT NULL,
    admitted_by INT NOT NULL,
    admitted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    admission_reason TEXT NOT NULL,
    guardian_name VARCHAR(200) NOT NULL,
    guardian_relationship VARCHAR(100) NOT NULL DEFAULT 'Guardian',
    guardian_contact VARCHAR(20) NOT NULL,
    gender ENUM('Female', 'Male') NOT NULL,
    status ENUM('Admitted', 'Pending') NOT NULL DEFAULT 'Pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES Patients(patient_id),
    FOREIGN KEY (ward_id) REFERENCES Wards(ward_id),
    FOREIGN KEY (bed_id) REFERENCES Beds(bed_id),
    FOREIGN KEY (admitted_doctor_id) REFERENCES Staff(staff_id),
    FOREIGN KEY (admitted_by) REFERENCES Users(user_id)
);

CREATE TABLE IF NOT EXISTS Discharges (
    discharge_id INT AUTO_INCREMENT PRIMARY KEY,
    admission_id INT NOT NULL UNIQUE,
    discharge_authorized_by INT NOT NULL,
    discharge_authorized_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    discharge_notes TEXT NOT NULL,
    status ENUM('Authorized', 'Discharged') NOT NULL DEFAULT 'Authorized',
    discharged_by INT NULL,
    discharged_at DATETIME NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (admission_id) REFERENCES Admissions(admission_id),
    FOREIGN KEY (discharge_authorized_by) REFERENCES Staff(staff_id),
    FOREIGN KEY (discharged_by) REFERENCES Users(user_id)
);

-- CREATE TABLE IF NOT EXISTS Bills (
--     bill_id INT AUTO_INCREMENT PRIMARY KEY,
--     admission_id INT NOT NULL UNIQUE,
--     room_charges DECIMAL(10,2) NOT NULL DEFAULT 0.00,
--     treatment_charges DECIMAL(10,2) NOT NULL DEFAULT 0.00,
--     other_charges DECIMAL(10,2) NOT NULL DEFAULT 0.00,
--     total_amount DECIMAL(10,2) NOT NULL,
--     amount_paid DECIMAL(10,2) NOT NULL DEFAULT 0.00,
--     payment_method VARCHAR(40) NULL,
--     payment_status ENUM('Unpaid', 'Partially Paid', 'Paid') NOT NULL DEFAULT 'Unpaid',
--     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--     paid_at DATETIME NULL,
--     FOREIGN KEY (admission_id) REFERENCES Admissions(admission_id)
-- );