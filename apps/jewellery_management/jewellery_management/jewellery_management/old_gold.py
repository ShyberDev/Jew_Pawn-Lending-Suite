"""Old Gold two-leg accounting: metal in at tested purity, credit/cash out.

Estimate vs assay are stored separately and never overwritten.
Melting reconciles expected vs actual fine with explicit variance.
"""

import frappe
from frappe.utils import flt


def validate_receipt(doc, method=None):
    net = flt(doc.gross_weight) - flt(doc.deduction_weight)
    if net < 0:
        frappe.throw("Deduction cannot exceed Gross Weight.")
    doc.net_weight = round(net, 3)
    doc.estimated_fine_weight = round(net * flt(doc.estimated_purity) / 100, 3)
    if flt(doc.assayed_purity):
        doc.assayed_fine_weight = round(net * flt(doc.assayed_purity) / 100, 3)
    else:
        doc.assayed_fine_weight = 0
    doc.estimated_value = round(
        flt(doc.estimated_fine_weight) * flt(doc.rate_per_gram), 2
    )
    if doc.settlement_type == "Exchange Credit" and not doc.credit_amount:
        doc.credit_amount = doc.estimated_value


def validate_melt(doc, method=None):
    total_in = 0.0
    total_exp = 0.0
    for row in doc.items:
        if not row.receipt:
            frappe.throw("Old Gold Receipt is required on every melt row.")
        rec = frappe.db.get_value(
            "Old Gold Receipt",
            row.receipt,
            ["net_weight", "assayed_purity", "estimated_purity", "docstatus"],
            as_dict=True,
        )
        if not rec:
            frappe.throw(f"Receipt {row.receipt} not found.")
        if rec.docstatus != 1:
            frappe.throw(f"Receipt {row.receipt} must be submitted before melting.")
        pct = flt(rec.assayed_purity) or flt(rec.estimated_purity)
        row.input_net_weight = flt(rec.net_weight)
        row.input_assay_purity = pct
        row.expected_fine = round(flt(rec.net_weight) * pct / 100, 3)
        total_in += flt(rec.net_weight)
        total_exp += row.expected_fine
        if doc.docstatus == 0:
            frappe.db.set_value(
                "Old Gold Receipt", row.receipt, "melt_reference", doc.name
            )
    doc.total_input_weight = round(total_in, 3)
    doc.total_expected_fine = round(total_exp, 3)
    doc.variance = round(flt(doc.actual_fine_weight) - total_exp, 3)
    if doc.output_disposition == "Sold to Worker" and not doc.worker:
        frappe.throw("Worker is required when fine gold is Sold to Worker.")
