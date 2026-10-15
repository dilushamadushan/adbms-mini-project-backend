USE hms;

CREATE INDEX idx_tokens_expires_revoked 
ON Refresh_Tokens (expires_at, revoked);

CREATE INDEX idx_tokens_user_revoked 
ON Refresh_Tokens (user_id, revoked, expires_at);

CREATE INDEX idx_departments_hierarchy 
ON Departments (parent_dept_id, dept_name);

CREATE INDEX idx_appt_doctor_status 
ON Appointments (doctor_id, status);

CREATE INDEX idx_appt_dept_date 
ON Appointments (dept_id, apt_date);

CREATE INDEX idx_staff_dept 
ON Staff (dept_id);

CREATE INDEX idx_audit_actor_action 
ON Audit_Logs (actor_id, action_type);


