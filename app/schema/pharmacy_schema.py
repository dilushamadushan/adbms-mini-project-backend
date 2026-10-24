from datetime import date, datetime
from typing import Optional, List
from decimal import Decimal
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Medicine Schemas
# ---------------------------------------------------------------------------
class MedicineBase(BaseModel):
    med_name: str = Field(..., min_length=2, max_length=100, description="Commercial medicine name")
    generic_name: Optional[str] = Field(None, max_length=100, description="Generic pharmacological name")
    unit_price: Decimal = Field(..., gt=0, description="Selling unit price")
    reorder_level: int = Field(20, ge=0, description="Threshold for low-stock alert")
    expiry_date: Optional[date] = Field(None, description="Batch expiry date")
    is_active: bool = Field(True, description="Active status in inventory")

class MedicineCreate(MedicineBase):
    stock_qty: Optional[int] = Field(0, ge=0, description="Initial stock quantity")

class MedicineUpdate(BaseModel):
    med_name: Optional[str] = Field(None, min_length=2, max_length=100)
    generic_name: Optional[str] = None
    unit_price: Optional[Decimal] = Field(None, gt=0)
    stock_qty: Optional[int] = Field(None, ge=0)
    reorder_level: Optional[int] = Field(None, ge=0)
    expiry_date: Optional[date] = None
    is_active: Optional[bool] = None

class MedicineResponse(MedicineBase):
    medicine_id: int
    stock_qty: int
    days_to_expiry: Optional[int] = None
    stock_status: Optional[str] = None
    inventory_value: Optional[Decimal] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

# ---------------------------------------------------------------------------
# Stock Receipts Schemas
# ---------------------------------------------------------------------------
class StockReceiptCreate(BaseModel):
    medicine_id: int = Field(..., description="Target medicine ID")
    quantity: int = Field(..., gt=0, description="Quantity of units received")
    expiry_date: date = Field(..., description="Expiry date of the received batch")
    received_by: int = Field(..., description="Staff ID receiving the batch")

class StockReceiptResponse(BaseModel):
    receipt_id: int
    medicine_id: int
    quantity: int
    expiry_date: date
    received_by: int
    received_at: Optional[datetime] = None

class StockReceiptItemResponse(BaseModel):
    receipt_id: int
    medicine_id: int
    med_name: str
    generic_name: Optional[str] = None
    quantity: int
    expiry_date: date
    received_by: int
    received_by_name: Optional[str] = None
    received_at: datetime

# ---------------------------------------------------------------------------
# Alerts & Reports Schemas
# ---------------------------------------------------------------------------
class LowStockAlertResponse(BaseModel):
    medicine_id: int
    med_name: str
    generic_name: Optional[str] = None
    stock_qty: int
    reorder_level: int
    unit_price: Decimal
    expiry_date: date
    deficit_quantity: int

class ExpiringMedicineResponse(BaseModel):
    medicine_id: int
    med_name: str
    generic_name: Optional[str] = None
    stock_qty: int
    unit_price: Decimal
    expiry_date: date
    days_left: int
    urgency_status: str

class TopDispensedMedicineResponse(BaseModel):
    medicine_id: int
    med_name: str
    generic_name: Optional[str] = None
    current_stock: int
    total_dispense_events: int
    total_units_dispensed: int
    total_revenue_generated: Decimal

class DailyDispensingReportResponse(BaseModel):
    report_date: date
    total_dispensations: int
    total_units: int
    total_revenue: Decimal

class PharmacyDashboardKpisResponse(BaseModel):
    total_medicines: int
    total_stock_units: int
    low_stock_count: int
    expired_count: int
    expiring_soon_count: int
    total_inventory_valuation: Decimal
    today_units_dispensed: int
    today_revenue: Decimal

# ---------------------------------------------------------------------------
# Purchase Orders & Restock Requisition Schemas
# ---------------------------------------------------------------------------
class PurchaseOrderItemCreate(BaseModel):
    medicine_id: int
    requested_quantity: int = Field(..., gt=0)

class PurchaseOrderCreate(BaseModel):
    supplier_name: Optional[str] = "State Pharmaceuticals Corporation"
    expected_delivery_date: date = Field(..., description="Lead time must be at least 3 days")
    notes: Optional[str] = None
    items: List[PurchaseOrderItemCreate]

class PurchaseOrderItemResponse(BaseModel):
    item_id: int
    medicine_id: int
    med_name: str
    generic_name: Optional[str] = None
    requested_quantity: int
    unit_price: Decimal
    subtotal: Decimal

class PurchaseOrderResponse(BaseModel):
    order_id: int
    order_number: str
    pharmacist_id: int
    pharmacist_name: Optional[str] = None
    supplier_name: str
    order_date: datetime
    expected_delivery_date: date
    lead_time_days: Optional[int] = None
    total_cost: Decimal
    status: str
    notes: Optional[str] = None
    total_items: Optional[int] = 0
    items: Optional[List[PurchaseOrderItemResponse]] = []

# ---------------------------------------------------------------------------
# Prescription & Dispensing Schemas (Doctor-to-Pharmacist Workflow)
# ---------------------------------------------------------------------------
class MedicationPrescriptionItem(BaseModel):
    medicine: str
    dose: Optional[str] = "Standard"
    route: Optional[str] = "Oral"
    frequency: Optional[str] = "Once Daily"
    duration: Optional[str] = "7 Days"
    timeSlots: Optional[str] = None
    instructions: Optional[str] = None

class PrescriptionSendRequest(BaseModel):
    medications: List[MedicationPrescriptionItem]

class PrescriptionQueueItem(BaseModel):
    rx_id: int
    record_id: int
    med_name: str
    dosage: str
    duration: Optional[str] = None
    prescribed_at: Optional[datetime] = None
    patient_id: int
    patient_name: str
    allergies: Optional[str] = None
    doctor_name: str
    medicine_id: Optional[int] = None
    inventory_med_name: Optional[str] = None
    stock_qty: Optional[int] = None
    unit_price: Optional[Decimal] = None
    is_dispensed: bool = False
    dispense_id: Optional[int] = None

class DispenseRequest(BaseModel):
    medicine_id: int
    quantity: int = Field(..., gt=0, description="Quantity of medicine units to dispense")
    pharmacist_id: int = Field(5, description="Staff ID of the dispensing pharmacist")
    admission_id: Optional[int] = None

class DispenseResponse(BaseModel):
    success: bool
    message: str
    dispense_id: int
    rx_id: int
    medicine_id: int
    quantity: int
    unit_price: Decimal
    total_price: Decimal
    remaining_stock: int
    dispensed_at: datetime

class DispensationHistoryItem(BaseModel):
    dispense_id: int
    rx_id: int
    patient_name: str
    doctor_name: str
    med_name: str
    quantity: int
    unit_price_at_sale: Decimal
    total_revenue: Decimal
    dispensed_at: datetime
    pharmacist_name: str

