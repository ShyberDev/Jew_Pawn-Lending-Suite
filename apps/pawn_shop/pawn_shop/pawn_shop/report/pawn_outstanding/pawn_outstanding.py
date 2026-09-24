import frappe
from frappe import _
from frappe.utils import date_diff, flt, getdate, today


def execute(filters=None):
	filters = filters or {}
	conditions = {}
	if filters.get("status"):
		conditions["status"] = filters["status"]
	if filters.get("village"):
		conditions["village"] = filters["village"]

	columns = [
		{"label": _("Loan"), "fieldname": "name", "fieldtype": "Link", "options": "Pawn Loan", "width": 130},
		{"label": _("Customer"), "fieldname": "customer_name", "fieldtype": "Data", "width": 150},
		{"label": _("Village"), "fieldname": "village", "fieldtype": "Link", "options": "Village", "width": 110},
		{"label": _("Loan Date"), "fieldname": "loan_date", "fieldtype": "Date", "width": 100},
		{"label": _("Due Date"), "fieldname": "due_date", "fieldtype": "Date", "width": 100},
		{"label": _("Loan Amount"), "fieldname": "loan_amount", "fieldtype": "Currency", "width": 120},
		{"label": _("Interest Accrued"), "fieldname": "interest_accrued", "fieldtype": "Currency", "width": 130},
		{"label": _("Total Payable"), "fieldname": "total_payable", "fieldtype": "Currency", "width": 120},
		{"label": _("Paid"), "fieldname": "amount_paid", "fieldtype": "Currency", "width": 110},
		{"label": _("Balance"), "fieldname": "balance", "fieldtype": "Currency", "width": 120},
		{"label": _("Days Overdue"), "fieldname": "days_overdue", "fieldtype": "Int", "width": 110},
		{"label": _("Status"), "fieldname": "status", "fieldtype": "Data", "width": 100},
		{"label": _("Items"), "fieldname": "items", "fieldtype": "Int", "width": 70},
	]

	loans = frappe.get_all(
		"Pawn Loan",
		filters=conditions,
		fields=["name", "customer_name", "village", "loan_date", "due_date", "loan_amount",
		        "interest_accrued", "total_payable", "amount_paid", "balance", "status"],
		order_by="due_date asc",
	)
	data = []
	for loan in loans:
		days_overdue = 0
		if loan.due_date and flt(loan.balance) > 0 and getdate(loan.due_date) < getdate(today()):
			days_overdue = date_diff(today(), loan.due_date)
		row = dict(loan)
		row["days_overdue"] = days_overdue
		row["items"] = frappe.db.count("Pawn Item", {"parent": loan.name, "parenttype": "Pawn Loan"})
		data.append(row)
	return columns, data
