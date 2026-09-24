"""Test that a Pawn Release settles against interest accrued to the release date.

Run with:

    bench --site library.local execute pawn_shop.tests.test_pawn_release.run

It creates a throwaway Pawn Customer + Pawn Loan, simulates a stale stored
balance (as if the loan was last saved days ago), then verifies that:

  * overpaying the settlement balance is rejected, and
  * paying the balance as of the release date closes the loan (balance 0).

Everything is cleaned up afterwards.
"""

import frappe
from frappe.utils import add_days, flt, today

from pawn_shop.utils import money, months_between

LOAN_AMOUNT = 10000.0
RATE = 3.0


def run():
	frappe.set_user("Administrator")
	out = {}

	customer = frappe.get_doc(
		{
			"doctype": "Pawn Customer",
			"customer_name": "Release Test Customer",
			"phone": "9000000001",
			"customer_type": "Gold Pawn",
		}
	).insert(ignore_permissions=True)

	loan = frappe.get_doc(
		{
			"doctype": "Pawn Loan",
			"customer": customer.name,
			"interest_basis": "Gold",
			"loan_date": add_days(today(), -45),
			"loan_amount": LOAN_AMOUNT,
			"interest_rate": RATE,
			"due_date": add_days(today(), 45),
			"items": [
				{
					"item_description": "Test chain",
					"metal_type": "Gold",
					"gross_weight": 10,
					"net_weight": 10,
					"hallmarked": 1,
					"valuation_rate": 5000,
				}
			],
		}
	).insert(ignore_permissions=True)
	out["loan"] = loan.name

	# Simulate a stale stored balance (as if last saved 5 days ago).
	frappe.db.set_value(
		"Pawn Loan",
		loan.name,
		{"balance": 10300.0, "total_payable": 10300.0, "interest_accrued": 300.0},
		update_modified=False,
	)

	months = months_between(loan.loan_date, today())
	settlement_interest = money(LOAN_AMOUNT * RATE / 100.0 * months)
	settlement_total = money(LOAN_AMOUNT + settlement_interest)
	out["settlement_total"] = settlement_total

	# 1) Overpay must be rejected.
	over = _make_release(customer.name, loan.name, settlement_total + 100)
	try:
		over.insert(ignore_permissions=True)
		out["overpay_rejected"] = False
		frappe.delete_doc("Pawn Release", over.name, force=True, ignore_permissions=True)
	except Exception as exc:
		# Do NOT roll back here - that would undo the loan we just created.
		out["overpay_rejected"] = isinstance(exc, frappe.ValidationError)
		out["overpay_error"] = str(exc)[:120]

	# 2) Exact settlement must close the loan.
	rel = _make_release(customer.name, loan.name, settlement_total)
	rel.insert(ignore_permissions=True)
	rel.submit()

	loan.reload()
	out["after_status"] = loan.status
	out["after_balance"] = loan.balance
	out["after_paid"] = loan.amount_paid
	out["passed"] = loan.status == "Released" and flt(loan.balance) <= 0

	# Cleanup.
	rel.cancel()
	frappe.delete_doc("Pawn Release", rel.name, force=True, ignore_permissions=True)
	frappe.delete_doc("Pawn Loan", loan.name, force=True, ignore_permissions=True)
	frappe.delete_doc("Pawn Customer", customer.name, force=True, ignore_permissions=True)
	frappe.db.commit()
	return out


def _make_release(customer, loan, total):
	# Split the total into principal + interest (principal first).
	principal = money(min(total, LOAN_AMOUNT))
	interest = money(total - principal)
	return frappe.get_doc(
		{
			"doctype": "Pawn Release",
			"pawn_loan": loan,
			"customer": customer,
			"release_date": today(),
			"principal_paid": principal,
			"interest_paid": interest,
			"other_charges": 0,
			"payment_mode": "Cash",
		}
	)
