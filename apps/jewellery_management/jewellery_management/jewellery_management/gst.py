"""
Brick E: GST filing support.

- TCS on sales above a settings-defined threshold (server mirror in
  calculations._compute_tcs_amount).
- GSTR-1 export: aggregated outward-supply rows in the GSTR-1 style
  (B2B by GSTIN, B2C without GSTIN, per-rate summaries).
- e-invoice JSON payload for a submitted Sales Invoice (IRN-style fields).

The GSTR-1 aggregates the submitted Jewellery Sales Invoice, with returns
(Brick D) netting against it like the GST Summary report does.
"""

import json

import frappe
from frappe import _
from frappe.utils import flt, formatdate, getdate


# ---------------------------------------------------------------------------
# rounding helpers (same contract as calculations.py)
# ---------------------------------------------------------------------------

def _ceil_money(value):
    import math
    try:
        return math.ceil(flt(value))
    except Exception:
        return 0


def _flt2(value):
    return round(flt(value) + 1e-9, 2)


# ---------------------------------------------------------------------------
# GSTR-1 export
# ---------------------------------------------------------------------------

def get_gstr1(from_date, to_date):
    """
    Return GSTR-1 style outward-supply aggregation for the period.

    Rows:
    - B2B: invoices with a customer GSTIN (net of returns)
    - B2C: invoices without a customer GSTIN
    - summary: per-rate totals (taxable, cgst, sgst, tcs, count)
    """

    invoices = frappe.get_all(
        "Jewellery Sales Invoice",
        filters=[
            ["docstatus", "=", 1],
            ["sales_date", ">=", from_date],
            ["sales_date", "<=", to_date],
        ],
        fields=[
            "name",
            "sales_date",
            "customer_gstin",
            "customer_name",
            "subtotal",
            "gst_rate",
            "gst_amount",
            "grand_total",
            "tcs_amount",
            "is_return",
        ],
        order_by="sales_date asc, name asc",
    )

    b2b = []
    b2c = []
    summary = {}

    for inv in invoices:
        taxable = flt(inv.subtotal)
        gst = flt(inv.gst_amount)
        tcs = flt(inv.tcs_amount)
        rate = flt(inv.gst_rate)

        row = {
            "invoice": inv.name,
            "date": formatdate(inv.sales_date),
            "party": inv.customer_name,
            "taxable": _ceil_money(taxable),
            "rate": rate,
            "cgst": _ceil_money(gst / 2),
            "sgst": _ceil_money(gst / 2),
            "tcs": _ceil_money(tcs),
            "grand_total": _ceil_money(flt(inv.grand_total)),
            "is_return": 1 if inv.is_return else 0,
        }

        # For summary only count returns net (negative) against B2C/B2B.
        target = b2b if (inv.customer_gstin and not inv.is_return) else (b2b if inv.customer_gstin else b2c)

        if inv.customer_gstin:
            row["gstin"] = inv.customer_gstin
            b2b.append(row)
        else:
            b2c.append(row)

        key = flt(rate)
        s = summary.setdefault(
            key,
            {
                "rate": key,
                "count": 0,
                "taxable": 0.0,
                "cgst": 0.0,
                "sgst": 0.0,
                "tcs": 0.0,
            },
        )
        s["count"] += 1
        s["taxable"] += flt(taxable)
        s["cgst"] += flt(gst / 2)
        s["sgst"] += flt(gst / 2)
        s["tcs"] += flt(tcs)

    summary_rows = []
    for key in sorted(summary):
        s = summary[key]
        s["taxable"] = _ceil_money(s["taxable"])
        s["cgst"] = _ceil_money(s["cgst"])
        s["sgst"] = _ceil_money(s["sgst"])
        s["tcs"] = _ceil_money(s["tcs"])
        summary_rows.append(s)

    return {
        "from_date": formatdate(from_date),
        "to_date": formatdate(to_date),
        "b2b": b2b,
        "b2c": b2c,
        "summary": summary_rows,
    }


@frappe.whitelist()
def gstr1_export(from_date, to_date):
    """API endpoint returning the GSTR-1 aggregation as JSON."""
    data = get_gstr1(from_date, to_date)
    return data


# ---------------------------------------------------------------------------
# e-invoice JSON payload
# ---------------------------------------------------------------------------

def get_einvoice_payload(sales_invoice):
    """
    Build an IRN-style e-invoice JSON payload for a submitted sales invoice.

    Seller GSTIN / business name come from Jewellery Settings; buyer GSTIN
    from the invoice. Item lines carry the invoice-level HSN (default 7113).
    """

    inv = frappe.get_doc("Jewellery Sales Invoice", sales_invoice)
    if inv.docstatus != 1:
        frappe.throw(_("e-invoice payload requires a submitted Sales Invoice"))

    settings = frappe.get_doc("Jewellery Settings")
    seller_gstin = (settings.get("gstin") or "").strip()
    seller_name = (settings.get("shop_name") or inv.company or "Sri Sai Krishna Jewellery").strip()

    hsn = (inv.get("hsn_code") or "7113").strip()

    items = []
    for row in inv.items:
        items.append(
            {
                "SlNo": len(items) + 1,
                "Item": (row.item_name or ""),
                "Qty": flt(row.net_weight),
                "Unit": "GMS",
                "HSN": hsn,
                "TaxableAmount": _flt2(flt(row.total_amount)),
                "Rate": flt(row.rate_24k),
                "Amount": _flt2(flt(row.total_amount)),
            }
        )

    taxable = _flt2(flt(inv.subtotal))
    gst = _flt2(flt(inv.gst_amount))
    cgst = _flt2(gst / 2)
    sgst = _flt2(gst / 2)
    igst = _flt2(0.0)

    payload = {
        "Version": "1.09",
        "TranDtls": {
            "TaxSch": "GST",
            "SupTyp": "B2CS" if not inv.customer_gstin else "B2B",
            "RegRev": "N",
            "EcmGstin": "",
            "IgstOnIntra": "N",
        },
        "DocDtls": {
            "Typ": "INV",
            "No": inv.name,
            "Dt": str(getdate(inv.sales_date)),
        },
        "SellerDtls": {
            "Gstin": seller_gstin,
            "LglNm": seller_name,
        },
        "BuyerDtls": {
            "Gstin": inv.customer_gstin or "",
            "LglNm": inv.customer_name or "",
        },
        "ItemList": items,
        "ValDtls": {
            "AssVal": taxable,
            "CgstVal": cgst,
            "SgstVal": sgst,
            "IgstVal": igst,
            "TotInvVal": _flt2(flt(inv.grand_total)),
        },
        "PayDtls": {
            "Nm": "",
            "Mode": "",
            "FinInsBr": "",
            "PayTerm": "",
            "PaidAmt": _flt2(flt(inv.grand_total)),
            "PaymtDue": _flt2(0.0),
        },
    }

    return payload


@frappe.whitelist()
def einvoice_payload(sales_invoice):
    """API endpoint returning the e-invoice JSON payload."""
    return get_einvoice_payload(sales_invoice)