"""Worker Settlement ledger: gold grams and cash tracked separately.

Sign semantics (V1):
    pure_gold_delta > 0 : you owe the worker more pure gold
    pure_gold_delta < 0 : worker settled / paid in gold
    cash_delta > 0      : worker holds cash credit / advance
    cash_delta < 0      : worker cash reduced (e.g. Cash -> Gold)

Cash never auto-converts to gold. Cash -> Gold is an explicit
event using conversion_rate (never forced to reference rate).
History is append-only: correct via new adjusting entries,
amend flow revalidates.
"""

import frappe
from frappe.utils import flt


@frappe.whitelist()
def get_worker_balances(worker: str) -> dict[str, float]:
    """Submitted gold / cash balances for one worker."""
    rows = frappe.db.sql(
        """SELECT COALESCE(SUM(pure_gold_delta), 0) AS gold,
                  COALESCE(SUM(cash_delta), 0) AS cash
           FROM `tabWorker Settlement`
           WHERE worker = %s AND docstatus = 1""",
        worker,
        as_dict=True,
    )
    row = rows[0] if rows else {}
    return {
        "worker": worker,
        "gold_balance": flt(row.get("gold")),
        "cash_balance": flt(row.get("cash")),
    }


def validate_settlement(doc, method=None):
    """Enforce event-type rules before save / submit."""

    if not doc.worker:
        frappe.throw("Worker is required.")

    event = doc.event_type or ""
    gold = flt(doc.pure_gold_delta)
    cash = flt(doc.cash_delta)

    if event == "Physical Gold Given":
        if flt(doc.physical_weight) <= 0:
            frappe.throw("Physical Weight is required for Physical Gold Given.")
        if not doc.purity:
            frappe.throw("Purity is required for Physical Gold Given.")
        purity_pct = flt(frappe.db.get_value("Metal Purity", doc.purity, "purity_"))
        if purity_pct <= 0:
            frappe.throw("Purity percentage is missing on the selected Metal Purity.")
        doc.pure_gold_delta = -round(flt(doc.physical_weight) * purity_pct / 100, 3)
        if cash:
            frappe.throw("Cash must be zero for Physical Gold Given (use a separate Cash event).")

    elif event == "Worker Earning":
        if not gold:
            frappe.throw("Pure Gold ± is required for Worker Earning.")
        if cash:
            frappe.throw("Cash must be zero for Worker Earning (use a separate Cash event).")

    elif event in ("Cash Payment", "Cash Advance"):
        if not cash:
            frappe.throw(f"Cash ± is required for {event}.")
        if gold:
            frappe.throw(f"Pure Gold must be zero for {event} (gold moves only via explicit conversion).")

    elif event in ("Cash -> Gold", "Gold -> Cash"):
        if flt(doc.conversion_rate) <= 0:
            frappe.throw(f"Conversion / Settlement Rate is required for {event}.")

    if not flt(doc.pure_gold_delta) and not flt(doc.cash_delta):
        frappe.throw("Entry moves nothing: set Pure Gold ± and/or Cash ±.")
