# Copyright (c) 2026, Sri Sai Krishna Jewellery and contributors
# For license information, please see license.txt

import frappe

from jewellery_management.jewellery_management.fifo import (
    fifo_all,
    fmt,
)


def execute(filters=None):
    filters = frappe._dict(filters or {})

    data = fifo_all(
        as_of=filters.get("as_of"),
        retail_stock_item=filters.get("retail_stock_item"),
        purity=filters.get("purity"),
    )

    columns = [
        {
            "fieldname": "bucket",
            "label": "Item · Purity",
            "fieldtype": "Data",
            "width": 200,
        },
        {
            "fieldname": "date",
            "label": "Date",
            "fieldtype": "Date",
            "width": 90,
        },
        {
            "fieldname": "transaction",
            "label": "Transaction",
            "fieldtype": "Data",
            "width": 320,
        },
        {
            "fieldname": "movement",
            "label": "Mv",
            "fieldtype": "Data",
            "width": 55,
        },
        {
            "fieldname": "weight",
            "label": "Weight g",
            "fieldtype": "Float",
            "precision": 3,
            "width": 90,
        },
        {
            "fieldname": "rate",
            "label": "Rate ₹/g",
            "fieldtype": "Currency",
            "width": 100,
        },
        {
            "fieldname": "metal_value",
            "label": "Metal Value ₹",
            "fieldtype": "Currency",
            "width": 120,
        },
        {
            "fieldname": "stock_value",
            "label": "Doc Value ₹",
            "fieldtype": "Currency",
            "width": 120,
        },
        {
            "fieldname": "lot_rate",
            "label": "FIFO Lot Rate ₹/g",
            "fieldtype": "Currency",
            "width": 120,
        },
        {
            "fieldname": "fifo_cost",
            "label": "FIFO Cost ₹",
            "fieldtype": "Currency",
            "width": 120,
        },
        {
            "fieldname": "realised",
            "label": "Realised P&L ₹",
            "fieldtype": "Currency",
            "width": 120,
        },
        {
            "fieldname": "balance",
            "label": "Balance g",
            "fieldtype": "Float",
            "precision": 3,
            "width": 90,
        },
        {
            "fieldname": "provisional",
            "label": "Provisional P&L ₹",
            "fieldtype": "Currency",
            "width": 130,
        },
    ]

    result = []

    for bucket in data["buckets"]:
        label = "%s · %s" % (
            bucket["retail_stock_item"],
            bucket["purity"],
        )
        for row in bucket["rows"]:
            result.append(
                {
                    "bucket": label,
                    "date": row["date"],
                    "transaction": "%s · %s · %s"
                    % (row["jst"], row["transaction_type"], row["reference"]),
                    "movement": row["movement"],
                    "weight": fmt(row["weight"]),
                    "rate": fmt(row["rate"]),
                    "metal_value": fmt(row["metal_value"]),
                    "stock_value": fmt(row["stock_value"]),
                    "lot_rate": fmt(row["lot_rate"]),
                    "fifo_cost": fmt(row["fifo_cost"]),
                    "realised": fmt(row["realised"]),
                    "balance": fmt(row["balance"]),
                    "provisional": None,
                }
            )

        # bucket subtotal row
        result.append(
            {
                "bucket": "BUCKET TOTAL · %s" % label,
                "transaction": "Open stock: %d lot(s) at purchase cost, "
                "mark-to-market at %s" % (
                    bucket["open_lots_count"],
                    fmt(bucket["current_rate"]),
                ),
                "weight": fmt(bucket["open_weight"]),
                "rate": fmt(bucket["current_rate"]),
                "metal_value": fmt(bucket["book_value"]),
                "realised": fmt(bucket["realised_total"]),
                "provisional": fmt(bucket["provisional"]),
            }
        )

    t = data["totals"]
    # grand total row
    result.append(
        {
            "bucket": "GRAND TOTAL",
            "transaction": "Book + Provisional = MTM at current rate",
            "weight": fmt(t["open_weight"]),
            "metal_value": fmt(t["book_value"]),
            "realised": fmt(t["realised_total"]),
            "provisional": fmt(t["provisional"]),
        }
    )

    return columns, result