import frappe
from frappe import _
from frappe.utils import add_months, flt, get_first_day, get_last_day, getdate, today

from pawn_shop.utils import money


def execute(filters=None):
	filters = filters or {}
	from_date = getdate(filters.get("from_date") or add_months(today(), -6))
	to_date = getdate(filters.get("to_date") or today())

	columns = [
		{"label": _("Month"), "fieldname": "month", "fieldtype": "Data", "width": 110},
		{"label": _("New Loans"), "fieldname": "new_loans", "fieldtype": "Int", "width": 90},
		{"label": _("Principal Disbursed"), "fieldname": "disbursed", "fieldtype": "Currency", "width": 140},
		{"label": _("Interest Accrued"), "fieldname": "interest_accrued", "fieldtype": "Currency", "width": 140},
		{"label": _("Interest Collected"), "fieldname": "interest_collected", "fieldtype": "Currency", "width": 140},
		{"label": _("Principal Collected"), "fieldname": "principal_collected", "fieldtype": "Currency", "width": 140},
		{"label": _("Releases"), "fieldname": "releases", "fieldtype": "Int", "width": 80},
		{"label": _("Principal Outstanding"), "fieldname": "outstanding", "fieldtype": "Currency", "width": 150},
	]

	loans = frappe.get_all(
		"Pawn Loan",
		fields=["name", "loan_date", "loan_amount", "interest_rate", "release_date", "status"],
	)
	releases = frappe.get_all(
		"Pawn Release",
		filters={"docstatus": 1},
		fields=["pawn_loan", "release_date", "principal_paid", "interest_paid", "total_paid"],
	)

	data = []
	labels = []
	accrued_series = []
	collected_series = []
	totals = dict(new_loans=0, disbursed=0, interest_accrued=0, interest_collected=0,
	              principal_collected=0, releases=0, outstanding=0)

	month_start = get_first_day(from_date)
	while month_start <= to_date:
		month_end = get_last_day(month_start)
		label = month_start.strftime("%b %Y")

		new_loans = [l for l in loans if l.loan_date and month_start <= getdate(l.loan_date) <= month_end]
		disbursed = money(sum(flt(l.loan_amount) for l in new_loans))

		interest_accrued = 0.0
		for l in loans:
			if l.status == "Forfeited" or not l.loan_date:
				continue
			start = max(getdate(l.loan_date), month_start)
			end = min(getdate(l.release_date) if l.release_date else month_end, month_end)
			active_days = (end - start).days + 1
			if active_days <= 0:
				continue
			interest_accrued += flt(l.loan_amount) * flt(l.interest_rate) / 100.0 * active_days / 30.0
		interest_accrued = money(interest_accrued)

		month_releases = [
			r for r in releases if r.release_date and month_start <= getdate(r.release_date) <= month_end
		]
		interest_collected = money(sum(flt(r.interest_paid) for r in month_releases))
		principal_collected = money(sum(flt(r.principal_paid) for r in month_releases))

		outstanding = 0.0
		for l in loans:
			if not l.loan_date or getdate(l.loan_date) > month_end:
				continue
			if l.release_date and getdate(l.release_date) <= month_end:
				continue
			paid = sum(
				flt(r.principal_paid)
				for r in releases
				if r.pawn_loan == l.name and r.release_date and getdate(r.release_date) <= month_end
			)
			outstanding += flt(l.loan_amount) - paid
		outstanding = money(outstanding)

		row = {
			"month": label,
			"new_loans": len(new_loans),
			"disbursed": disbursed,
			"interest_accrued": interest_accrued,
			"interest_collected": interest_collected,
			"principal_collected": principal_collected,
			"releases": len(month_releases),
			"outstanding": outstanding,
		}
		data.append(row)
		labels.append(label)
		accrued_series.append(interest_accrued)
		collected_series.append(interest_collected)
		for k in totals:
			totals[k] += row[k]

		month_start = add_months(month_start, 1)

	data.append({
		"month": _("TOTAL"),
			"new_loans": totals["new_loans"],
			"disbursed": money(totals["disbursed"]),
			"interest_accrued": money(totals["interest_accrued"]),
			"interest_collected": money(totals["interest_collected"]),
			"principal_collected": money(totals["principal_collected"]),
			"releases": totals["releases"],
			"outstanding": money(totals["outstanding"]),
		})

	chart = {
		"data": {
			"labels": labels,
			"datasets": [
				{"name": _("Interest Accrued"), "values": accrued_series},
				{"name": _("Interest Collected"), "values": collected_series},
			],
		},
		"type": "line",
		"colors": ["#f0a500", "#24963f"],
	}
	return columns, data, None, chart
