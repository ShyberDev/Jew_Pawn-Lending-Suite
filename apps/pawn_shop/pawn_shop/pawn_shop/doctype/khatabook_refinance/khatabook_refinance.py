import frappe
from frappe.model.document import Document
from frappe.utils import flt

from pawn_shop.utils import add_days, interval_days, money


class KhatabookRefinance(Document):
	def validate(self):
		if not flt(self.new_principal):
			self.new_principal = flt(
				frappe.db.get_value("Khatabook Loan", self.khatabook_loan, "outstanding")
			)
		if not self.new_installment_count:
			self.new_installment_count = 12

	def on_submit(self):
		old = frappe.get_doc("Khatabook Loan", self.khatabook_loan)
		self.db_set("old_outstanding", old.outstanding)

		new = frappe.new_doc("Khatabook Loan")
		new.customer = old.customer
		new.village = old.village
		new.business = old.business
		new.loan_date = self.refinance_date
		new.principal_amount = flt(self.new_principal) or flt(old.outstanding)
		new.interest_amount = flt(self.new_interest_amount)
		new.installment_count = self.new_installment_count
		new.collection_frequency = old.collection_frequency
		new.start_date = add_days(self.refinance_date, interval_days(old.collection_frequency))
		new.refinanced_from = old.name
		new.remarks = frappe._("Refinanced from {0}. {1}").format(
			old.name, self.new_interest_note or ""
		)
		new.flags.ignore_permissions = True
		new.insert()

		self.db_set("new_loan", new.name)

		old.status = "Closed"
		old.remarks = frappe._("Refinanced into {0}.").format(new.name)
		old.flags.ignore_permissions = True
		old.save()

		frappe.msgprint(
			frappe._("Old loan {0} closed; new loan {1} created with outstanding {2}.").format(
				old.name, new.name, money(new.total_payable)
			),
			indicator="green",
		)

	def on_cancel(self):
		if not self.new_loan:
			return
		new = frappe.get_doc("Khatabook Loan", self.new_loan)
		if new.docstatus == 0:
			frappe.delete_doc("Khatabook Loan", new.name, ignore_permissions=True)
		old = frappe.get_doc("Khatabook Loan", self.khatabook_loan)
		if old.status == "Closed":
			old.status = "Active"
			old.flags.ignore_permissions = True
			old.save()
		self.db_set("new_loan", None)
