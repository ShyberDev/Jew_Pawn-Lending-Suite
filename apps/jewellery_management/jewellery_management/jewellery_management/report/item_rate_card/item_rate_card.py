# Copyright (c) 2026, Sri Sai Krishna Jewellery and contributors
# For license information, please see license.txt

import frappe
from frappe.utils import flt

from jewellery_management.jewellery_management.fifo import get_current_metal_rates


def execute(filters=None):
    filters = frappe._dict(filters or {})

    cond = "rsi.active = 1"
    if filters.get("metal"):
        cond += " AND rsi.metal = %(metal)s"

    items = frappe.db.sql(
        """
        SELECT rsi.name, rsi.stock_item_name, rsi.metal, rsi.purity,
               rsi.hallmark_status, rsi.article_category,
               mp.purity_ AS purity_percentage
        FROM `tabRetail Stock Item` rsi
        LEFT JOIN `tabMetal Purity` mp ON mp.name = rsi.purity
        WHERE {cond}
        ORDER BY rsi.metal ASC, rsi.name ASC
        """.format(cond=cond),
        filters,
        as_dict=1,
    )

    rates = get_current_metal_rates()

    columns = [
        {"fieldname": "name", "label": "Item", "fieldtype": "Data", "width": 200},
        {"fieldname": "stock_item_name", "label": "Display Name", "fieldtype": "Data", "width": 140},
        {"fieldname": "metal", "label": "Metal", "fieldtype": "Data", "width": 70},
        {"fieldname": "purity", "label": "Purity", "fieldtype": "Data", "width": 90},
        {"fieldname": "purity_percentage", "label": "Purity %", "fieldtype": "Percent", "width": 80},
        {"fieldname": "hallmark_status", "label": "Hallmark", "fieldtype": "Data", "width": 110},
        {"fieldname": "article_category", "label": "Category", "fieldtype": "Data", "width": 120},
        {"fieldname": "current_rate", "label": "Metal Rate ₹/g", "fieldtype": "Currency", "width": 120},
    ]

    data = []
    for it in items:
        data.append({
            "name": it.name,
            "stock_item_name": it.stock_item_name,
            "metal": it.metal,
            "purity": it.purity,
            "purity_percentage": flt(it.purity_percentage),
            "hallmark_status": it.hallmark_status,
            "article_category": it.article_category,
            "current_rate": flt(rates.get(it.metal)),
        })

    return columns, data