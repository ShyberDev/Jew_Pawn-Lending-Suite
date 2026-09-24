"""Offline-first mobile sync API for the Jewellery / Pawn / Lending suite.

Design: docs/MOBILE_SYNC_DESIGN.md

The Android (Flutter) app stores data locally and talks to these endpoints:

    register_device(device_name, platform)  -> { device, server_time }
    pull(since, doctypes, limit)            -> { server_time, docs }
    push(mutations, device)                 -> { server_time, results }
    status()                                -> { server_time, doctypes, ... }

Idempotency
-----------
Every client-created document carries a ``client_uuid``. The mapping
``client_uuid -> (reference_doctype, reference_name)`` is stored in the
``Sync ID Map`` doctype, so a retried ``push`` returns the already-created
document instead of creating a duplicate.

Permissions
-----------
Every read/write is checked with ``frappe.has_permission`` for the logged-in
user, exactly like the desk. A phone can only sync what its user may access.
"""

import json

import frappe
from frappe import _
from frappe.utils import get_datetime, now_datetime

# --------------------------------------------------------------------------- #
# Registry: DocTypes the phone may sync, and their sync semantics.
#   "transaction" = append-only, submittable (create / read only)
#   "master"      = editable, last-write-wins
# --------------------------------------------------------------------------- #
SYNC_DOCTYPES = {
	"Village": "master",
	"Business": "master",
	"Pawn Customer": "master",
	"Pawn Loan": "transaction",
	"Pawn Release": "transaction",
	"Khatabook Loan": "transaction",
	"Khatabook Collection": "transaction",
	"Khatabook Refinance": "transaction",
	"Jewellery Order": "transaction",
	"Jewellery Sales Invoice": "transaction",
	"Jewellery Purchase Invoice": "transaction",
}

# Fields the server always owns; never accept them from a client.
_SERVER_FIELDS = {
	"name", "owner", "creation", "modified", "modified_by", "docstatus",
	"idx", "parent", "parentfield", "parenttype", "doctype",
	"_user_tags", "_comments", "_assign", "_liked_by",
}

_MAX_PULL_LIMIT = 500


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def _as_json(value):
	"""whitelisted methods may receive JSON as a string (form data) or object."""
	if isinstance(value, str):
		try:
			return json.loads(value)
		except (ValueError, TypeError):
			return value
	return value


def _require_login():
	if frappe.session.user == "Guest":
		frappe.throw(_("Login required"), frappe.AuthenticationError)


def _check_enabled(doctype):
	if doctype not in SYNC_DOCTYPES:
		frappe.throw(
			_("{0} is not enabled for mobile sync").format(doctype),
			frappe.ValidationError,
		)


def _clean_data(doctype, data):
	"""Keep only real, client-writable fields of ``doctype`` (incl. child tables)."""
	data = _as_json(data) or {}
	if not isinstance(data, dict):
		frappe.throw(_("data must be an object"))
	meta = frappe.get_meta(doctype)
	valid = {df.fieldname for df in meta.fields if df.fieldname}
	clean = {}
	for key, value in data.items():
		if key in _SERVER_FIELDS or key not in valid:
			continue
		clean[key] = value
	return clean


def _touch_device(device):
	if device and frappe.db.exists("Sync Device", device):
		frappe.db.set_value("Sync Device", device, "last_sync", now_datetime(), update_modified=False)


def _log(device, direction, doctype, count, results=None):
	results = results or []
	errors = [r for r in results if r.get("status") == "error"]
	if not results:
		status = "Success"
	elif len(errors) == len(results):
		status = "Error"
	elif errors:
		status = "Partial"
	else:
		status = "Success"
	try:
		frappe.get_doc(
			{
				"doctype": "Sync Log",
				"device": device,
				"direction": direction,
				"reference_doctype": doctype,
				"count": count,
				"status": status,
				"error": "\n".join(r.get("error", "") for r in errors)[:2000],
			}
		).insert(ignore_permissions=True)
		frappe.db.commit()
	except Exception:
		frappe.db.rollback()


# --------------------------------------------------------------------------- #
# endpoints
# --------------------------------------------------------------------------- #
@frappe.whitelist()
def register_device(device_name, platform=None):
	"""Register a phone and return its device id (used as ``device`` in push)."""
	_require_login()
	device = frappe.get_doc(
		{
			"doctype": "Sync Device",
			"device_name": device_name,
			"platform": platform or "android",
			"user": frappe.session.user,
			"enabled": 1,
		}
	).insert(ignore_permissions=True)
	return {"device": device.name, "server_time": now_datetime()}


@frappe.whitelist()
def status(device=None):
	"""Server time + the DocTypes this user may sync."""
	_require_login()
	allowed = [dt for dt in SYNC_DOCTYPES if frappe.has_permission(dt, "read")]
	return {
		"server_time": now_datetime(),
		"user": frappe.session.user,
		"doctypes": allowed,
		"registry": {dt: SYNC_DOCTYPES[dt] for dt in allowed},
	}


@frappe.whitelist()
def pull(since=None, doctypes=None, limit=200):
	"""Return full documents (incl. child tables) modified after ``since``."""
	_require_login()
	try:
		limit = min(int(limit or 200), _MAX_PULL_LIMIT)
	except (TypeError, ValueError):
		limit = 200

	wanted = _as_json(doctypes) or list(SYNC_DOCTYPES)
	since = get_datetime(since) if since else None
	server_time = now_datetime()

	docs = {}
	for doctype in wanted:
		if doctype not in SYNC_DOCTYPES or not frappe.has_permission(doctype, "read"):
			continue
		filters = [["modified", ">", since]] if since else []
		names = frappe.get_list(
			doctype,
			filters=filters,
			pluck="name",
			limit_page_length=limit,
			order_by="modified asc",
		)
		rows = []
		for name in names:
			try:
				rows.append(frappe.get_doc(doctype, name).as_dict())
			except frappe.PermissionError:
				continue
		docs[doctype] = rows

	return {"server_time": server_time, "docs": docs}


@frappe.whitelist()
def push(mutations, device=None):
	"""Apply a batch of client mutations idempotently.

	Each mutation::

	    {
	      "op": "create" | "update",
	      "doctype": "Pawn Loan",
	      "client_uuid": "…uuid…",
	      "submit": true,          # optional, transactions only
	      "data": { …fields… }
	    }
	"""
	_require_login()
	mutations = _as_json(mutations) or []
	if isinstance(mutations, dict):
		mutations = [mutations]

	results = []
	for index, mutation in enumerate(mutations):
		mutation = _as_json(mutation)
		client_uuid = mutation.get("client_uuid")
		doctype = mutation.get("doctype")
		op = (mutation.get("op") or "create").lower()
		data = mutation.get("data") or {}
		savepoint = f"sync_push_{index}"
		frappe.db.savepoint(savepoint)
		try:
			_check_enabled(doctype)
			if op == "create":
				name = _create(doctype, client_uuid, data, device, submit=bool(mutation.get("submit")))
				results.append({"client_uuid": client_uuid, "server_name": name, "status": "created"})
			elif op == "update":
				name = _update(doctype, client_uuid, data)
				results.append({"client_uuid": client_uuid, "server_name": name, "status": "updated"})
			else:
				raise frappe.ValidationError(_("Unknown op: {0}").format(op))
		except Exception as error:
			frappe.db.rollback(save_point=savepoint)
			results.append({"client_uuid": client_uuid, "status": "error", "error": str(error)})

	frappe.db.commit()
	_touch_device(device)
	_log(device, "Push", None, len(mutations), results)
	return {"server_time": now_datetime(), "results": results}


# --------------------------------------------------------------------------- #
# internals
# --------------------------------------------------------------------------- #
def _create(doctype, client_uuid, data, device, submit=False):
	if client_uuid:
		existing = frappe.db.get_value(
			"Sync ID Map", {"client_uuid": client_uuid}, "reference_name"
		)
		if existing:
			return existing

	if not frappe.has_permission(doctype, "create"):
		frappe.throw(_("Not permitted to create {0}").format(doctype), frappe.PermissionError)

	doc = frappe.get_doc({"doctype": doctype, **_clean_data(doctype, data)})
	doc.insert()

	if submit and doc.meta.is_submittable and doc.docstatus == 0:
		doc.submit()

	if client_uuid:
		_map_uuid(client_uuid, doctype, doc.name, device)
	return doc.name


def _update(doctype, client_uuid, data):
	name = None
	if client_uuid:
		name = frappe.db.get_value("Sync ID Map", {"client_uuid": client_uuid}, "reference_name")
	name = name or _as_json(data).get("name")
	if not name:
		frappe.throw(_("update needs a client_uuid or a name"))

	if not frappe.has_permission(doctype, "write", doc=name):
		frappe.throw(_("Not permitted to edit {0}").format(name), frappe.PermissionError)

	doc = frappe.get_doc(doctype, name)
	if doc.meta.is_submittable and doc.docstatus != 0:
		frappe.throw(_("Submitted {0} cannot be edited").format(doctype))
	doc.update(_clean_data(doctype, data))
	doc.save()
	return doc.name


def _map_uuid(client_uuid, doctype, name, device):
	if frappe.db.exists("Sync ID Map", client_uuid):
		return
	frappe.get_doc(
		{
			"doctype": "Sync ID Map",
			"client_uuid": client_uuid,
			"reference_doctype": doctype,
			"reference_name": name,
			"device": device,
		}
	).insert(ignore_permissions=True)
