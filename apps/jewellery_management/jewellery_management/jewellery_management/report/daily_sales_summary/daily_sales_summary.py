# Copyright (c) 2026, Sri Sai Krishna Jewellery and contributors
# For license information, please see license.txt

import frappe
from frappe.utils import flt


def execute(filters=None):
    filters = frappe._dict(filters or {})

    cond = "si.docstatus = 1"
    if filters.get("from_date"):
        cond += " AND si.sales_date >= %(from_date)s"
    if filters.get("to_date"):
        cond += " AND si.sales_date <= %(to_date)s"

    rows = frappe.db.sql(
        """
        SELECT si.sales_date AS date, si.name AS invoice, si.customer_name,
               si.gross_total_weight, si.net_total_weight, si.subtotal,
               si.gst_amount, si.grand_total, si.total_paid, si.balance_amount,
               si.is_return
        FROM `tabJewellery Sales Invoice` si
        WHERE {cond}
        ORDER BY si.sales_date ASC, si.name ASC
        """.format(cond=cond),
        filters,
        as_dict=1,
    )

    columns = [
        {"fieldname": "date", "label": "Date", "fieldtype": "Date", "width": 90},
        {"fieldname": "invoice", "label": "Invoice", "fieldtype": "Data", "width": 150},
        {"fieldname": "customer_name", "label": "Customer", "fieldtype": "Data", "width": 160},
        {"fieldname": "type", "label": "Type", "fieldtype": "Data", "width": 70},
        {"fieldname": "gross_total_weight", "label": "Gross g", "fieldtype": "Float", "precision": 3, "width": 80},
        {"fieldname": "net_total_weight", "label": "Net g", "fieldtype": "Float", "precision": 3, "width": 80},
        {"fieldname": "subtotal", "label": "Taxable", "fieldtype": "Currency", "width": 110},
        {"fieldname": "gst_amount", "label": "GST", "fieldtype": "Currency", "width": 100},
        {"fieldname": "grand_total", "label": "Grand Total", "fieldtype": "Currency", "width": 120},
        {"fieldname": "total_paid", "label": "Paid", "fieldtype": "Currency", "width": 110},
        {"fieldname": "balance_amount", "label": "Balance", "fieldtype": "Currency", "width": 110},
    ]

    summary = {
        "count": 0, "gross": 0.0, "net": 0.0, "subtotal": 0.0,
        "gst": 0.0, "grand": 0.0, "paid": 0.0, "balance": 0.0,
    }

    data = []
    for r in rows:
        data.append({
            "date": r.date,
            "invoice": r.invoice,
            "customer_name": r.customer_name,
            "type": "Return" if r.is_return else "Sale",
            "gross_total_weight": flt(r.gross_total_weight),
            "net_total_weight": flt(r.net_total_weight),
            "subtotal": flt(r.subtotal),
            "gst_amount": flt(r.gst_amount),
            "grand_total": flt(r.grand_total),
            "total_paid": flt(r.total_paid),
            "balance_amount": flt(r.balance_amount),
        })
        summary["count"] += 1
        summary["gross"] += flt(r.gross_total_weight)
        summary["net"] += flt(r.net_total_weight)
        summary["subtotal"] += flt(r.subtotal)
        summary["gst"] += flt(r.gst_amount)
        summary["grand"] += flt(r.grand_total)
        summary["paid"] += flt(r.total_paid)
        summary["balance"] += flt(r.balance_amount)

    data.append({
        "invoice": "TOTAL (%d invoices)" % summary["count"],
        "gross_total_weight": summary["gross"],
        "net_total_weight": summary["net"],
        "subtotal": summary["subtotal"],
        "gst_amount": summary["gst"],
        "grand_total": summary["grand"],
        "total_paid": summary["paid"],
        "balance_amount": summary["balance"],
    })

    return columns, data