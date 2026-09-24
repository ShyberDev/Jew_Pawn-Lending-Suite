import frappe
from frappe import _
from frappe.utils import add_months, flt, getdate, today

from pawn_shop.utils import money


def _existing_field(doctype, candidates):
	if not frappe.db.exists("DocType", doctype):
		return None
	meta = frappe.get_meta(doctype)
	fields = {f.fieldname for f in meta.fields}
	for c in candidates:
		if c in fields:
			return c
	return None


def _in_range(value, start, end):
	return value and start <= getdate(value) <= end


def execute(filters=None):
	filters = filters or {}
	from_date = getdate(filters.get("from_date") or add_months(today(), -6))
	to_date = getdate(filters.get("to_date") or today())

	columns = [
		{"label": _("Business"), "fieldname": "business", "fieldtype": "Data", "width": 150},
		{"label": _("Type"), "fieldname": "business_type", "fieldtype": "Data", "width": 110},
		{"label": _("Documents"), "fieldname": "documents", "fieldtype": "Int", "width": 90},
		{"label": _("Principal / Purchases"), "fieldname": "principal", "fieldtype": "Currency", "width": 160},
		{"label": _("Income"), "fieldname": "income", "fieldtype": "Currency", "width": 130},
		{"label": _("Collected"), "fieldname": "collected", "fieldtype": "Currency", "width": 130},
		{"label": _("Outstanding"), "fieldname": "outstanding", "fieldtype": "Currency", "width": 130},
	]

	data = []

	# --- Shop (Jewellery ERP) -------------------------------------------------
	shop_income = shop_purchases = 0.0
	shop_docs = 0
	if frappe.db.exists("DocType", "Jewellery Sales Invoice"):
		sales = frappe.get_all("Jewellery Sales Invoice", filters={"docstatus": 1},
		                       fields=["grand_total", "sales_date"])
		for s in sales:
			if _in_range(s.sales_date, from_date, to_date):
				shop_income += flt(s.grand_total)
				shop_docs += 1
	if frappe.db.exists("DocType", "Jewellery Purchase Invoice"):
		pdate = _existing_field("Jewellery Purchase Invoice", ["purchase_date", "invoice_date", "posting_date"])
		purchases = frappe.get_all("Jewellery Purchase Invoice", filters={"docstatus": 1},
		                           fields=["grand_total", pdate])
		for p in purchases:
			if _in_range(p.get(pdate), from_date, to_date):
				shop_purchases += flt(p.grand_total)
	data.append({
		"business": _("Shop (Jewellery)"), "business_type": "Shop", "documents": shop_docs,
		"principal": money(shop_purchases), "income": money(shop_income),
		"collected": money(shop_income), "outstanding": 0.0,
	})

	# --- Money Lending (frappe/lending) --------------------------------------
	lend_principal = lend_income = lend_collected = lend_outstanding = 0.0
	lend_docs = 0
	if frappe.db.exists("DocType", "Loan"):
		loans = frappe.get_all("Loan", fields=["loan_amount", "disbursed_amount", "posting_date", "status"])
		for loan in loans:
			if _in_range(loan.posting_date, from_date, to_date):
				lend_principal += flt(loan.disbursed_amount) or flt(loan.loan_amount)
				lend_docs += 1
			if loan.status in ("Active", "Disbursed", "Partially Disbursed"):
				lend_outstanding += flt(loan.disbursed_amount) or flt(loan.loan_amount)
	if frappe.db.exists("DocType", "Loan Interest Accrual"):
		accruals = frappe.get_all("Loan Interest Accrual", filters={"docstatus": 1},
		                          fields=["interest_amount", "posting_date"])
		for a in accruals:
			if _in_range(a.posting_date, from_date, to_date):
				lend_income += flt(a.interest_amount)
	if frappe.db.exists("DocType", "Loan Repayment"):
		reps = frappe.get_all("Loan Repayment", filters={"docstatus": 1},
		                      fields=["amount_paid", "posting_date"])
		for r in reps:
			if _in_range(r.posting_date, from_date, to_date):
				lend_collected += flt(r.amount_paid)
	data.append({
		"business": _("Money Lending"), "business_type": "Money Lending", "documents": lend_docs,
		"principal": money(lend_principal), "income": money(lend_income),
		"collected": money(lend_collected), "outstanding": money(lend_outstanding),
	})

	# --- Pawn -----------------------------------------------------------------
	pawn_principal = pawn_income = pawn_collected = pawn_outstanding = 0.0
	pawn_docs = 0
	pawn_loans = frappe.get_all("Pawn Loan", fields=["loan_amount", "loan_date", "balance", "status"])
	for loan in pawn_loans:
		if _in_range(loan.loan_date, from_date, to_date):
			pawn_principal += flt(loan.loan_amount)
			pawn_docs += 1
		if loan.status in ("Active", "Overdue"):
			pawn_outstanding += flt(loan.balance)
	releases = frappe.get_all("Pawn Release", filters={"docstatus": 1},
	                          fields=["interest_paid", "total_paid", "release_date"])
	for r in releases:
		if _in_range(r.release_date, from_date, to_date):
			pawn_income += flt(r.interest_paid)
			pawn_collected += flt(r.total_paid)
	data.append({
		"business": _("Pawn"), "business_type": "Pawn", "documents": pawn_docs,
		"principal": money(pawn_principal), "income": money(pawn_income),
		"collected": money(pawn_collected), "outstanding": money(pawn_outstanding),
	})

	# --- Khatabook ------------------------------------------------------------
	kb_principal = kb_income = kb_collected = kb_outstanding = 0.0
	kb_docs = 0
	kb_loans = frappe.get_all("Khatabook Loan",
	                          fields=["name", "principal_amount", "interest_amount", "total_payable",
	                                  "loan_date", "outstanding", "status"])
	kb_ratio = {}
	for loan in kb_loans:
		if _in_range(loan.loan_date, from_date, to_date):
			kb_principal += flt(loan.principal_amount)
			kb_docs += 1
		if loan.status == "Active":
			kb_outstanding += flt(loan.outstanding)
		kb_ratio[loan.name] = (
			flt(loan.interest_amount) / flt(loan.total_payable) if flt(loan.total_payable) else 0.0
		)
	collections = frappe.get_all("Khatabook Collection", filters={"docstatus": 1},
	                             fields=["khatabook_loan", "amount", "collection_date"])
	for c in collections:
		if _in_range(c.collection_date, from_date, to_date):
			kb_collected += flt(c.amount)
			kb_income += flt(c.amount) * kb_ratio.get(c.khatabook_loan, 0.0)
	data.append({
		"business": _("Khatabook Lending"), "business_type": "Khatabook", "documents": kb_docs,
		"principal": money(kb_principal), "income": money(kb_income),
		"collected": money(kb_collected), "outstanding": money(kb_outstanding),
	})

	# --- Total ----------------------------------------------------------------
	data.append({
		"business": _("TOTAL"), "business_type": "", "documents": sum(d["documents"] for d in data),
		"principal": money(sum(d["principal"] for d in data)),
		"income": money(sum(d["income"] for d in data)),
		"collected": money(sum(d["collected"] for d in data)),
		"outstanding": money(sum(d["outstanding"] for d in data)),
	})

	chart = {
		"data": {
			"labels": [d["business"] for d in data if d["business"] != _("TOTAL")],
			"datasets": [
				{"name": _("Income"), "values": [d["income"] for d in data if d["business"] != _("TOTAL")]},
				{"name": _("Outstanding"), "values": [d["outstanding"] for d in data if d["business"] != _("TOTAL")]},
			],
		},
		"type": "bar",
		"colors": ["#24963f", "#e67e22"],
	}
	return columns, data, None, chart
