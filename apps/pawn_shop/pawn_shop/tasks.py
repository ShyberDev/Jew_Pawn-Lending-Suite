import frappe
from frappe.utils import getdate, today


def mark_overdue_loans():
	"""Daily job: flag overdue pawn loans and defaulted Khatabook loans."""
	# Pawn loans past due with a balance
	loans = frappe.get_all(
		"Pawn Loan",
		filters={"status": "Active", "balance": [">", 0]},
		fields=["name", "due_date"],
	)
	for loan in loans:
		if loan.due_date and getdate(loan.due_date) < getdate(today()):
			frappe.db.set_value("Pawn Loan", loan.name, "status", "Overdue", update_modified=False)

	# Khatabook loans with 2+ overdue installments -> Defaulted
	kb_loans = frappe.get_all(
		"Khatabook Loan",
		filters={"status": "Active", "outstanding": [">", 0]},
		fields=["name", "customer"],
	)
	for loan in kb_loans:
		overdue = frappe.db.sql(
			"""
			SELECT COUNT(*) FROM `tabKhatabook Installment`
			WHERE parent = %s AND status IN ('Late', 'Partial', 'Pending')
			  AND due_date < %s AND IFNULL(amount_paid, 0) < installment_amount
			""",
			(loan.name, today()),
		)[0][0]
		if overdue >= 2:
			frappe.db.set_value("Khatabook Loan", loan.name, "status", "Defaulted", update_modified=False)
			if loan.customer:
				frappe.db.set_value("Pawn Customer", loan.customer, "rating", "Bad", update_modified=False)

	frappe.db.commit()
