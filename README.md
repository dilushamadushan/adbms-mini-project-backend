# MediCore HMS - Advanced Database Management System (ADBMS) Backend

![FastAPI](https://img.shields.io/badge/FastAPI-0.115.0-009688?style=for-the-badge&logo=fastapi&logoColor=white)
![MySQL](https://img.shields.io/badge/MySQL-8.0+-4479A1?style=for-the-badge&logo=mysql&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.10+-3776AB?style=for-the-badge&logo=python&logoColor=white)
![JWT](https://img.shields.io/badge/JWT-Authentication-black?style=for-the-badge&logo=JSON%20web%20tokens)
![License](https://img.shields.io/badge/Course-ADBMS_Mini_Project-blue?style=for-the-badge)

**MediCore HMS** is an enterprise-grade Hospital Management System backend built with **FastAPI** and **MySQL 8.0+**. Designed as an Advanced Database Management System (ADBMS) project, this platform demonstrates the practical application of enterprise database engineering concepts including **Horizontal Table Partitioning**, **ACID-Compliant Stored Procedures with Cursors**, **Deterministic Stored Functions**, **Event-Driven Triggers**, **Analytical Views with Window Functions**, **Full-Text & Composite Indexing**, and **Automated Database Events**.

## 1. Project Structure

```
adbms-mini-project-backend/
├── app/
│   ├── core/                  # Core infrastructure
│   │   ├── database.py        # MySQL Connection Pool & session context manager
│   │   ├── security.py        # Bcrypt password hashing & JWT token issuance/verification
│   │   ├── email.py           # SMTP mailer for OTP delivery
│   │   └── middleware.py      # CORS configuration & global exception handlers
│   ├── db/                    # SQL Database scripts (ADBMS Artifacts)
│   │   ├── schema.sql         # Unified complete database script
│   │   ├── table.sql          # Table DDL & Partitioning schemas
│   │   ├── procedure.sql      # Stored procedures
│   │   ├── function.sql       # User-defined functions (UDFs)
│   │   ├── trigger.sql        # Active database triggers
│   │   ├── view.sql           # Analytical & operational views
│   │   ├── index.sql          # Composite & Full-Text performance indexes
│   │   ├── event.sql          # MySQL scheduled background events
│   │   ├── data.sql           # Seed datasets & realistic clinical catalogs
│   │   └── [subfolders]/      # Team member specialized module scripts
│   ├── repositories/          # Data Access Object (DAO) layer
│   │   ├── Docter/            # Doctor repository
│   │   ├── Nurse/             # Nurse repository
│   │   ├── Patient/           # Patient repository
│   │   ├── appointment_repo.py
│   │   ├── audit_repo.py
│   │   ├── auth_repo.py
│   │   ├── department_repo.py
│   │   ├── pharmacy_repo.py
│   │   ├── recep_repo.py
│   │   ├── report_repo.py
│   │   └── user_repo.py
│   ├── services/              # Business logic orchestration
│   ├── routers/               # FastAPI route definitions (REST controllers)
│   ├── schema/                # Pydantic v2 validation models
│   └── templates/             # HTML email templates
├── docs/                      # Technical documentation
│   ├── DATABASE_ARCHITECTURE.md # Exhaustive ADBMS technical report
│   └── API_DOCUMENTATION.md     # Full REST API endpoint reference
├── main.py                    # Application entrypoint
├── requirements.txt           # Python dependencies
├── CONTRIBUTING.md            # Contribution guidelines & coding conventions
├── README.md                  # Project overview & documentation
└── .env                       # Environment configuration
```

---

## 2. Installation & Setup Guide

### 2.1 Prerequisites
* **Python**: 3.10 or higher
* **MySQL Server**: 8.0 or higher
* **Git**

### 2.2 Environment Setup
1. Clone the repository and navigate into the root directory:
   ```bash
   git clone https://github.com/dilushamadushan/adbms-mini-project-backend.git
   cd adbms-mini-project-backend
   ```

2. Create and activate a Python virtual environment:
   ```bash
   python -m venv venv

   # On Windows (PowerShell):
   .\venv\Scripts\Activate.ps1

   # On Linux/macOS:
   source venv/bin/activate
   ```

3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

4. Configure your `.env` file:
   Create or edit `.env` in the root directory:
   ```ini
   DB_HOST=localhost
   DB_PORT=3306
   DB_USER=root
   DB_PASSWORD=your_mysql_password
   DB_NAME=hms

   JWT_SECRET_KEY=your_super_secret_jwt_key_here
   JWT_ALGORITHM=HS256
   ACCESS_TOKEN_EXPIRE_MINUTES=30
   REFRESH_TOKEN_EXPIRE_DAYS=7

   SMTP_HOST=smtp.gmail.com
   SMTP_PORT=587
   SMTP_USER=your_email@gmail.com
   SMTP_PASSWORD=your_app_password
   SMTP_TLS=True
   EMAILS_FROM_EMAIL=your_email@gmail.com
   EMAILS_FROM_NAME=MediCore HMS
   ```

### 2.3 Database Initialization
Execute the unified database script in MySQL to create the database, tables, partitions, functions, views, procedures, triggers, events, and seed data:

### 2.4 Running the Application
Start the development server with hot-reload enabled:

```bash
uvicorn main.py:app --reload --host 0.0.0.0 --port 8000
```

Verify application health:
* **Health Check**: [http://localhost:8000/health](http://localhost:8000/health)
* **Swagger Interactive Docs**: [http://localhost:8000/docs](http://localhost:8000/docs)
* **ReDoc Reference**: [http://localhost:8000/redoc](http://localhost:8000/redoc)

## 4. Documentation & Contribution

* Detailed ADBMS Technical Architecture: [docs/DATABASE_ARCHITECTURE.md](docs/DATABASE_ARCHITECTURE.md)
* Team Contribution & Coding Standards: [CONTRIBUTING.md](CONTRIBUTING.md)

## License

This project is developed for academic evaluation in the **Advanced Database Management Systems (ADBMS)** course. All rights reserved.
