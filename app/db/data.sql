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
