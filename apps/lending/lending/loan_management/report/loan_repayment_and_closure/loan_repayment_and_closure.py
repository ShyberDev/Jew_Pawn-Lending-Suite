# Copyright (c) 2013, Frappe Technologies Pvt. Ltd. and contributors
# For license information, please see license.txt


import frappe
from frappe import _


def execute(filters=None):
	columns = get_columns()
	data = get_data(filters)
	return columns, data


def get_columns():
	return [
		{"label": _("Posting Date"), "fieldtype": "Date", "fieldname": "posting_date", "width": 100},
		{"label": _("Value Date"), "fieldtype": "Date", "fieldname": "value_date", "width": 100},
		{
			"label": _("Loan Repayment"),
			"fieldtype": "Link",
			"fieldname": "loan_repayment",
			"options": "Loan Repayment",
			"width": 100,
		},
		{
			"label": _("Against Loan"),
			"fieldtype": "Link",
			"fieldname": "against_loan",
			"options": "Loan",
			"width": 200,
		},
		{"label": _("Applicant"), "fieldtype": "Data", "fieldname": "applicant", "width": 150},
		{"label": _("Payment Type"), "fieldtype": "Data", "fieldname": "repayment_type", "width": 150},
		{
			"label": _("Overdue Amount"),
			"fieldtype": "Currency",
			"fieldname": "overdue_amount",
			"options": "currency",
			"width": 100,
		},
		{
			"label": _("Total Principal Paid"),
			"fieldtype": "Currency",
			"fieldname": "principal_amount_paid",
			"options": "currency",
			"width": 100,
		},
		{
			"label": _("Total Interest Paid"),
			"fieldtype": "Currency",
			"fieldname": "total_interest_paid",
			"options": "currency",
			"width": 100,
		},
		{
			"label": _("Total Penalty Paid"),
			"fieldtype": "Currency",
			"fieldname": "total_penalty_paid",
			"options": "currency",
			"width": 100,
		},
		{
			"label": _("Total Payment"),
			"fieldtype": "Currency",
			"fieldname": "amount_paid",
			"options": "currency",
			"width": 100,
		},
		{
			"label": _("Currency"),
			"fieldtype": "Link",
			"fieldname": "currency",
			"options": "Currency",
			"width": 100,
			"hidden": 1,
		},
	]

def get_data(filters):
	data = []

	query_filters = {
		"docstatus": 1,
		"company": filters.get("company"),
	}

	if filters.get("applicant"):
		query_filters.update({"applicant": filters.get("applicant")})

	if filters.get("loan"):
		query_filters.update({"against_loan": filters.get("loan")})

	if filters.get("loan_product"):
		query_filters.update({"loan_product": filters.get("loan_product")})

	loan_repayments = frappe.get_all(
		"Loan Repayment",
		filters=query_filters,
		fields=[
			"posting_date",
			"value_date",
			"repayment_type",
			"applicant",
			"name",
			"against_loan",
			"payable_amount",
			"principal_amount_paid",
			"total_interest_paid",
			"total_penalty_paid",
			"amount_paid"
		],
	)

	default_currency = frappe.get_cached_value("Company", filters.get("company"), "default_currency")

	for repayment in loan_repayments:
		row = {
			"posting_date": repayment.posting_date,
			"value_date": repayment.value_date,
			"against_loan": repayment.against_loan,
			"loan_repayment": repayment.name,
			"applicant": repayment.applicant,
			"repayment_type": repayment.repayment_type,
			"overdue_amount": repayment.payable_amount,
			"principal_amount_paid": repayment.principal_amount_paid,
			"total_interest_paid": repayment.total_interest_paid,
			"total_penalty_paid": repayment.total_penalty_paid,
			"amount_paid": repayment.amount_paid,
			"currency": default_currency,
		}

		data.append(row)

	return data
