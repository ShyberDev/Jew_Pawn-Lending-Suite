"""End-to-end test of the mobile sync API (pawn_shop.api.sync).

Run with:

    bench --site library.local execute pawn_shop.tests.test_sync_api.run

It creates a throwaway Pawn Customer + Pawn Loan, exercises register/push/pull/
update/idempotency/permission-rejection, then cleans everything up.
"""

import frappe

from pawn_shop.api import sync

CUST_UUID = "test-sync-cust-0001"
LOAN_UUID = "test-sync-loan-0001"


def run():
	frappe.set_user("Administrator")
	results = {}

	device = sync.register_device("Sync Test Phone", "android")["device"]
	results["device"] = device

	# 1) create a master
	pushed = sync.push(
		[
			{
				"op": "create",
				"doctype": "Pawn Customer",
				"client_uuid": CUST_UUID,
				"data": {
					"customer_name": "Sync Test Customer",
					"phone": "9999999999",
					"customer_type": "General",
				},
			}
		],
		device=device,
	)["results"][0]
	customer = pushed["server_name"]
	results["create_customer"] = pushed

	# 2) idempotency: same client_uuid must return the same name, no duplicate
	again = sync.push(
		[
			{
				"op": "create",
				"doctype": "Pawn Customer",
				"client_uuid": CUST_UUID,
				"data": {"customer_name": "Sync Test Customer", "phone": "9999999999"},
			}
		],
		device=device,
	)["results"][0]
	results["idempotent"] = {
		"same_name": again["server_name"] == customer,
		"count": frappe.db.count("Pawn Customer", {"name": customer}),
	}

	# 3) create + submit a transaction
	loan_pushed = sync.push(
		[
			{
				"op": "create",
				"doctype": "Pawn Loan",
				"client_uuid": LOAN_UUID,
				"submit": True,
				"data": {
					"customer": customer,
					"loan_date": "2026-09-24",
					"interest_basis": "Gold",
					"loan_amount": 10000,
					"due_date": "2026-12-24",
					"items": [
						{
							"item_description": "Gold Chain",
							"metal_type": "Gold",
							"gross_weight": 10,
							"net_weight": 10,
							"hallmarked": 1,
						}
					],
				},
			}
		],
		device=device,
	)["results"][0]
	loan = loan_pushed.get("server_name")
	results["create_loan"] = loan_pushed
	if loan:
		results["loan_state"] = frappe.db.get_value(
			"Pawn Loan",
			loan,
			["docstatus", "total_market_value", "interest_rate", "total_payable"],
			as_dict=True,
		)

	# 4) pull delta
	pulled = sync.pull(since="2026-09-24 00:00:00", doctypes=["Pawn Customer", "Pawn Loan"])
	results["pull_counts"] = {k: len(v) for k, v in pulled["docs"].items()}

	# 5) update a master by client_uuid
	updated = sync.push(
		[
			{
				"op": "update",
				"doctype": "Pawn Customer",
				"client_uuid": CUST_UUID,
				"data": {"phone": "8888888888"},
			}
		],
		device=device,
	)["results"][0]
	results["update"] = updated
	results["phone_after_update"] = frappe.db.get_value("Pawn Customer", customer, "phone")

	# 6) a DocType outside the registry must be rejected
	rejected = sync.push(
		[{"op": "create", "doctype": "User", "client_uuid": "nope", "data": {}}],
		device=device,
	)["results"][0]
	results["rejected"] = rejected

	_cleanup(customer, loan, device)
	return results


def _cleanup(customer, loan, device):
	if loan and frappe.db.exists("Pawn Loan", loan):
		try:
			doc = frappe.get_doc("Pawn Loan", loan)
			if doc.docstatus == 1:
				doc.cancel()
			frappe.delete_doc("Pawn Loan", loan, force=True)
		except Exception:
			frappe.log_error(title="test_sync_api cleanup loan")
	if customer and frappe.db.exists("Pawn Customer", customer):
		try:
			frappe.delete_doc("Pawn Customer", customer, force=True)
		except Exception:
			frappe.log_error(title="test_sync_api cleanup customer")
	for name in frappe.get_all(
		"Sync ID Map", filters={"client_uuid": ["in", [CUST_UUID, LOAN_UUID]]}, pluck="name"
	):
		frappe.delete_doc("Sync ID Map", name, force=True)
	if device and frappe.db.exists("Sync Device", device):
		frappe.delete_doc("Sync Device", device, force=True)
	for name in frappe.get_all("Sync Log", filters={"device": device}, pluck="name"):
		frappe.delete_doc("Sync Log", name, force=True)
	frappe.db.commit()
