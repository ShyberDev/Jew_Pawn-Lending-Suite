frappe.query_reports["Khatabook Collection Sheet"] = {
	filters: [
  {
    "fieldname": "village",
    "label": "Village",
    "fieldtype": "Link",
    "options": "Village"
  },
  {
    "fieldname": "status",
    "label": "Status",
    "fieldtype": "Select",
    "options": "\nActive\nClosed\nDefaulted"
  },
  {
    "fieldname": "rating",
    "label": "Rating",
    "fieldtype": "Select",
    "options": "\nNew\nGood\nBad"
  }
],
};
