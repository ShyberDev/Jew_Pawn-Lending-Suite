import frappe
from frappe import _
from frappe.utils import flt, getdate, today


def execute(filters=None):
	filters = filters or {}
	conditions = {}
	if filters.get("village"):
		conditions["village"] = filters["village"]
	if filters.get("status"):
		conditions["status"] = filters["status"]
	if filters.get("rating"):
		conditions["customer_rating"] = filters["rating"]

	columns = [
		{"label": _("Loan"), "fieldname": "name", "fieldtype": "Link", "options": "Khatabook Loan", "width": 130},
		{"label": _("Customer"), "fieldname": "customer_name", "fieldtype": "Data", "width": 150},
		{"label": _("Village"), "fieldname": "village", "fieldtype": "Link", "options": "Village", "width": 110},
		{"label": _("Principal"), "fieldname": "principal_amount", "fieldtype": "Currency", "width": 110},
		{"label": _("Interest"), "fieldname": "interest_amount", "fieldtype": "Currency", "width": 110},
		{"label": _("Total Payable"), "fieldname": "total_payable", "fieldtype": "Currency", "width": 120},
		{"label": _("Installment"), "fieldname": "installment_amount", "fieldtype": "Currency", "width": 110},
		{"label": _("Paid / Total"), "fieldname": "paid_ratio", "fieldtype": "Data", "width": 110},
		{"label": _("Collected"), "fieldname": "total_collected", "fieldtype": "Currency", "width": 110},
		{"label": _("Outstanding"), "fieldname": "outstanding", "fieldtype": "Currency", "width": 120},
		{"label": _("Irregular"), "fieldname": "irregular_count", "fieldtype": "Int", "width": 90},
		{"label": _("Rating"), "fieldname": "customer_rating", "fieldtype": "Data", "width": 90},
		{"label": _("Next Due"), "fieldname": "next_due", "fieldtype": "Date", "width": 100},
		{"label": _("Status"), "fieldname": "status", "fieldtype": "Data", "width": 100},
	]

	loans = frappe.get_all(
		"Khatabook Loan",
		filters=conditions,
		fields=["name", "customer_name", "village", "principal_amount", "interest_amount",
		        "total_payable", "installment_amount", "installment_count", "paid_installments",
		        "total_collected", "outstanding", "customer_rating", "status"],
		order_by="village asc, name asc",
	)
	data = []
	for loan in loans:
		next_due = frappe.db.get_value(
			"Khatabook Installment",
			{"parent": loan.name, "status": ["in", ["Pending", "Late", "Partial"]]},
			"due_date",
			order_by="due_date asc",
		)
		irregular = frappe.db.count(
			"Khatabook Collection",
			{"khatabook_loan": loan.name, "is_irregular": 1, "docstatus": 1},
		)
		row = dict(loan)
		row["paid_ratio"] = f"{loan.paid_installments or 0} / {loan.installment_count or 0}"
		row["irregular_count"] = irregular
		row["next_due"] = next_due
		data.append(row)
	return columns, data
