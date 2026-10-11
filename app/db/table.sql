CREATE DATABASE IF NOT EXISTS hms;

USE hms;

CREATE TABLE IF NOT EXISTS Users (
    user_id       INT AUTO_INCREMENT PRIMARY KEY,
    username      VARCHAR(100) NOT NULL UNIQUE,
    email         VARCHAR(255) NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role          ENUM('doctor', 'nurse', 'receptionist', 'patient', 'admin') DEFAULT 'patient',
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
