USE hms;

CREATE INDEX idx_patients_first_name ON Patients (first_name);
CREATE INDEX idx_patients_last_name ON Patients (last_name);