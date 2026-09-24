"""Shared helpers for the Pawn Shop app.

Rounding contract (matches the jewellery app):
  * money  -> rounded UP (ceiling) to 2 decimals
  * weights -> rounded half-up to 3 decimals
  * percentages -> rounded half-up to 2 decimals
"""

from decimal import Decimal, ROUND_CEILING, ROUND_HALF_UP

import frappe
from frappe.utils import cint, date_diff, flt, getdate, today

MONEY = Decimal("0.01")
WEIGHT = Decimal("0.001")
PCT = Decimal("0.01")


def money(value) -> float:
    return float(Decimal(str(value or 0)).quantize(MONEY, rounding=ROUND_CEILING))


def round2(value) -> float:
    return float(Decimal(str(value or 0)).quantize(MONEY, rounding=ROUND_HALF_UP))


def round3(value) -> float:
    return float(Decimal(str(value or 0)).quantize(WEIGHT, rounding=ROUND_HALF_UP))


def round_pct(value) -> float:
    return float(Decimal(str(value or 0)).quantize(PCT, rounding=ROUND_HALF_UP))


def get_settings():
    return frappe.get_cached_doc("Pawn Settings")


def months_between(from_date, to_date=None) -> float:
    """Simple-interest month count: elapsed days / 30."""
    to_date = to_date or today()
    days = date_diff(getdate(to_date), getdate(from_date))
    if days <= 0:
        return 0.0
    return days / 30.0


def default_interest_rate(basis: str, customer: str | None = None) -> float:
    settings = get_settings()
    if customer:
        cust = frappe.get_cached_doc("Pawn Customer", customer)
        if (basis or "Gold") == "Silver" and flt(cust.silver_interest_rate):
            return flt(cust.silver_interest_rate)
        if (basis or "Gold") == "Gold" and flt(cust.gold_interest_rate):
            return flt(cust.gold_interest_rate)
    if (basis or "Gold") == "Silver":
        return flt(settings.default_silver_interest_rate) or 4.0
    return flt(settings.default_gold_interest_rate) or 3.0


def metal_valuation_rate(metal_type: str) -> float:
    """Fallback per-gram valuation: Pawn Settings first, then Metal Rate master."""
    settings = get_settings()
    if (metal_type or "Gold") == "Silver":
        if flt(settings.silver_valuation_rate):
            return flt(settings.silver_valuation_rate)
        rate = frappe.db.get_value(
            "Metal Rate", {"metal_type": "Silver", "active": 1}, "rate", order_by="rate_date desc"
        )
        return flt(rate)
    if flt(settings.gold_valuation_rate):
        return flt(settings.gold_valuation_rate)
    rate = frappe.db.get_value(
        "Metal Rate", {"metal_type": "Gold", "active": 1}, "rate", order_by="rate_date desc"
    )
    return flt(rate)


def interval_days(frequency: str) -> int:
    return {"Weekly": 7, "Biweekly": 14, "Monthly": 30}.get(frequency or "Weekly", 7)


def add_days(d, days):
    from frappe.utils import add_days as _add

    return _add(d, days)


def update_customer_rating(loan):
    """Good if no irregular collections, Bad if 2+ irregulars or defaulted."""
    if not loan.customer:
        return
    irregular = frappe.db.count(
        "Khatabook Collection", {"khatabook_loan": loan.name, "is_irregular": 1, "docstatus": 1}
    )
    if loan.status == "Defaulted" or irregular >= 2:
        rating = "Bad"
    elif loan.status == "Closed" or irregular == 0:
        rating = "Good"
    else:
        rating = "New"
    frappe.db.set_value("Pawn Customer", loan.customer, "rating", rating, update_modified=False)
