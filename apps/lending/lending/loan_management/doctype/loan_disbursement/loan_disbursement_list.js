// Copyright (c) 2024, Frappe Technologies Pvt. Ltd. and Contributors
// License: GNU General Public License v3. See license.txt

frappe.listview_settings['Loan Disbursement'] = {
	get_indicator: function(doc) {
		var status_color = {
			"Draft": "red",
			"Submitted": "blue",
			"Cancelled": "red",
			"Closed": "green"
		};
		return [__(doc.status), status_color[doc.status], "status,=,"+doc.status];
	},
};
