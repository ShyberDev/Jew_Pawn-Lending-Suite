import frappe


def has_app_permission():
	"""Show the Pawn Shop app on the apps screen to logged-in users who can read pawn data."""
	if frappe.session.user == "Guest":
		return False
	return bool(frappe.has_permission("Pawn Loan", "read"))
