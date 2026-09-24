frappe.query_reports["Pawn Valuation"] = {
	filters: [
  {
    "fieldname": "as_on_date",
    "label": "As On Date",
    "fieldtype": "Date",
    "default": "Today"
  },
  {
    "fieldname": "metal_type",
    "label": "Metal",
    "fieldtype": "Select",
    "options": "\nGold\nSilver\nOther"
  }
],
};
