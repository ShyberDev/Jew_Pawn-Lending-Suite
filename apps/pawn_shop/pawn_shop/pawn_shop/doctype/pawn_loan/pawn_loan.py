import frappe
from frappe.model.document import Document
from frappe.utils import flt, getdate, today

from pawn_shop.utils import (
	default_interest_rate,
	metal_valuation_rate,
	money,
	months_between,
	round3,
	round_pct,
)


class PawnLoan(Document):
	def validate(self):
		self.set_defaults()
		self.compute_items()
		self.compute_interest()
		self.check_ltv()

	def set_defaults(self):
		if not flt(self.interest_rate) and self.customer:
			self.interest_rate = default_interest_rate(self.interest_basis, self.customer)
		if not self.business:
			self.business = frappe.db.get_single_value("Pawn Settings", "pawn_business")

	def compute_items(self):
		total_gross = total_net = hallmarked = non_hallmarked = market_value = 0.0
		for item in self.items:
			gross = flt(item.gross_weight)
			net = flt(item.net_weight) or gross
			item.net_weight = round3(net)
			rate = flt(item.valuation_rate) or metal_valuation_rate(item.metal_type)
			item.valuation_rate = rate
			item.market_value = money(net * rate)
			total_gross += gross
			total_net += net
			market_value += flt(item.market_value)
			if item.hallmarked:
				hallmarked += net
			else:
				non_hallmarked += net
		self.total_gross_weight = round3(total_gross)
		self.total_net_weight = round3(total_net)
		self.hallmarked_weight = round3(hallmarked)
		self.non_hallmarked_weight = round3(non_hallmarked)
		self.total_market_value = money(market_value)

	def compute_interest(self):
		end = self.release_date if (self.status in ("Released", "Forfeited") and self.release_date) else None
		months = months_between(self.loan_date, end)
		self.interest_accrued = money(flt(self.loan_amount) * flt(self.interest_rate) / 100.0 * months)
		self.total_payable = money(flt(self.loan_amount) + flt(self.interest_accrued))
		self.balance = money(flt(self.total_payable) - flt(self.amount_paid))
		if (
			self.status == "Active"
			and flt(self.balance) > 0
			and self.due_date
			and getdate(self.due_date) < getdate(today())
		):
			self.status = "Overdue"

	def check_ltv(self):
		if not flt(self.total_market_value):
			return
		self.ltv = round_pct(flt(self.loan_amount) / flt(self.total_market_value) * 100.0)
		settings = frappe.get_cached_doc("Pawn Settings")
		limit = flt(settings.max_ltv_silver if self.interest_basis == "Silver" else settings.max_ltv_gold)
		if limit and flt(self.ltv) > limit:
			frappe.msgprint(
				frappe._("Loan is {0}% of the pledged value, above the {1}% LTV limit.").format(
					self.ltv, limit
				),
				title=frappe._("High LTV"),
				indicator="orange",
			)

	def on_update(self):
		if self.status == "Released" and flt(self.balance) > 0:
			frappe.msgprint(frappe._("Loan marked Released but balance is still {0}.").format(self.balance))
