import frappe


def execute():
	frappe.db.sql(
		"""
		UPDATE `tabLoan Disbursement`
		SET status = 'Draft'
		WHERE docstatus = 0
	"""
	)

	frappe.db.sql(
		"""
		UPDATE `tabLoan Disbursement`
		SET status = 'Submitted'
		WHERE docstatus = 1
	"""
	)

	frappe.db.sql(
		"""
		UPDATE `tabLoan Disbursement`
		SET status = 'Cancelled'
		WHERE docstatus = 2
	"""
	)

	frappe.db.sql(
		"""
		UPDATE `tabLoan Disbursement` ld
		INNER JOIN `tabLoan Repayment Schedule` lrs
		ON ld.name = lrs.loan_disbursement
		SET ld.status = 'Closed'
		WHERE lrs.status = 'Closed'
	"""
	)
