from typing import Optional, List, Dict, Any
from datetime import date
from decimal import Decimal
from mysql.connector.connection import MySQLConnection

def get_all_medicines(conn: MySQLConnection, search: Optional[str] = None, status_filter: Optional[str] = None) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        query = """
            SELECT 
                medicine_id, med_name, generic_name, unit_price, stock_qty,
                reorder_level, expiry_date, is_active, created_at, updated_at,
                DATEDIFF(expiry_date, CURDATE()) AS days_to_expiry,
                CASE 
                    WHEN stock_qty <= 0 THEN 'OUT_OF_STOCK'
                    WHEN expiry_date <= CURDATE() THEN 'EXPIRED'
                    WHEN expiry_date <= DATE_ADD(CURDATE(), INTERVAL 30 DAY) THEN 'EXPIRING_SOON'
                    WHEN stock_qty <= reorder_level THEN 'LOW_STOCK'
                    ELSE 'IN_STOCK'
                END AS stock_status,
                (unit_price * stock_qty) AS inventory_value
            FROM Medicines
            WHERE 1=1
        """
        params = []
        if search:
            query += " AND (med_name LIKE %s OR generic_name LIKE %s)"
            search_param = f"%{search}%"
            params.extend([search_param, search_param])
        
        query += " ORDER BY med_name ASC"
        cursor.execute(query, tuple(params))
        rows = cursor.fetchall()

        if status_filter:
            rows = [r for r in rows if r.get('stock_status') == status_filter]

        return rows
    finally:
        cursor.close()

def get_medicine_by_id(conn: MySQLConnection, medicine_id: int) -> Optional[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT 
                medicine_id, med_name, generic_name, unit_price, stock_qty,
                reorder_level, expiry_date, is_active, created_at, updated_at,
                DATEDIFF(expiry_date, CURDATE()) AS days_to_expiry,
                CASE 
                    WHEN stock_qty <= 0 THEN 'OUT_OF_STOCK'
                    WHEN expiry_date <= CURDATE() THEN 'EXPIRED'
                    WHEN expiry_date <= DATE_ADD(CURDATE(), INTERVAL 30 DAY) THEN 'EXPIRING_SOON'
                    WHEN stock_qty <= reorder_level THEN 'LOW_STOCK'
                    ELSE 'IN_STOCK'
                END AS stock_status,
                (unit_price * stock_qty) AS inventory_value
            FROM Medicines
            WHERE medicine_id = %s
        """, (medicine_id,))
        return cursor.fetchone()
    finally:
        cursor.close()

def add_medicine(conn: MySQLConnection, data: Dict[str, Any]) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute("""
            INSERT INTO Medicines (med_name, generic_name, unit_price, stock_qty, reorder_level, expiry_date, is_active)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """, (
            data["med_name"],
            data.get("generic_name"),
            data["unit_price"],
            data.get("stock_qty", 0),
            data.get("reorder_level", 20),
            data["expiry_date"],
            data.get("is_active", True)
        ))
        return cursor.lastrowid
    finally:
        cursor.close()

def update_medicine(conn: MySQLConnection, medicine_id: int, updates: Dict[str, Any]) -> bool:
    if not updates:
        return False
    cursor = conn.cursor()
    try:
        clauses = []
        params = []
        for key, val in updates.items():
            clauses.append(f"{key} = %s")
            params.append(val)
        params.append(medicine_id)

        sql = f"UPDATE Medicines SET {', '.join(clauses)} WHERE medicine_id = %s"
        cursor.execute(sql, tuple(params))
        return cursor.rowcount > 0
    finally:
        cursor.close()

def receive_stock(conn: MySQLConnection, medicine_id: int, quantity: int, expiry_date: date, received_by: int) -> int:
    cursor = conn.cursor()
    try:
        # Check pre-stock to detect if trigger trg_after_stock_receipt_insert handles increment
        cursor.execute("SELECT stock_qty FROM Medicines WHERE medicine_id = %s", (medicine_id,))
        med_row = cursor.fetchone()
        pre_stock = med_row[0] if med_row else 0

        # Insert into Stock_Receipts (fires trg_after_stock_receipt_insert trigger to auto-increment stock)
        cursor.execute("""
            INSERT INTO Stock_Receipts (medicine_id, quantity, expiry_date, received_by, received_at)
            VALUES (%s, %s, %s, %s, NOW())
        """, (medicine_id, quantity, expiry_date, received_by))
        receipt_id = cursor.lastrowid

        # Verify whether the trigger incremented stock; if not, apply manual fallback update
        cursor.execute("SELECT stock_qty FROM Medicines WHERE medicine_id = %s", (medicine_id,))
        post_stock_row = cursor.fetchone()
        post_stock = post_stock_row[0] if post_stock_row else pre_stock

        if post_stock == pre_stock:
            cursor.execute("""
                UPDATE Medicines
                SET stock_qty = stock_qty + %s,
                    expiry_date = %s,
                    is_active = TRUE
                WHERE medicine_id = %s
            """, (quantity, expiry_date, medicine_id))
        else:
            cursor.execute("""
                UPDATE Medicines
                SET expiry_date = %s,
                    is_active = TRUE
                WHERE medicine_id = %s
            """, (expiry_date, medicine_id))

        return receipt_id
    finally:
        cursor.close()

def get_stock_receipts_history(conn: MySQLConnection, limit: int = 50) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc("sp_get_stock_receipts_history", (limit,))
        for res in cursor.stored_results():
            return res.fetchall()
        return []
    finally:
        cursor.close()

def get_low_stock_alerts(conn: MySQLConnection) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT 
                medicine_id, med_name, generic_name, stock_qty, reorder_level,
                unit_price, expiry_date, (reorder_level - stock_qty) AS deficit_quantity
            FROM Medicines
            WHERE stock_qty <= reorder_level AND is_active = TRUE
            ORDER BY stock_qty ASC
        """)
        return cursor.fetchall()
    finally:
        cursor.close()

def get_expiring_medicines(conn: MySQLConnection, days_threshold: int = 30) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT 
                medicine_id, med_name, generic_name, stock_qty, unit_price, expiry_date,
                DATEDIFF(expiry_date, CURDATE()) AS days_left,
                CASE 
                    WHEN expiry_date <= CURDATE() THEN 'EXPIRED'
                    ELSE 'EXPIRING_SOON'
                END AS urgency_status
            FROM Medicines
            WHERE expiry_date <= DATE_ADD(CURDATE(), INTERVAL %s DAY) AND is_active = TRUE
            ORDER BY expiry_date ASC
        """, (days_threshold,))
        return cursor.fetchall()
    finally:
        cursor.close()

def get_frequently_dispensed(conn: MySQLConnection, limit: int = 10) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT 
                m.medicine_id, m.med_name, m.generic_name, m.stock_qty AS current_stock,
                COUNT(d.dispense_id) AS total_dispense_events,
                COALESCE(SUM(d.quantity), 0) AS total_units_dispensed,
                COALESCE(SUM(d.quantity * d.unit_price_at_sale), 0.00) AS total_revenue_generated
            FROM Medicines m
            LEFT JOIN Dispensations d ON m.medicine_id = d.medicine_id
            GROUP BY m.medicine_id, m.med_name, m.generic_name, m.stock_qty
            ORDER BY total_units_dispensed DESC
            LIMIT %s
        """, (limit,))
        return cursor.fetchall()
    finally:
        cursor.close()

def get_daily_dispensing_report(conn: MySQLConnection, start_date: date, end_date: date) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT 
                DATE(d.dispensed_at) AS report_date,
                COUNT(d.dispense_id) AS total_dispensations,
                COALESCE(SUM(d.quantity), 0) AS total_units,
                COALESCE(SUM(d.quantity * d.unit_price_at_sale), 0.00) AS total_revenue
            FROM Dispensations d
            WHERE DATE(d.dispensed_at) BETWEEN %s AND %s
            GROUP BY DATE(d.dispensed_at)
            ORDER BY report_date DESC
        """, (start_date, end_date))
        return cursor.fetchall()
    finally:
        cursor.close()

def get_dashboard_kpis(conn: MySQLConnection) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT 
                (SELECT COUNT(*) FROM Medicines WHERE is_active = TRUE) AS total_medicines,
                (SELECT COALESCE(SUM(stock_qty), 0) FROM Medicines WHERE is_active = TRUE) AS total_stock_units,
                (SELECT COUNT(*) FROM Medicines WHERE stock_qty <= reorder_level AND is_active = TRUE) AS low_stock_count,
                (SELECT COUNT(*) FROM Medicines WHERE expiry_date <= CURDATE() AND is_active = TRUE) AS expired_count,
                (SELECT COUNT(*) FROM Medicines WHERE expiry_date > CURDATE() AND expiry_date <= DATE_ADD(CURDATE(), INTERVAL 30 DAY) AND is_active = TRUE) AS expiring_soon_count,
                (SELECT COALESCE(SUM(unit_price * stock_qty), 0.00) FROM Medicines WHERE is_active = TRUE) AS total_inventory_valuation,
                (SELECT COALESCE(SUM(quantity), 0) FROM Dispensations WHERE DATE(dispensed_at) = CURDATE()) AS today_units_dispensed,
                (SELECT COALESCE(SUM(quantity * unit_price_at_sale), 0.00) FROM Dispensations WHERE DATE(dispensed_at) = CURDATE()) AS today_revenue
        """)
        row = cursor.fetchone()
        return row or {
            "total_medicines": 0, "total_stock_units": 0, "low_stock_count": 0,
            "expired_count": 0, "expiring_soon_count": 0, "total_inventory_valuation": Decimal("0.00"),
            "today_units_dispensed": 0, "today_revenue": Decimal("0.00")
        }
    finally:
        cursor.close()

def create_purchase_order(
    conn: MySQLConnection,
    pharmacist_id: int,
    supplier_name: str,
    expected_delivery_date: date,
    notes: Optional[str],
    items: List[Dict[str, Any]]
) -> int:
    cursor = conn.cursor(dictionary=True)
    try:
        # Validate lead time: minimum 1 day in advance
        from datetime import timedelta
        if expected_delivery_date < date.today() + timedelta(days=1):
            raise ValueError("Restock lead time must be at least 1 day in advance.")

        # Calculate totals
        total_cost = Decimal("0.00")
        processed_items = []
        for it in items:
            med_id = it["medicine_id"]
            qty = it["requested_quantity"]
            cursor.execute("SELECT med_name, unit_price FROM Medicines WHERE medicine_id = %s", (med_id,))
            med = cursor.fetchone()
            if not med:
                raise ValueError(f"Medicine ID {med_id} not found.")
            price = Decimal(str(med["unit_price"]))
            subtotal = price * qty
            total_cost += subtotal
            processed_items.append({
                "medicine_id": med_id,
                "requested_quantity": qty,
                "unit_price": price,
                "subtotal": subtotal
            })

        # Generate order number
        cursor.execute("SELECT COUNT(*) AS cnt FROM Purchase_Orders")
        cnt = cursor.fetchone()["cnt"] + 1
        order_number = f"PO-{date.today().strftime('%Y%m%d')}-{cnt:04d}"

        # Insert Order Header
        cursor.execute("""
            INSERT INTO Purchase_Orders (
                order_number, pharmacist_id, supplier_name, expected_delivery_date, total_cost, status, notes
            ) VALUES (%s, %s, %s, %s, %s, 'PENDING_APPROVAL', %s)
        """, (order_number, pharmacist_id, supplier_name, expected_delivery_date, total_cost, notes))
        order_id = cursor.lastrowid

        # Insert Order Items
        for it in processed_items:
            cursor.execute("""
                INSERT INTO Purchase_Order_Items (
                    order_id, medicine_id, requested_quantity, unit_price, subtotal
                ) VALUES (%s, %s, %s, %s, %s)
            """, (order_id, it["medicine_id"], it["requested_quantity"], it["unit_price"], it["subtotal"]))

        return order_id
    finally:
        cursor.close()

def get_purchase_orders(conn: MySQLConnection) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT 
                po.order_id,
                po.order_number,
                po.supplier_name,
                po.order_date,
                po.expected_delivery_date,
                DATEDIFF(po.expected_delivery_date, DATE(po.order_date)) AS lead_time_days,
                po.total_cost,
                po.status,
                po.notes,
                po.pharmacist_id,
                CONCAT(s.first_name, ' ', s.last_name) AS pharmacist_name,
                COUNT(poi.item_id) AS total_items
            FROM Purchase_Orders po
            LEFT JOIN Staff s ON po.pharmacist_id = s.staff_id
            LEFT JOIN Purchase_Order_Items poi ON po.order_id = poi.order_id
            GROUP BY po.order_id, po.order_number, po.supplier_name, po.order_date, 
                     po.expected_delivery_date, po.total_cost, po.status, po.notes, 
                     po.pharmacist_id, s.first_name, s.last_name
            ORDER BY po.order_date DESC
        """)
        orders = cursor.fetchall()
        for order in orders:
            cursor.execute("""
                SELECT 
                    poi.item_id,
                    poi.medicine_id,
                    m.med_name,
                    m.generic_name,
                    poi.requested_quantity,
                    poi.unit_price,
                    poi.subtotal
                FROM Purchase_Order_Items poi
                JOIN Medicines m ON poi.medicine_id = m.medicine_id
                WHERE poi.order_id = %s
                ORDER BY poi.item_id ASC
            """, (order["order_id"],))
            order["items"] = cursor.fetchall()
        return orders
    finally:
        cursor.close()

def get_purchase_order_by_id(conn: MySQLConnection, order_id: int) -> Optional[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("""
            SELECT 
                po.order_id,
                po.order_number,
                po.supplier_name,
                po.order_date,
                po.expected_delivery_date,
                DATEDIFF(po.expected_delivery_date, DATE(po.order_date)) AS lead_time_days,
                po.total_cost,
                po.status,
                po.notes,
                po.pharmacist_id,
                CONCAT(s.first_name, ' ', s.last_name) AS pharmacist_name
            FROM Purchase_Orders po
            LEFT JOIN Staff s ON po.pharmacist_id = s.staff_id
            WHERE po.order_id = %s
        """, (order_id,))
        order = cursor.fetchone()
        if not order:
            return None

        cursor.execute("""
            SELECT 
                poi.item_id,
                poi.medicine_id,
                m.med_name,
                m.generic_name,
                poi.requested_quantity,
                poi.unit_price,
                poi.subtotal
            FROM Purchase_Order_Items poi
            JOIN Medicines m ON poi.medicine_id = m.medicine_id
            WHERE poi.order_id = %s
            ORDER BY poi.item_id ASC
        """, (order_id,))
        order["items"] = cursor.fetchall()
        order["total_items"] = len(order["items"])
        return order
    finally:
        cursor.close()

def update_purchase_order_status(conn: MySQLConnection, order_id: int, status: str) -> bool:
    cursor = conn.cursor()
    try:
        cursor.callproc("sp_update_purchase_order_status", (order_id, status))
        return True
    finally:
        cursor.close()

def restock_delivered_order(conn: MySQLConnection, order_id: int, staff_id: int, expiry_date: Optional[date] = None) -> bool:
    cursor = conn.cursor()
    try:
        cursor.callproc("sp_receive_and_restock_purchase_order", (order_id, staff_id, expiry_date))
        return True
    finally:
        cursor.close()

# ---------------------------------------------------------------------------
# Prescriptions & Live Dispensing Queue Repositories
# ---------------------------------------------------------------------------
def get_prescriptions_queue(conn: MySQLConnection, status_filter: str = "PENDING") -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        query = """
            SELECT 
                p.rx_id,
                p.record_id,
                p.med_name,
                p.dosage,
                p.duration,
                p.created_at AS prescribed_at,
                mr.patient_id,
                CONCAT(pt.first_name, ' ', pt.last_name) AS patient_name,
                pt.allergies,
                CONCAT(doc.first_name, ' ', doc.last_name) AS doctor_name,
                m.medicine_id,
                m.med_name AS inventory_med_name,
                m.stock_qty,
                m.unit_price,
                d.dispense_id,
                IF(d.dispense_id IS NOT NULL, TRUE, FALSE) AS is_dispensed
            FROM Prescriptions p
            JOIN Medical_Records mr ON p.record_id = mr.record_id
            JOIN Patients pt ON mr.patient_id = pt.patient_id
            JOIN Staff doc ON mr.doctor_id = doc.staff_id
            LEFT JOIN Dispensations d ON p.rx_id = d.rx_id
            LEFT JOIN Medicines m ON (
                LOWER(m.med_name) LIKE CONCAT('%', LOWER(p.med_name), '%') 
                OR LOWER(p.med_name) LIKE CONCAT('%', LOWER(m.med_name), '%')
            )
        """
        if status_filter == "PENDING":
            query += " WHERE d.dispense_id IS NULL"
        elif status_filter == "DISPENSED":
            query += " WHERE d.dispense_id IS NOT NULL"
        
        query += " ORDER BY p.created_at DESC"
        cursor.execute(query)
        rows = cursor.fetchall()
        
        # Deduplicate rows by rx_id if LIKE match matched multiple medicines
        seen = set()
        deduped = []
        for r in rows:
            if r['rx_id'] not in seen:
                seen.add(r['rx_id'])
                deduped.append(r)
        return deduped
    finally:
        cursor.close()

def record_dispensation(
    conn: MySQLConnection,
    rx_id: int,
    medicine_id: int,
    quantity: int,
    pharmacist_id: int = 5,
    admission_id: Optional[int] = None
) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        # 1. Check if already dispensed
        cursor.execute("SELECT dispense_id FROM Dispensations WHERE rx_id = %s", (rx_id,))
        if cursor.fetchone():
            raise ValueError(f"Prescription #{rx_id} has already been dispensed.")

        # 2. Get medicine details & current price
        cursor.execute("SELECT med_name, unit_price, stock_qty FROM Medicines WHERE medicine_id = %s", (medicine_id,))
        med = cursor.fetchone()
        if not med:
            raise ValueError(f"Medicine #{medicine_id} not found in inventory.")
        if med["stock_qty"] < quantity:
            raise ValueError(f"Insufficient stock for '{med['med_name']}'. In stock: {med['stock_qty']}, requested: {quantity}")

        unit_price = med["unit_price"]

        # 3. Insert into Dispensations (triggers trg_after_dispensation_insert will auto-decrement Medicines.stock_qty!)
        insert_query = """
            INSERT INTO Dispensations (
                rx_id, medicine_id, pharmacist_id, admission_id, quantity, unit_price_at_sale, dispensed_at
            ) VALUES (%s, %s, %s, %s, %s, %s, NOW())
        """
        cursor.execute(insert_query, (rx_id, medicine_id, pharmacist_id, admission_id, quantity, unit_price))
        dispense_id = cursor.lastrowid

        # 4. Fetch updated remaining stock & timestamp
        cursor.execute("SELECT stock_qty FROM Medicines WHERE medicine_id = %s", (medicine_id,))
        updated_stock = cursor.fetchone()["stock_qty"]
        cursor.execute("SELECT dispensed_at FROM Dispensations WHERE dispense_id = %s", (dispense_id,))
        dispensed_time = cursor.fetchone()["dispensed_at"]

        return {
            "success": True,
            "message": f"Successfully dispensed {quantity} units. Inventory deducted automatically.",
            "dispense_id": dispense_id,
            "rx_id": rx_id,
            "medicine_id": medicine_id,
            "quantity": quantity,
            "unit_price": unit_price,
            "total_price": unit_price * quantity,
            "remaining_stock": updated_stock,
            "dispensed_at": dispensed_time
        }
    finally:
        cursor.close()

def get_dispensations_history(conn: MySQLConnection, limit: int = 50) -> List[Dict[str, Any]]:
    cursor = conn.cursor(dictionary=True)
    try:
        query = """
            SELECT 
                d.dispense_id,
                d.rx_id,
                CONCAT(pt.first_name, ' ', pt.last_name) AS patient_name,
                CONCAT(doc.first_name, ' ', doc.last_name) AS doctor_name,
                m.med_name,
                d.quantity,
                d.unit_price_at_sale,
                (d.quantity * d.unit_price_at_sale) AS total_revenue,
                d.dispensed_at,
                COALESCE(CONCAT(pharm.first_name, ' ', pharm.last_name), 'Alex Taylor') AS pharmacist_name
            FROM Dispensations d
            JOIN Prescriptions p ON d.rx_id = p.rx_id
            JOIN Medical_Records mr ON p.record_id = mr.record_id
            JOIN Patients pt ON mr.patient_id = pt.patient_id
            JOIN Staff doc ON mr.doctor_id = doc.staff_id
            JOIN Medicines m ON d.medicine_id = m.medicine_id
            LEFT JOIN Staff pharm ON d.pharmacist_id = pharm.staff_id
            ORDER BY d.dispensed_at DESC
            LIMIT %s
        """
        cursor.execute(query, (limit,))
        return cursor.fetchall()
    finally:
        cursor.close()

def save_doctor_prescription(conn: MySQLConnection, appointment_id: int, medications: List[Dict[str, Any]]) -> Dict[str, Any]:
    cursor = conn.cursor(dictionary=True)
    try:
        # 1. Lookup appointment
        cursor.execute("""
            SELECT apt_id, patient_id, doctor_id 
            FROM Appointments 
            WHERE apt_id = %s
        """, (appointment_id,))
        apt = cursor.fetchone()
        if not apt:
            patient_id = 1
            doctor_id = 1
            apt_id = None
        else:
            patient_id = apt["patient_id"]
            doctor_id = apt["doctor_id"]
            apt_id = apt["apt_id"]

        # 2. Lookup or create Medical_Record
        cursor.execute("""
            SELECT record_id FROM Medical_Records 
            WHERE patient_id = %s AND doctor_id = %s 
            ORDER BY created_at DESC LIMIT 1
        """, (patient_id, doctor_id))
        rec = cursor.fetchone()
        if rec:
            record_id = rec["record_id"]
        else:
            cursor.execute("""
                INSERT INTO Medical_Records (patient_id, doctor_id, apt_id, diagnosis, notes, created_at)
                VALUES (%s, %s, %s, 'Clinical Consultation', 'Prescription dispatched to pharmacy', NOW())
            """, (patient_id, doctor_id, apt_id))
            record_id = cursor.lastrowid

        # 3. Insert each medication into Prescriptions
        rx_ids = []
        for m in medications:
            med_name = m.get("medicine") or "Medication"
            dosage = f"{m.get('dose', '')} {m.get('frequency', '')}".strip() or "Standard Dose"
            duration = m.get("duration") or "7 Days"
            cursor.execute("""
                INSERT INTO Prescriptions (record_id, med_name, dosage, duration, status, created_at)
                VALUES (%s, %s, %s, %s, 'Active', NOW())
            """, (record_id, med_name, dosage, duration))
            rx_ids.append(cursor.lastrowid)

        # 4. Insert notification for Pharmacists
        cursor.execute("""
            INSERT INTO Notifications (title, message, type, target_role, created_at)
            VALUES (
                'New Doctor Prescription',
                CONCAT('New prescription sent for patient #', %s, ' with ', %s, ' item(s).'),
                'PRESCRIPTION',
                'pharmacist',
                NOW()
            )
        """, (patient_id, len(medications)))

        return {
            "success": True,
            "message": f"Successfully sent {len(medications)} prescribed medication(s) to pharmacy.",
            "record_id": record_id,
            "rx_ids": rx_ids
        }
    finally:
        cursor.close()


