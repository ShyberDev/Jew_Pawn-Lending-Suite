import frappe
from frappe.model.document import Document
from frappe.utils import flt

from pawn_shop.utils import money


class PawnRelease(Document):
	def validate(self):
		self.total_paid = money(
			flt(self.principal_paid) + flt(self.interest_paid) + flt(self.other_charges)
		)
		if flt(self.total_paid) <= 0:
			frappe.throw(frappe._("Total paid must be greater than zero."))
		loan = frappe.get_doc("Pawn Loan", self.pawn_loan)
		if flt(self.total_paid) > flt(loan.balance) + 0.01:
			frappe.throw(
				frappe._("Total paid {0} exceeds the outstanding balance {1}.").format(
					self.total_paid, loan.balance
				)
			)

	def on_submit(self):
		loan = frappe.get_doc("Pawn Loan", self.pawn_loan)
		loan.amount_paid = money(flt(loan.amount_paid) + flt(self.total_paid))
		loan.flags.ignore_permissions = True
		loan.save()
		if flt(loan.balance) <= 0:
			loan.status = "Released"
			loan.release_date = self.release_date
			loan.save()
		self.db_set("total_paid", self.total_paid)
		frappe.msgprint(
			frappe._("Pawn Loan {0} balance is now {1}.").format(loan.name, loan.balance),
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
