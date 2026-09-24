import frappe
from frappe.model.document import Document
from frappe.utils import flt, getdate

from pawn_shop.utils import money, update_customer_rating


class KhatabookCollection(Document):
	def on_submit(self):
		loan = frappe.get_doc("Khatabook Loan", self.khatabook_loan)
		if loan.status == "Closed":
			frappe.throw(frappe._("Loan {0} is already closed.").format(loan.name))
		amount = flt(self.amount)
		if amount <= 0:
			frappe.throw(frappe._("Collection amount must be greater than zero."))
		if amount > flt(loan.outstanding) + 0.01:
			frappe.throw(
				frappe._("Amount {0} exceeds the outstanding {1}.").format(amount, loan.outstanding)
			)

		irregular = False
		for inst in loan.installments:
			if amount <= 0:
				break
			due = flt(inst.installment_amount) - flt(inst.amount_paid)
			if due <= 0:
				continue
			pay = min(amount, due)
			inst.amount_paid = money(flt(inst.amount_paid) + pay)
			inst.paid_date = self.collection_date
			amount -= pay
			if inst.due_date and getdate(self.collection_date) > getdate(inst.due_date):
				irregular = True
			if flt(inst.amount_paid) + 0.001 < flt(inst.installment_amount):
				irregular = True

		loan.flags.ignore_permissions = True
		loan.save()
		self.db_set("is_irregular", 1 if irregular else 0)
		update_customer_rating(loan)

	def on_cancel(self):
		loan = frappe.get_doc("Khatabook Loan", self.khatabook_loan)
		amount = flt(self.amount)
		for inst in reversed(loan.installments):
			if amount <= 0:
				break
			paid = flt(inst.amount_paid)
			if paid <= 0:
				continue
			back = min(amount, paid)
			inst.amount_paid = money(paid - back)
			if flt(inst.amount_paid) <= 0:
				inst.paid_date = None
			amount -= back
		if loan.status == "Closed":
			loan.status = "Active"
		loan.flags.ignore_permissions = True
		loan.save()
		update_customer_rating(loan)
