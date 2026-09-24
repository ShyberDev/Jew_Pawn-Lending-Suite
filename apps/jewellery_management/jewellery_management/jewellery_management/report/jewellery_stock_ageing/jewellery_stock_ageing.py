# Copyright (c) 2026, Sri Sai Krishna Jewellery and contributors
# For license information, please see license.txt

import frappe
from frappe.utils import flt, getdate


def execute(filters=None):
    filters = frappe._dict(filters or {})
    as_of = getdate(filters.get("as_of") or frappe.utils.today())

    cond = "jst.docstatus = 1 AND jst.movement = 'In'"
    if filters.get("retail_stock_item"):
        cond += " AND jst.retail_stock_item = %(retail_stock_item)s"

    rows = frappe.db.sql(
        """
        SELECT jst.retail_stock_item, jst.item, jst.purity, jst.weight,
               jst.rate_24k, jst.stock_value, MIN(jst.transaction_date) AS first_in,
               MAX(jst.transaction_date) AS last_in
        FROM `tabJewellery Stock Transaction` jst
        WHERE {cond}
        GROUP BY jst.retail_stock_item, jst.purity, jst.item
        ORDER BY jst.retail_stock_item ASC, jst.item ASC
        """.format(cond=cond),
        filters,
        as_dict=1,
    )

    columns = [
        {"fieldname": "retail_stock_item", "label": "Item", "fieldtype": "Data", "width": 200},
        {"fieldname": "item", "label": "Category", "fieldtype": "Data", "width": 120},
        {"fieldname": "purity", "label": "Purity", "fieldtype": "Data", "width": 90},
        {"fieldname": "last_in", "label": "Last In", "fieldtype": "Date", "width": 90},
        {"fieldname": "age_days", "label": "Age Days", "fieldtype": "Int", "width": 70},
        {"fieldname": "age_bucket", "label": "Age Bucket", "fieldtype": "Data", "width": 100},
        {"fieldname": "weight", "label": "In Weight g", "fieldtype": "Float", "precision": 3, "width": 100},
        {"fieldname": "rate_24k", "label": "Rate ₹/g", "fieldtype": "Currency", "width": 100},
        {"fieldname": "stock_value", "label": "Value ₹", "fieldtype": "Currency", "width": 120},
    ]

    buckets = {
        "0-30 days": (0, 30),
        "31-60 days": (31, 60),
        "61-90 days": (61, 90),
        "90+ days": (91, 10 ** 6),
    }

    data = []
    totals = {k: 0.0 for k in buckets}
    total_weight = 0.0
    total_value = 0.0

    for r in rows:
        last_in = r.last_in or as_of
        age = max(0, (as_of - last_in).days)

        bucket = "90+ days"
        for name, (lo, hi) in buckets.items():
            if lo <= age <= hi:
                bucket = name
                break

        weight = flt(r.weight)
        value = flt(r.stock_value)
        totals[bucket] += weight
        total_weight += weight
        total_value += value

        data.append({
            "retail_stock_item": r.retail_stock_item,
            "item": r.item,
            "purity": r.purity,
            "last_in": last_in,
            "age_days": age,
            "age_bucket": bucket,
            "weight": weight,
            "rate_24k": flt(r.rate_24k),
            "stock_value": value,
        })

    for name in buckets:
        data.append({
            "retail_stock_item": "BUCKET TOTAL · %s" % name,
            "weight": totals[name],
        })
    data.append({
        "retail_stock_item": "GRAND TOTAL",
        "weight": total_weight,
        "stock_value": total_value,
    })

    return columns, data