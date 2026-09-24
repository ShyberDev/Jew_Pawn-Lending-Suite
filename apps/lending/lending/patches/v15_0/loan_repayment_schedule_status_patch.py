import frappe
from frappe.query_builder import DocType


def execute():
	LoanRepaymentSchedule = DocType("Loan Repayment Schedule")

	frappe.qb.update(LoanRepaymentSchedule).set(LoanRepaymentSchedule.status, "Cancelled").where(
		(LoanRepaymentSchedule.docstatus == 2) & (LoanRepaymentSchedule.status != "Cancelled")
	).run()
