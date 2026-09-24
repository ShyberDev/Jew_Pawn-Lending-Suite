import frappe
from frappe.model.document import Document
from frappe.utils import cint, flt, getdate, today

from pawn_shop.utils import add_days, interval_days, money, update_customer_rating


class KhatabookLoan(Document):
	def validate(self):
		self.total_payable = money(flt(self.principal_amount) + flt(self.interest_amount))
		count = cint(self.installment_count) or 12
		self.installment_count = count
		self.installment_amount = money(flt(self.total_payable) / count)
		if not self.start_date:
			self.start_date = self.loan_date
		if not self.business:
			self.business = frappe.db.get_single_value("Pawn Settings", "khatabook_business")
		if not self.installments:
			self.build_schedule()
		else:
			self.end_date = self.installments[-1].due_date
		self.recompute()

	def build_schedule(self):
		days = interval_days(self.collection_frequency)
		self.installments = []
		for i in range(1, self.installment_count + 1):
			self.append(
				"installments",
				{
					"installment_no": i,
					"due_date": add_days(self.start_date, days * (i - 1)),
					"installment_amount": self.installment_amount,
					"amount_paid": 0,
					"status": "Pending",
				},
			)
		self.end_date = add_days(self.start_date, days * (self.installment_count - 1))

	def recompute(self):
		collected = sum(flt(i.amount_paid) for i in self.installments)
		self.total_collected = money(collected)
		self.paid_installments = sum(1 for i in self.installments if i.status == "Paid")
		self.outstanding = money(flt(self.total_payable) - flt(self.total_collected))
		for i in self.installments:
			if flt(i.installment_amount) and flt(i.amount_paid) >= flt(i.installment_amount):
				i.status = "Paid"
			elif flt(i.amount_paid) > 0:
				i.status = "Partial"
			elif i.due_date and getdate(i.due_date) < getdate(today()):
				i.status = "Late"
			else:
				i.status = "Pending"
		self.paid_installments = sum(1 for i in self.installments if i.status == "Paid")
		if flt(self.outstanding) <= 0 and self.status != "Defaulted":
			self.status = "Closed"
		if self.customer:
			self.customer_rating = frappe.db.get_value("Pawn Customer", self.customer, "rating") or "New"

	def on_update(self):
		if self.customer:
			update_customer_rating(self)

	@frappe.whitelist()
	def generate_schedule(self):
		if any(flt(i.amount_paid) > 0 for i in self.installments):
			frappe.throw(frappe._("Cannot regenerate the schedule after payments have been collected."))
		self.build_schedule()
		self.recompute()
		self.save()
		return self.as_dict()
