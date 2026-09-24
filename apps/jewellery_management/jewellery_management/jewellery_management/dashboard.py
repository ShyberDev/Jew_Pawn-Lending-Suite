"""Home dashboard data for Sri Sai Krishna Jewellery (read-only)."""

import frappe
from frappe.utils import flt


def _bucket(purity_name, metal, pct):
    name = (purity_name or "").lower()
    if metal == "Gold":
        if "22" in name:
            return "gold_22k"
        if "18" in name:
            return "gold_18k"
        if "24" in name or (pct and pct >= 99):
            return "gold_24k"
        if pct and 91 <= pct <= 92:
            return "gold_22k"
        if pct and 74 <= pct <= 76:
            return "gold_18k"
        return "gold_other"
    return "silver"


@frappe.whitelist()
def get_data(from_date: str, to_date: str) -> dict:
    fd, td = from_date, to_date

    sales = frappe.db.sql(
        """SELECT COALESCE(SUM(grand_total),0) s, COUNT(*) c
           FROM `tabJewellery Sales Invoice`
           WHERE docstatus=1 AND sales_date BETWEEN %s AND %s""",
        (fd, td),
        as_dict=True,
    )[0]
    purch = frappe.db.sql(
        """SELECT COALESCE(SUM(grand_total),0) s, COUNT(*) c
           FROM `tabJewellery Purchase Invoice`
           WHERE docstatus=1 AND purchase_date BETWEEN %s AND %s""",
        (fd, td),
        as_dict=True,
    )[0]

    recv = frappe.db.sql(
        """SELECT COALESCE(SUM(grand_total - total_paid),0) s
           FROM `tabJewellery Sales Invoice` WHERE docstatus=1"""
    )[0][0]
    pay = frappe.db.sql(
        """SELECT COALESCE(SUM(grand_total - total_paid),0) s
           FROM `tabJewellery Purchase Invoice` WHERE docstatus=1"""
    )[0][0]

    orders = frappe.db.sql(
        """SELECT COUNT(*) c, COALESCE(SUM(grand_total),0) s
           FROM `tabJewellery Order`
           WHERE docstatus=0 AND order_status != 'Delivered'"""
    )[0]
    pending_delivery = frappe.db.sql(
        """SELECT COUNT(*) c FROM `tabJewellery Order`
           WHERE docstatus < 2 AND order_status != 'Delivered'"""
    )[0][0]
    karigar = frappe.db.sql(
        """SELECT COUNT(DISTINCT o.name) c, COALESCE(SUM(i.net_weight),0) w
           FROM `tabJewellery Order` o
           JOIN `tabJewellery Order Item` i ON i.parent = o.name
           WHERE o.docstatus < 2
             AND o.order_status IN ('Ordered to Worker', 'Worker Finished')"""
    )[0]

    oldgold = frappe.db.sql(
        """SELECT COUNT(*) c, COALESCE(SUM(estimated_fine_weight),0) w
           FROM `tabOld Gold Receipt`
           WHERE docstatus=1 AND (melt_reference IS NULL OR melt_reference='')"""
    )[0]

    # current stock per bucket (ledger rows are submitted; cancels excluded)
    purities = {
        p.name: (p.purity_name, p.metal, flt(p.purity_))
        for p in frappe.get_all(
            "Metal Purity", fields=["name", "purity_name", "metal", "purity_"]
        )
    }
    rows = frappe.db.sql(
        """SELECT retail_stock_item, purity,
                  SUM(CASE WHEN movement='In' THEN weight ELSE -weight END) w
           FROM `tabJewellery Stock Transaction`
           WHERE docstatus < 2
           GROUP BY retail_stock_item, purity"""
    )
    buckets = {"gold_22k": 0.0, "gold_18k": 0.0, "gold_24k": 0.0,
               "gold_other": 0.0, "silver": 0.0}
    for _, purity, w in rows:
        if not purity or not w:
            continue
        info = purities.get(purity)
        if not info:
            continue
        buckets[_bucket(*info)] = round(
            buckets[_bucket(*info)] + flt(w), 3
        )
    gold_total = round(
        buckets["gold_22k"] + buckets["gold_18k"]
        + buckets["gold_24k"] + buckets["gold_other"], 3
    )

    # stock value at latest rate per metal
    rates = {}
    for metal in ("Gold", "Silver"):
        r = frappe.db.sql(
            """SELECT rate_per_gram FROM `tabMetal Rate`
               WHERE metal=%s AND active=1
               ORDER BY rate_date DESC LIMIT 1""",
            metal,
        )
        rates[metal] = flt(r[0][0]) if r else 0
    stock_value = round(
        (gold_total) * rates["Gold"] + buckets["silver"] * rates["Silver"], 2
    )

    # lowest 5 stocked items + out-of-stock count
    items = frappe.db.sql(
        """SELECT rsi.name, rsi.stock_item_name, rsi.metal,
                  ROUND(SUM(CASE WHEN rst.movement='In' THEN rst.weight ELSE -rst.weight END),3) w
           FROM `tabRetail Stock Item` rsi
           JOIN `tabJewellery Stock Transaction` rst
             ON rst.retail_stock_item = rsi.name AND rst.docstatus < 2
           GROUP BY rsi.name
           ORDER BY w ASC"""
    )
    lowest = [
        {"id": r[0], "name": r[1], "metal": r[2], "weight": flt(r[3])}
        for r in items[:5]
    ]
    oos = sum(1 for r in items if flt(r[3]) <= 0)

    # daily trend in range
    trend = frappe.db.sql(
        """SELECT d, SUM(s), SUM(p) FROM (
             SELECT sales_date d, SUM(grand_total) s, 0 p
             FROM `tabJewellery Sales Invoice`
             WHERE docstatus=1 AND sales_date BETWEEN %s AND %s GROUP BY d
             UNION ALL
             SELECT purchase_date d, 0 s, SUM(grand_total) p
             FROM `tabJewellery Purchase Invoice`
             WHERE docstatus=1 AND purchase_date BETWEEN %s AND %s GROUP BY d
           ) t GROUP BY d ORDER BY d""",
        (fd, td, fd, td),
    )
    trend = [{"date": str(r[0]), "sales": flt(r[1]), "purchases": flt(r[2])}
             for r in trend]

    # recent activity (submitted docs, single fetch each)
    activity = []
    feeds = [
        ("Jewellery Sales Invoice", "sales_date", "customer_name",
         lambda d: f"SALE {d['name']} · {d.get('customer_name') or ''} · ₹{flt(d.get('grand_total')):,.0f}"),
        ("Jewellery Purchase Invoice", "purchase_date", "supplier_name",
         lambda d: f"PURCHASE {d['name']} · {d.get('supplier_name') or ''} · ₹{flt(d.get('grand_total')):,.0f}"),
        ("Jewellery Order", "order_date", "customer",
         lambda d: f"ORDER {d['name']} · {d.get('customer') or ''} · {d.get('order_status') or ''}"),
        ("Worker Settlement", "settlement_date", "worker",
         lambda d: f"SETTLEMENT {d['name']} · {d.get('worker') or ''} · {d.get('event_type') or ''}"),
        ("Old Gold Receipt", "receipt_date", "customer_name",
         lambda d: f"OLD GOLD {d['name']} · {d.get('customer_name') or ''} · {flt(d.get('estimated_fine_weight'))}g"),
        ("Old Gold Melt", "melt_date", None,
         lambda d: f"MELT {d['name']} · {flt(d.get('actual_fine_weight'))}g (var {flt(d.get('variance'))}g)"),
    ]
    for dt, datefield, _party, labelfn in feeds:
        try:
            meta_fields = ["name", datefield]
            for extra in ("customer_name", "supplier_name", "customer",
                          "worker", "grand_total", "order_status",
                          "event_type", "estimated_fine_weight",
                          "actual_fine_weight", "variance"):
                meta = frappe.get_meta(dt)
                if meta.has_field(extra):
                    meta_fields.append(extra)
            for d in frappe.get_all(
                dt, filters={"docstatus": 1}, fields=meta_fields,
                order_by=f"{datefield} DESC", limit=5,
            ):
                activity.append({"date": str(d.get(datefield)), "text": labelfn(d)})
        except Exception:
            continue
    activity.sort(key=lambda a: a["date"], reverse=True)
    activity = activity[:15]

    # cash / bank from ERPNext books (best effort)
    cash = bank = 0.0
    try:
        companies = frappe.db.sql("SELECT name FROM tabCompany")
        company = companies[0][0] if companies else None
        bals = frappe.db.sql(
            """SELECT a.account_type, SUM(g.debit - g.credit) b
               FROM `tabGL Entry` g JOIN tabAccount a ON a.name = g.account
               WHERE g.company=%s AND a.account_type IN ('Cash','Bank')
               GROUP BY a.account_type""",
            company,
            as_dict=True,
        )
        for b in bals:
            if b.account_type == "Cash":
                cash = flt(b.b)
            else:
                bank = flt(b.b)
    except Exception:
        pass

    return {
        "sales": {"amount": flt(sales.s), "count": sales.c},
        "purchases": {"amount": flt(purch.s), "count": purch.c},
        "receivables": flt(recv),
        "payables": flt(pay),
        "orders": {"active": orders[0], "amount": flt(orders[1]),
                   "pending_delivery": pending_delivery},
        "karigar": {"jobs": karigar[0], "weight": round(flt(karigar[1]), 3)},
        "old_gold": {"pending": oldgold[0],
                     "fine": round(flt(oldgold[1]), 3)},
        "metal": {**{k: v for k, v in buckets.items()},
                  "gold_total": gold_total},
        "stock_value": stock_value,
        "rates": rates,
        "low_stock": {"lowest": lowest, "out_of_stock": oos},
        "trend": trend,
        "activity": activity,
        "cash": cash,
        "bank": bank,
    }
