from typing import Optional, List
from datetime import date
from fastapi import APIRouter, Query, status

import app.services.pharmacy_service as service
from app.schema.pharmacy_schema import (
    MedicineCreate, MedicineUpdate, MedicineResponse,
    StockReceiptCreate, StockReceiptResponse,
    LowStockAlertResponse, ExpiringMedicineResponse,
    TopDispensedMedicineResponse, DailyDispensingReportResponse,
    PharmacyDashboardKpisResponse
)

router = APIRouter(prefix="/pharmacy", tags=["Pharmacy"])

@router.get("/dashboard/kpis", response_model=PharmacyDashboardKpisResponse)
def get_pharmacy_kpis():
    """Retrieve summary KPIs for the pharmacist dashboard."""
    return service.fetch_dashboard_kpis()

@router.get("/inventory", response_model=List[MedicineResponse])
def get_inventory(
    search: Optional[str] = Query(None, description="Search by medicine or generic name"),
    status: Optional[str] = Query(None, description="Filter by status (IN_STOCK, LOW_STOCK, EXPIRING_SOON, EXPIRED, OUT_OF_STOCK)")
):
    """List all medicines with current stock, pricing, and health status."""
    return service.fetch_medicines(search=search, status_filter=status)

@router.get("/inventory/{medicine_id}", response_model=MedicineResponse)
def get_medicine(medicine_id: int):
    """Retrieve details for a specific medicine."""
    return service.fetch_medicine(medicine_id)

@router.post("/inventory", response_model=MedicineResponse, status_code=status.HTTP_201_CREATED)
def create_medicine(payload: MedicineCreate):
    """Register a new medicine in the pharmacy inventory."""
    return service.create_medicine(payload)

@router.put("/inventory/{medicine_id}", response_model=MedicineResponse)
def update_medicine(medicine_id: int, payload: MedicineUpdate):
    """Update medicine details, prices, or reorder levels."""
    return service.modify_medicine(medicine_id, payload)

@router.post("/inventory/stock-receipt", response_model=StockReceiptResponse, status_code=status.HTTP_201_CREATED)
def receive_stock(payload: StockReceiptCreate):
    """Record receipt of a new batch of stock and automatically update inventory."""
    return service.record_stock_receipt(payload)

@router.get("/alerts/low-stock", response_model=List[LowStockAlertResponse])
def get_low_stock():
    """Identify medicines at or below their reorder threshold."""
    return service.fetch_low_stock_alerts()

@router.get("/alerts/expiring", response_model=List[ExpiringMedicineResponse])
def get_expiring_medicines(
    days: int = Query(30, ge=1, le=365, description="Lookahead window in days")
):
    """Identify medicines that have expired or will expire soon."""
    return service.fetch_expiring_medicines(days_threshold=days)

@router.get("/reports/top-dispensed", response_model=List[TopDispensedMedicineResponse])
def get_top_dispensed(
    limit: int = Query(10, ge=1, le=100, description="Number of top medicines to return")
):
    """Retrieve most frequently dispensed medications."""
    return service.fetch_top_dispensed(limit=limit)

@router.get("/reports/daily-dispensing", response_model=List[DailyDispensingReportResponse])
def get_daily_dispensing(
    start_date: Optional[date] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[date] = Query(None, description="End date (YYYY-MM-DD)")
):
    """Generate daily dispensing and revenue breakdown report."""
    return service.fetch_daily_dispensing_report(start_date=start_date, end_date=end_date)

# ---------------------------------------------------------------------------
# Purchase Orders & Restock Requisition Routes
# ---------------------------------------------------------------------------
from app.schema.pharmacy_schema import PurchaseOrderCreate, PurchaseOrderResponse

@router.post("/orders", response_model=PurchaseOrderResponse, status_code=status.HTTP_201_CREATED)
def create_restock_order(
    payload: PurchaseOrderCreate,
    pharmacist_id: int = Query(5, description="Staff ID placing the order")
):
    """Create a new official Restock Purchase Order (enforces min 3 business days lead time)."""
    return service.create_order(payload, pharmacist_id=pharmacist_id)

@router.get("/orders", response_model=List[PurchaseOrderResponse])
def list_restock_orders():
    """List all restock purchase orders."""
    return service.fetch_orders()

@router.get("/orders/{order_id}", response_model=PurchaseOrderResponse)
def get_restock_order(order_id: int):
    """Retrieve full details of a purchase order including itemized list for PDF/printing."""
    return service.fetch_order(order_id)

@router.put("/orders/{order_id}/status", response_model=PurchaseOrderResponse)
def update_order_status(
    order_id: int,
    new_status: str = Query(..., description="Target status: APPROVED, ORDERED, RECEIVED, CANCELLED")
):
    """Update order status (e.g. approve or mark received)."""
    return service.change_order_status(order_id, new_status)

@router.post("/orders/{order_id}/restock", response_model=PurchaseOrderResponse)
def restock_received_order(
    order_id: int,
    staff_id: int = Query(5, description="Staff ID receiving and restocking the order"),
    batch_expiry: Optional[date] = Query(None, description="Batch expiry date for received stock")
):
    """Confirm receipt of order and automatically restock all items into active inventory."""
    return service.receive_and_restock_order(order_id, staff_id=staff_id, expiry_date=batch_expiry)


# ---------------------------------------------------------------------------
# Prescriptions & Dispensing Endpoints
# ---------------------------------------------------------------------------
from app.schema.pharmacy_schema import (
    PrescriptionQueueItem, DispenseRequest, DispenseResponse, DispensationHistoryItem,
    PrescriptionSendRequest
)

@router.get("/prescriptions/pending", response_model=List[PrescriptionQueueItem])
def get_pending_prescriptions_queue():
    """List all pending prescriptions sent by doctors waiting to be dispensed."""
    return service.fetch_pending_prescriptions()

@router.get("/prescriptions/history", response_model=List[DispensationHistoryItem])
def get_dispensations_history(limit: int = Query(50, ge=1, le=200)):
    """Audit log of all dispensed prescriptions."""
    return service.fetch_dispensation_history(limit=limit)

@router.post("/prescriptions/{rx_id}/dispense", response_model=DispenseResponse)
def dispense_medication_to_patient(rx_id: int, payload: DispenseRequest):
    """
    Confirm dispensing of prescribed medication to patient.
    Triggers automatically deduct inventory stock and verify stock availability.
    """
    return service.dispense_prescription(rx_id, payload)

@router.post("/prescriptions/send/{appointment_id}")
def send_prescription_from_doctor(appointment_id: int, payload: PrescriptionSendRequest):
    """Direct clinical transmission of prescription from doctor consultation to pharmacy queue."""
    return service.dispatch_doctor_prescription(appointment_id, payload)


