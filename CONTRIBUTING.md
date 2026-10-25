# Contributing to MediCore HMS (ADBMS Project)

Thank you for contributing to the **MediCore Hospital Management System (HMS)** Advanced Database Management System project!

This document sets out the team standards, database workflows, branching conventions, and coding patterns required for all contributions.

## 1. Database Contribution Guidelines

Because this project focuses on **Advanced Database Concepts**, database scripts are primary project artifacts.

1. **Idempotence**: Always use `DROP PROCEDURE IF EXISTS`, `DROP FUNCTION IF EXISTS`, `DROP TRIGGER IF EXISTS`, `DROP EVENT IF EXISTS`, or `CREATE OR REPLACE VIEW` prior to creation.
2. **DELIMITER Syntax**: Always encapsulate multi-statement blocks with `DELIMITER //` and restore with `DELIMITER ;`.
3. **Function Determinism**: Explicitly declare `DETERMINISTIC`, `READS SQL DATA`, `NO SQL`, or `CONTAINS SQL` for all stored functions.
4. **Error Signaling**: Use ANSI SQLSTATE `45000` with user-friendly messages for validation failures:
   ```sql
   IF v_patient_id IS NULL THEN
       SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Patient record not found.';
   END IF;
   ```
5. **ACID Transactions**: For stored procedures that perform multi-table mutations, wrap the sequence in `START TRANSACTION;` and `COMMIT;`.
6. **Unified Script Sync**: Whenever you add or alter an SQL routine in your personal subfolder (`app/db/<member>/`), ensure the corresponding root files (`table.sql`, `procedure.sql`, etc.) or unified schema script are synchronized.

## 2. Backend Application Standards (Python / FastAPI)

### 2.1 3-Tier Layered Architecture
All backend logic must follow the established layered separation of concerns:

```
[ Router Layer (app/routers/) ]
         │  Receives HTTP request, validates Pydantic schema, enforces JWT role dependencies
         ▼
[ Service Layer (app/services/) ]
         │  Orchestrates business logic, parses payloads, prepares data structures
         ▼
[ Repository Layer (app/repositories/) ]
         │  Acquires connection from MySQL pool, executes SQL / CALLs Stored Procedures
         ▼
[ Database (MySQL 8.0+) ]
```

### 2.2 Database Queries & Connections
* Always obtain connections via the context manager:
  ```python
  from app.core.database import get_db_connection

  with get_db_connection() as conn:
      with conn.cursor(dictionary=True) as cursor:
          cursor.callproc("sp_my_procedure", (param1, param2))
          # fetch results...
  ```
* Never hardcode database credentials in source code. All configuration must be loaded from `.env` via `python-dotenv`.
* Never perform raw string concatenation in SQL queries to prevent SQL injection vulnerabilities. Always use parameterized queries or stored procedure parameters.

## 3. Testing & Verification Checklist

Before opening a Pull Request:
1. Ensure the MySQL server is running and the database connection succeeds (`GET /health` returns `{"status": "ok", "database": "healthy"}`).
2. Verify all new endpoints appear and test successfully in Swagger UI at `http://localhost:8000/docs`.
3. Confirm that error cases (e.g. invalid inputs, unauthorized role access, foreign key violations) return appropriate HTTP status codes (`400`, `401`, `403`, `404`, `422`).
4. Ensure no uncommitted scratch scripts or temporary files are included in the commit.
