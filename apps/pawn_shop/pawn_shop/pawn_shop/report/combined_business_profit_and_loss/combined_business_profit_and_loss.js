frappe.query_reports["Combined Business Profit and Loss"] = {
	filters: [
  {
    "fieldname": "from_date",
    "label": "From Date",
    "fieldtype": "Date",
    "default": "fiscal_year"
  },
  {
    "fieldname": "to_date",
    "label": "To Date",
    "fieldtype": "Date",
    "default": "Today"
  }
],
};
