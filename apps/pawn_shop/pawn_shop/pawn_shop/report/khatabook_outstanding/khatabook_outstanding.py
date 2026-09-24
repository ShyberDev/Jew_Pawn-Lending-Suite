import frappe
from frappe import _
from frappe.utils import getdate, today


def execute(filters=None):
	filters = filters or {}
	conditions = {"outstanding": [">", 0]}
	if filters.get("village"):
		conditions["village"] = filters["village"]
	if filters.get("rating"):
		conditions["customer_rating"] = filters["rating"]

	columns = [
		{"label": _("Loan"), "fieldname": "name", "fieldtype": "Link", "options": "Khatabook Loan", "width": 130},
		{"label": _("Customer"), "fieldname": "customer_name", "fieldtype": "Data", "width": 150},
		{"label": _("Village"), "fieldname": "village", "fieldtype": "Link", "options": "Village", "width": 120},
		{"label": _("Principal"), "fieldname": "principal_amount", "fieldtype": "Currency", "width": 110},
		{"label": _("Total Payable"), "fieldname": "total_payable", "fieldtype": "Currency", "width": 120},
		{"label": _("Collected"), "fieldname": "total_collected", "fieldtype": "Currency", "width": 110},
		{"label": _("Outstanding"), "fieldname": "outstanding", "fieldtype": "Currency", "width": 120},
		{"label": _("Paid Installments"), "fieldname": "paid_installments", "fieldtype": "Int", "width": 120},
		{"label": _("Overdue Installments"), "fieldname": "overdue_installments", "fieldtype": "Int", "width": 130},
		{"label": _("Rating"), "fieldname": "customer_rating", "fieldtype": "Data", "width": 90},
		{"label": _("Status"), "fieldname": "status", "fieldtype": "Data", "width": 100},
	]

	loans = frappe.get_all(
		"Khatabook Loan",
		filters=conditions,
		fields=["name", "customer_name", "village", "principal_amount", "total_payable",
		        "total_collected", "outstanding", "paid_installments", "customer_rating", "status"],
		order_by="outstanding desc",
	)
	data = []
	for loan in loans:
		overdue = frappe.db.sql(
			"""
			SELECT COUNT(*) FROM `tabKhatabook Installment`
			WHERE parent = %s AND due_date < %s AND IFNULL(amount_paid, 0) < installment_amount
			""",
			(loan.name, today()),
		)[0][0]
		row = dict(loan)
		row["overdue_installments"] = overdue
		data.append(row)
	return columns, data
