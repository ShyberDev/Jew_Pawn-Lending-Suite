frappe.query_reports["Pawn Outstanding"] = {
	filters: [
  {
    "fieldname": "status",
    "label": "Status",
    "fieldtype": "Select",
    "options": "\nActive\nOverdue\nReleased\nForfeited"
  },
  {
    "fieldname": "village",
    "label": "Village",
    "fieldtype": "Link",
    "options": "Village"
  }
],
};
