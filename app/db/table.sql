CREATE DATABASE IF NOT EXISTS hms;

USE hms;

CREATE TABLE IF NOT EXISTS Users (
    user_id       INT AUTO_INCREMENT PRIMARY KEY,
    username      VARCHAR(100) NOT NULL UNIQUE,
    email         VARCHAR(255) NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role          ENUM('doctor', 'nurse', 'receptionist', 'patient', 'admin', 'pharmacist') DEFAULT 'patient',
    is_active     BOOLEAN DEFAULT TRUE,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS Departments (
    dept_id        INT AUTO_INCREMENT PRIMARY KEY,
    dept_name      VARCHAR(100) NOT NULL,
    parent_dept_id INT NULL,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (parent_dept_id) REFERENCES Departments(dept_id)
);

CREATE TABLE IF NOT EXISTS Staff (
    staff_id   INT AUTO_INCREMENT PRIMARY KEY,
    user_id    INT UNIQUE,
    dept_id    INT,
    first_name VARCHAR(100) NOT NULL,
    last_name  VARCHAR(100) NOT NULL,
    specialty  VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Users(user_id),
    FOREIGN KEY (dept_id) REFERENCES Departments(dept_id)
);

CREATE TABLE IF NOT EXISTS Patients (
    patient_id        INT AUTO_INCREMENT PRIMARY KEY,
    user_id           INT UNIQUE,
    first_name        VARCHAR(100) NOT NULL,
    last_name         VARCHAR(100) NOT NULL,
    dob               DATE,
    blood_group       VARCHAR(10),
    emergency_contact VARCHAR(20),
    allergies         TEXT,
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Users(user_id)
);

CREATE TABLE IF NOT EXISTS Appointments (
    apt_id     INT AUTO_INCREMENT PRIMARY KEY,
    patient_id INT NOT NULL,
    doctor_id  INT NOT NULL,
    dept_id    INT NOT NULL,
    apt_date   DATE NOT NULL,
    time_slot  TIME NOT NULL,
    status     ENUM('Scheduled', 'Completed', 'Cancelled', 'No-Show') DEFAULT 'Scheduled',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES Patients(patient_id),
    FOREIGN KEY (doctor_id)  REFERENCES Staff(staff_id),
    FOREIGN KEY (dept_id)    REFERENCES Departments(dept_id)
);

CREATE TABLE IF NOT EXISTS Medical_Records (
    record_id      INT AUTO_INCREMENT PRIMARY KEY,
    patient_id     INT NOT NULL,
    doctor_id      INT NOT NULL,
    apt_id         INT,
    diagnosis      TEXT,
    clinical_notes TEXT,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES Patients(patient_id),
    FOREIGN KEY (doctor_id)  REFERENCES Staff(staff_id),
    FOREIGN KEY (apt_id)     REFERENCES Appointments(apt_id)
);

CREATE TABLE IF NOT EXISTS Prescriptions (
    rx_id      INT AUTO_INCREMENT PRIMARY KEY,
    record_id  INT NOT NULL,
    med_name   VARCHAR(100) NOT NULL,
    dosage     VARCHAR(100) NOT NULL,
    duration   VARCHAR(50),
    status     ENUM('Active', 'Inactive') DEFAULT 'Active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (record_id) REFERENCES Medical_Records(record_id)
);

CREATE TABLE IF NOT EXISTS Lab_Orders (
    lab_id       INT AUTO_INCREMENT PRIMARY KEY,
    patient_id   INT NOT NULL,
    doctor_id    INT NOT NULL,
    test_type    VARCHAR(100) NOT NULL,
    status       ENUM('Pending', 'Completed') DEFAULT 'Pending',
    results_text TEXT,
    ordered_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES Patients(patient_id),
    FOREIGN KEY (doctor_id)  REFERENCES Staff(staff_id)
);

CREATE TABLE IF NOT EXISTS Wards (
    ward_id              INT AUTO_INCREMENT PRIMARY KEY,
    ward_name            VARCHAR(100) NOT NULL,
    total_beds           INT NOT NULL,
    nurse_in_charge_id   INT,
    created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (nurse_in_charge_id) REFERENCES Staff(staff_id)
);

CREATE TABLE IF NOT EXISTS Beds (
    bed_id             INT AUTO_INCREMENT PRIMARY KEY,
    ward_id            INT NOT NULL,
    bed_number         VARCHAR(20) NOT NULL,
    status             ENUM('Available', 'Occupied', 'Cleaning') DEFAULT 'Available',
    current_patient_id INT,
    updated_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (ward_id)            REFERENCES Wards(ward_id),
    FOREIGN KEY (current_patient_id) REFERENCES Patients(patient_id)
);

CREATE TABLE IF NOT EXISTS Vitals_Log (
    vital_id    INT AUTO_INCREMENT,
    patient_id  INT NOT NULL,
    recorded_by INT NOT NULL,
    bp          VARCHAR(20),
    pulse       INT,
    temperature DECIMAL(5,2),
    recorded_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (vital_id, recorded_at),
    INDEX idx_vitals_patient (patient_id),
    INDEX idx_vitals_staff (recorded_by)
) PARTITION BY RANGE (YEAR(recorded_at)) (
    PARTITION p0 VALUES LESS THAN (2025),
    PARTITION p1 VALUES LESS THAN (2026),
    PARTITION p2 VALUES LESS THAN (2027),
    PARTITION p3 VALUES LESS THAN MAXVALUE
);

CREATE TABLE IF NOT EXISTS Audit_Logs (
    log_id         INT AUTO_INCREMENT,
    actor_id       INT,
    action_type    VARCHAR(50),
    resource_table VARCHAR(50),
    details        JSON,
    timestamp      DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (log_id, timestamp)
) PARTITION BY RANGE (YEAR(timestamp)) (
    PARTITION p0 VALUES LESS THAN (2025),
    PARTITION p1 VALUES LESS THAN (2026),
    PARTITION p2 VALUES LESS THAN (2027),
    PARTITION p3 VALUES LESS THAN MAXVALUE
);

CREATE TABLE IF NOT EXISTS Refresh_Tokens (
    token_id     INT AUTO_INCREMENT PRIMARY KEY,
    user_id      INT NOT NULL,
    token_hash   VARCHAR(255) NOT NULL UNIQUE,
    expires_at   DATETIME NOT NULL,
    revoked      BOOLEAN DEFAULT FALSE,
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS Password_Reset_OTPs (
    otp_id       INT AUTO_INCREMENT PRIMARY KEY,
    user_id      INT NOT NULL,
    email        VARCHAR(255) NOT NULL,
    otp_code     VARCHAR(10) NOT NULL,
    expires_at   DATETIME NOT NULL,
    is_used      BOOLEAN DEFAULT FALSE,
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
    INDEX idx_user_otp (email, otp_code, is_used, expires_at)
);

CREATE TABLE IF NOT EXISTS Notifications (
    notification_id INT AUTO_INCREMENT PRIMARY KEY,
    title           VARCHAR(255) NOT NULL,
    message         TEXT NOT NULL,
    type            VARCHAR(50) DEFAULT 'INFO',
    target_role     VARCHAR(50) DEFAULT 'admin',
    target_user_id  INT NULL,
    is_read         BOOLEAN DEFAULT FALSE,
    details         JSON NULL,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_notifications_role (target_role, is_read, created_at),
    INDEX idx_notifications_user (target_user_id, is_read),
    FOREIGN KEY (target_user_id) REFERENCES Users(user_id) ON DELETE CASCADE
);

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

CREATE TABLE IF NOT EXISTS Medicines (
    medicine_id    INT AUTO_INCREMENT PRIMARY KEY,
    med_name       VARCHAR(100) NOT NULL UNIQUE,
    generic_name   VARCHAR(100) NULL,
    unit_price     DECIMAL(10,2) NOT NULL COMMENT 'Unit price in Rupees (Rs.)',
    stock_qty      INT NOT NULL DEFAULT 0,
    reorder_level  INT NOT NULL DEFAULT 20,
    expiry_date    DATE NULL,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_med_stock_nonneg   CHECK (stock_qty >= 0),
    CONSTRAINT chk_med_price_positive CHECK (unit_price > 0),
    CONSTRAINT chk_med_reorder_nonneg CHECK (reorder_level >= 0)
);
 
CREATE TABLE IF NOT EXISTS Stock_Receipts (
    receipt_id   INT AUTO_INCREMENT PRIMARY KEY,
    medicine_id  INT NOT NULL,
    quantity     INT NOT NULL,
    expiry_date  DATE NOT NULL,
    received_by  INT NOT NULL,
    received_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_receipt_qty_positive CHECK (quantity > 0),
    FOREIGN KEY (medicine_id) REFERENCES Medicines(medicine_id),
    FOREIGN KEY (received_by) REFERENCES Staff(staff_id)
);
 
CREATE TABLE IF NOT EXISTS Dispensations (
    dispense_id        INT AUTO_INCREMENT PRIMARY KEY,
    rx_id              INT NOT NULL,
    medicine_id        INT NOT NULL,
    pharmacist_id      INT NOT NULL,
    admission_id       INT NULL,
    quantity           INT NOT NULL,
    unit_price_at_sale DECIMAL(10,2) NOT NULL COMMENT 'Sale unit price in Rupees (Rs.)',
    dispensed_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_disp_qty_positive CHECK (quantity > 0),
    UNIQUE KEY uq_one_dispense_per_rx (rx_id),
    FOREIGN KEY (rx_id)         REFERENCES Prescriptions(rx_id),
    FOREIGN KEY (medicine_id)   REFERENCES Medicines(medicine_id),
    FOREIGN KEY (pharmacist_id) REFERENCES Staff(staff_id),
    FOREIGN KEY (admission_id)  REFERENCES Admissions(admission_id)
);

CREATE TABLE IF NOT EXISTS Purchase_Orders (
    order_id               INT AUTO_INCREMENT PRIMARY KEY,
    order_number           VARCHAR(50) NOT NULL UNIQUE,
    pharmacist_id          INT NOT NULL,
    supplier_name          VARCHAR(150) NOT NULL DEFAULT 'State Pharmaceuticals Corporation',
    order_date             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expected_delivery_date DATE NOT NULL,
    total_cost             DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    status                 ENUM('PENDING_APPROVAL', 'APPROVED', 'ORDERED', 'RECEIVED', 'CANCELLED') NOT NULL DEFAULT 'PENDING_APPROVAL',
    notes                  TEXT NULL,
    created_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (pharmacist_id) REFERENCES Staff(staff_id)
);

CREATE TABLE IF NOT EXISTS Purchase_Order_Items (
    item_id            INT AUTO_INCREMENT PRIMARY KEY,
    order_id           INT NOT NULL,
    medicine_id        INT NOT NULL,
    requested_quantity INT NOT NULL,
    unit_price         DECIMAL(10,2) NOT NULL,
    subtotal           DECIMAL(10,2) NOT NULL,
    CONSTRAINT chk_po_qty_positive CHECK (requested_quantity > 0),
    FOREIGN KEY (order_id) REFERENCES Purchase_Orders(order_id) ON DELETE CASCADE,
    FOREIGN KEY (medicine_id) REFERENCES Medicines(medicine_id)
);

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

ALTER TABLE `admissions`
  MODIFY COLUMN `status` ENUM('Admitted', 'Pending', 'Discharged') NOT NULL DEFAULT 'Pending';

ALTER TABLE `discharges` ADD UNIQUE KEY `uq_discharge_admission` (`admission_id`);

