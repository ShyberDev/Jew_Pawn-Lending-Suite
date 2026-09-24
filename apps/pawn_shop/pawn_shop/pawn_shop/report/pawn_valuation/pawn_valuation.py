import frappe
from frappe import _
from frappe.utils import flt, getdate, today

from pawn_shop.utils import money, round3


def execute(filters=None):
	filters = filters or {}
	as_on = getdate(filters.get("as_on_date") or today())
	metal_filter = filters.get("metal_type")

	columns = [
		{"label": _("Metal"), "fieldname": "metal_type", "fieldtype": "Data", "width": 90},
		{"label": _("Hallmarked"), "fieldname": "hallmarked", "fieldtype": "Data", "width": 100},
		{"label": _("Net Wt (g)"), "fieldname": "net_weight", "fieldtype": "Float", "precision": 3, "width": 110},
		{"label": _("Gross Wt (g)"), "fieldname": "gross_weight", "fieldtype": "Float", "precision": 3, "width": 110},
		{"label": _("Market Value"), "fieldname": "market_value", "fieldtype": "Currency", "width": 130},
		{"label": _("Loan Outstanding"), "fieldname": "loan_outstanding", "fieldtype": "Currency", "width": 140},
		{"label": _("LTV %"), "fieldname": "ltv", "fieldtype": "Percent", "width": 90},
	]

	loans = frappe.get_all(
		"Pawn Loan",
		filters={"status": ["in", ["Active", "Overdue"]], "loan_date": ["<=", as_on]},
		fields=["name", "balance"],
	)
	buckets = {}
	for loan in loans:
		items = frappe.get_all(
			"Pawn Item",
			filters={"parent": loan.name, "parenttype": "Pawn Loan"},
			fields=["metal_type", "gross_weight", "net_weight", "hallmarked", "market_value"],
		)
		loan_market = sum(flt(i.market_value) for i in items) or 1.0
		for item in items:
			if metal_filter and item.metal_type != metal_filter:
				continue
			key = (item.metal_type, "Yes" if item.hallmarked else "No")
			b = buckets.setdefault(key, {"net": 0.0, "gross": 0.0, "value": 0.0, "loan": 0.0})
			b["net"] += flt(item.net_weight)
			b["gross"] += flt(item.gross_weight)
			b["value"] += flt(item.market_value)
			b["loan"] += flt(loan.balance) * (flt(item.market_value) / loan_market)

	data = []
	total = {"net": 0.0, "gross": 0.0, "value": 0.0, "loan": 0.0}
	for (metal, hallmarked), b in sorted(buckets.items()):
		ltv = (b["loan"] / b["value"] * 100.0) if b["value"] else 0.0
		data.append({
			"metal_type": metal,
			"hallmarked": hallmarked,
			"net_weight": round3(b["net"]),
			"gross_weight": round3(b["gross"]),
			"market_value": money(b["value"]),
			"loan_outstanding": money(b["loan"]),
			"ltv": round(ltv, 2),
		})
		for k in total:
			total[k] += b[k]

	data.append({
		"metal_type": _("TOTAL"),
		"hallmarked": "",
		"net_weight": round3(total["net"]),
		"gross_weight": round3(total["gross"]),
		"market_value": money(total["value"]),
		"loan_outstanding": money(total["loan"]),
		"ltv": round((total["loan"] / total["value"] * 100.0) if total["value"] else 0.0, 2),
	})
	return columns, data
