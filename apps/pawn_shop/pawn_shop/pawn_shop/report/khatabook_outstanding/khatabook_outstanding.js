frappe.query_reports["Khatabook Outstanding"] = {
	filters: [
  {
    "fieldname": "village",
    "label": "Village",
    "fieldtype": "Link",
    "options": "Village"
  },
  {
    "fieldname": "rating",
    "label": "Rating",
    "fieldtype": "Select",
    "options": "\nNew\nGood\nBad"
  }
],
};
