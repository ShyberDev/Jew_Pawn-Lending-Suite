"""Rare-occasion repair tokens: balance math only, no workflow engine."""

import frappe
from frappe.utils import flt


def validate_repair(doc, method=None):
    balance = flt(doc.estimate) - flt(doc.advance)
    if balance < 0:
        frappe.throw("Advance cannot exceed Estimate.")
    doc.balance = balance
