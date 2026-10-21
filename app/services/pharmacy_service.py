from typing import Optional, List, Dict, Any
from datetime import date
from fastapi import HTTPException, status
from app.core.database import get_db
import app.repositories.pharmacy_repo as repo
from app.schema.pharmacy_schema import (
    MedicineCreate, MedicineUpdate, StockReceiptCreate
)

def fetch_medicines(search: Optional[str] = None, status_filter: Optional[str] = None) -> List[Dict[str, Any]]:
    with get_db() as conn:
        return repo.get_all_medicines(conn, search, status_filter)

def fetch_medicine(medicine_id: int) -> Dict[str, Any]:
    with get_db() as conn:
        med = repo.get_medicine_by_id(conn, medicine_id)
        if not med:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Medicine with ID {medicine_id} not found."
            )
        return med

def create_medicine(data: MedicineCreate) -> Dict[str, Any]:
    with get_db() as conn:
        med_id = repo.add_medicine(conn, data.model_dump())
        return repo.get_medicine_by_id(conn, med_id)

def modify_medicine(medicine_id: int, data: MedicineUpdate) -> Dict[str, Any]:
    with get_db() as conn:
        existing = repo.get_medicine_by_id(conn, medicine_id)
        if not existing:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Medicine with ID {medicine_id} not found."
            )
        updates = {k: v for k, v in data.model_dump(exclude_unset=True).items() if v is not None}
        if updates:
            repo.update_medicine(conn, medicine_id, updates)
        return repo.get_medicine_by_id(conn, medicine_id)

def record_stock_receipt(data: StockReceiptCreate) -> Dict[str, Any]:
    with get_db() as conn:
        med = repo.get_medicine_by_id(conn, data.medicine_id)
        if not med:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Medicine with ID {data.medicine_id} not found."
            )
        receipt_id = repo.receive_stock(
            conn,
            medicine_id=data.medicine_id,
            quantity=data.quantity,
            expiry_date=data.expiry_date,
            received_by=data.received_by
        )
        return {
            "receipt_id": receipt_id,
            "medicine_id": data.medicine_id,
            "quantity": data.quantity,
            "expiry_date": data.expiry_date,
            "received_by": data.received_by
        }

def fetch_low_stock_alerts() -> List[Dict[str, Any]]:
    with get_db() as conn:
        return repo.get_low_stock_alerts(conn)

def fetch_expiring_medicines(days_threshold: int = 30) -> List[Dict[str, Any]]:
    with get_db() as conn:
        return repo.get_expiring_medicines(conn, days_threshold)

def fetch_top_dispensed(limit: int = 10) -> List[Dict[str, Any]]:
    with get_db() as conn:
        return repo.get_frequently_dispensed(conn, limit)

def fetch_daily_dispensing_report(start_date: Optional[date], end_date: Optional[date]) -> List[Dict[str, Any]]:
    with get_db() as conn:
        start = start_date or date(2026, 1, 1)
        end = end_date or date.today()
        return repo.get_daily_dispensing_report(conn, start, end)

def fetch_dashboard_kpis() -> Dict[str, Any]:
    with get_db() as conn:
        return repo.get_dashboard_kpis(conn)

def create_order(payload: Any, pharmacist_id: int) -> Dict[str, Any]:
    with get_db() as conn:
        try:
            order_id = repo.create_purchase_order(
                conn,
                pharmacist_id=pharmacist_id,
                supplier_name=payload.supplier_name or "State Pharmaceuticals Corporation",
                expected_delivery_date=payload.expected_delivery_date,
                notes=payload.notes,
                items=[it.model_dump() for it in payload.items]
            )
            return repo.get_purchase_order_by_id(conn, order_id)
        except ValueError as e:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

def fetch_orders() -> List[Dict[str, Any]]:
    with get_db() as conn:
        return repo.get_purchase_orders(conn)

def fetch_order(order_id: int) -> Dict[str, Any]:
    with get_db() as conn:
        order = repo.get_purchase_order_by_id(conn, order_id)
        if not order:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Order #{order_id} not found.")
        return order

def change_order_status(order_id: int, new_status: str) -> Dict[str, Any]:
    with get_db() as conn:
        order = repo.get_purchase_order_by_id(conn, order_id)
        if not order:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Order #{order_id} not found.")
        repo.update_purchase_order_status(conn, order_id, new_status)
        return repo.get_purchase_order_by_id(conn, order_id)

def receive_and_restock_order(order_id: int, staff_id: int, expiry_date: Optional[date] = None) -> Dict[str, Any]:
    with get_db() as conn:
        order = repo.get_purchase_order_by_id(conn, order_id)
        if not order:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Order #{order_id} not found.")
        try:
            repo.restock_delivered_order(conn, order_id, staff_id, expiry_date)
            return repo.get_purchase_order_by_id(conn, order_id)
        except Exception as e:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


