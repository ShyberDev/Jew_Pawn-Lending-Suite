import frappe
from frappe.model.document import Document
from frappe.utils import flt

from pawn_shop.utils import money


class PawnRelease(Document):
	def _settlement_loan(self):
		"""Load the pawn loan and compute its balance as of the release date.

		Interest accrues daily (days / 30), so a loan's stored balance can be
		stale by the time the customer pays. Recompute against ``release_date``
		so a full settlement actually closes the loan instead of leaving a
		residual day of interest.
		"""
		loan = frappe.get_doc("Pawn Loan", self.pawn_loan)
		loan.release_date = self.release_date
		loan.status = "Released"
		loan.compute_interest()
		return loan

	def validate(self):
		self.total_paid = money(
			flt(self.principal_paid) + flt(self.interest_paid) + flt(self.other_charges)
		)
		if flt(self.total_paid) <= 0:
			frappe.throw(frappe._("Total paid must be greater than zero."))
		loan = self._settlement_loan()
		if flt(self.total_paid) > flt(loan.balance) + 0.01:
			frappe.throw(
				frappe._("Total paid {0} exceeds the outstanding balance {1}.").format(
					money(self.total_paid), money(loan.balance)
				)
			)

	def on_submit(self):
		loan = self._settlement_loan()
		loan.amount_paid = money(flt(loan.amount_paid) + flt(self.total_paid))
		loan.compute_interest()
		loan.status = "Released" if flt(loan.balance) <= 0 else "Active"
		loan.flags.ignore_permissions = True
		loan.save()
		self.db_set("total_paid", self.total_paid)
		frappe.msgprint(
			frappe._("Pawn Loan {0} balance is now {1}.").format(
				loan.name, money(loan.balance)
			),
			indicator="green",
		)

	def on_cancel(self):
		loan = frappe.get_doc("Pawn Loan", self.pawn_loan)
		loan.amount_paid = money(max(0.0, flt(loan.amount_paid) - flt(self.total_paid)))
		if loan.status == "Released":
			loan.status = "Active"
			loan.release_date = None
		loan.flags.ignore_permissions = True
		loan.save()
