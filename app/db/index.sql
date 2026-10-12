USE hms;

CREATE INDEX idx_tokens_expires_revoked 
ON Refresh_Tokens (expires_at, revoked);

CREATE INDEX idx_tokens_user_revoked 
ON Refresh_Tokens (user_id, revoked, expires_at);

CREATE INDEX idx_departments_hierarchy 
ON Departments (parent_dept_id, dept_name);


