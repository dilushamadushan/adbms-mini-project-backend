# MediCore HMS - Advanced Database Management System (ADBMS) Architecture

This technical document details the Advanced Database Management System (ADBMS) concepts, architectural design, storage structures, and procedural implementations in the **MediCore Hospital Management System (HMS)**.

---

## 1. Architectural Overview & Database Engine

The system is powered by **MySQL 8.0+** using the **InnoDB Storage Engine** for full ACID-compliant transactions, foreign key enforcement, row-level locking, and declarative partitioning.

```
       +-----------------------------------------------------------+
       |                  FastAPI Application Tier                 |
       |  (Routers -> Services -> Repositories -> Connection Pool) |
       +-----------------------------+-----------------------------+
                                     |
                         MySQL Connection Pool
                                     |
                                     v
       +-----------------------------------------------------------+
       |               MySQL 8.0+ Database Server                  |
       |  +--------------------+  +-----------------------------+  |
       |  |  Standard Tables   |  | Partitioned Tables (RANGE)  |  |
       |  |  - Users, Staff    |  | - Vitals_Log (By Year)      |  |
       |  |  - Medicines, Beds |  | - Audit_Logs (By Year)      |  |
       |  +--------------------+  +-----------------------------+  |
       |                                                           |
       |  +-----------------------------------------------------+  |
       |  | Stored Routines & Event-Driven Logic                |  |
       |  | - Stored Procedures (Transactions & Cursors)        |  |
       |  | - Deterministic / SQL Data Functions (UDFs)         |  |
       |  | - Active Database Triggers (Auditing & Alerts)      |  |
       |  | - Analytical Views (CTEs & Window Functions)        |  |
       |  | - Scheduled Events (Automated Housekeeping)         |  |
       |  +-----------------------------------------------------+  |
       +-----------------------------------------------------------+
```