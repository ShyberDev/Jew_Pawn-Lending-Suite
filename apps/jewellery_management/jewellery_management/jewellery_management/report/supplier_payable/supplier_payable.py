# Copyright (c) 2026, Sri Sai Krishna Jewellery and contributors
# For license information, please see license.txt

import frappe
from frappe.utils import flt


def execute(filters=None):
    filters = frappe._dict(filters or {})

    cond = "pi.docstatus = 1"
    if filters.get("from_date"):
        cond += " AND pi.purchase_date >= %(from_date)s"
    if filters.get("to_date"):
        cond += " AND pi.purchase_date <= %(to_date)s"
    if filters.get("supplier_name"):
        cond += " AND pi.supplier_name LIKE %(supplier_name)s"

    rows = frappe.db.sql(
        """
        SELECT pi.supplier_name, pi.name AS invoice, pi.purchase_date,
               pi.supplier_invoice_no, pi.subtotal, pi.gst, pi.grand_total,
               pi.total_paid, pi.balance_amount, pi.is_return
        FROM `tabJewellery Purchase Invoice` pi
        WHERE {cond}
        ORDER BY pi.supplier_name ASC, pi.purchase_date ASC, pi.name ASC
        """.format(cond=cond),
        filters,
        as_dict=1,
    )

    columns = [
        {"fieldname": "supplier_name", "label": "Supplier", "fieldtype": "Data", "width": 180},
        {"fieldname": "purchase_date", "label": "Date", "fieldtype": "Date", "width": 90},
        {"fieldname": "invoice", "label": "Invoice", "fieldtype": "Data", "width": 150},
        {"fieldname": "supplier_invoice_no", "label": "Supplier Ref", "fieldtype": "Data", "width": 120},
        {"fieldname": "type", "label": "Type", "fieldtype": "Data", "width": 70},
        {"fieldname": "grand_total", "label": "Billed", "fieldtype": "Currency", "width": 120},
        {"fieldname": "total_paid", "label": "Paid", "fieldtype": "Currency", "width": 110},
        {"fieldname": "balance_amount", "label": "Payable", "fieldtype": "Currency", "width": 110},
    ]

    # aggregate per supplier first
    suppliers = {}
    for r in rows:
        s = suppliers.setdefault(r.supplier_name, {
            "count": 0, "total": 0.0, "paid": 0.0, "balance": 0.0, "rows": [],
        })
        s["count"] += 1
        s["total"] += flt(r.grand_total)
        s["paid"] += flt(r.total_paid)
        s["balance"] += flt(r.balance_amount)
        s["rows"].append(r)

    data = []
    for supplier_name in sorted(suppliers):
        s = suppliers[supplier_name]
        for r in s["rows"]:
            data.append({
                "supplier_name": supplier_name,
                "purchase_date": r.purchase_date,
                "invoice": r.invoice,
                "supplier_invoice_no": r.supplier_invoice_no,
                "type": "Return" if r.is_return else "Purchase",
                "grand_total": flt(r.grand_total),
                "total_paid": flt(r.total_paid),
                "balance_amount": flt(r.balance_amount),
            })
        data.append({
            "supplier_name": "TOTAL · %s" % supplier_name,
            "invoice": "%d invoice(s)" % s["count"],
            "grand_total": s["total"],
            "total_paid": s["paid"],
            "balance_amount": s["balance"],
        })

    return columns, data