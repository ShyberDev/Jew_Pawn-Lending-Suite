"""
Server-side totals mirror.

Replicates the exact client-side calculation scripts so that totals cannot be
bypassed through the API / bulk import / desk footguns:

- Jewellery Sales Invoice    : Jewellery_Sales_Invoice_-_Calculations.js
- Jewellery Purchase Invoice : Jewellery_Purchase_Invoice_-_Calculations.js
- Jewellery Order            : Jewellery_Order_calculation.js
- Jewellery Opening Stock    : Jewellery_Opening_Stock_-_Calculations.js

Rounding contract (must never drift from the JS):
- Money always rounds UP (Math.ceil) -> whole rupees.
- Weights round half-up to 3 decimals (JS Math.round((x+EPSILON)*1000)/1000).
- GST / rupee-paise uses flt(x, 2) which is round half-up to 2 decimals.
  Python's round() is banker's rounding, so it is never used here.
"""

import math

import frappe


# ---------------------------------------------------------------------------
# rounding helpers
# ---------------------------------------------------------------------------

def flt(value, default=0.0):
    """JS flt() equivalent: NaN / None / empty become 0."""
    try:
        value = float(value)
        if math.isnan(value):
            return default
        return value
    except (TypeError, ValueError):
        return default


def round3(value):
    """JS Math.round((x + EPSILON) * 1000) / 1000 — half-up, 3 decimals."""
    return math.floor(value * 1000 + 0.5) / 1000


def flt2(value):
    """JS flt(x, 2) — round half-up to 2 decimals."""
    return math.floor(value * 100 + 0.5) / 100


def ceil_money(value):
    """JS Math.ceil on money."""
    return math.ceil(value)


# ---------------------------------------------------------------------------
# JEWELLERY SALES INVOICE
# ---------------------------------------------------------------------------

def _calc_sales_item(item):
    weight = flt(item.get("net_weight"))
    if weight <= 0:
        weight = flt(item.get("gross_weight"))

    wastage = flt(item.get("wastage_percentage"))
    chargeable_weight = round3(weight * (1 + wastage / 100))

    pure_rate = flt(item.get("rate_24k"))
    metal_value = ceil_money(chargeable_weight * pure_rate)

    making = flt(item.get("making_charges"))
    total_amount = ceil_money(metal_value + making)

    item.chargeable_weight = chargeable_weight
    item.metal_value = metal_value
    item.total_amount = total_amount


def _sales_payments_total(doc):
    total = 0.0
    for payment in doc.get("payments") or []:
        total += flt(payment.get("amount"))
    return ceil_money(total)


def compute_sales_summary(doc):
    """Pure recomputation; returns dict of parent field -> value."""
    gross_total_weight = 0.0
    net_total_weight = 0.0
    total_chargeable_weight = 0.0
    total_metal_value = 0.0
    total_making_charges = 0.0

    for row in doc.get("items") or []:
        gross_total_weight += flt(row.get("gross_weight"))

        net_weight = flt(row.get("net_weight"))
        if net_weight <= 0:
            net_weight = flt(row.get("gross_weight"))
        net_total_weight += net_weight

        total_chargeable_weight += flt(row.get("chargeable_weight"))
        total_metal_value += flt(row.get("metal_value"))
        total_making_charges += flt(row.get("making_charges"))

    gross_total_weight = round3(gross_total_weight)
    net_total_weight = round3(net_total_weight)
    total_chargeable_weight = round3(total_chargeable_weight)
    total_metal_value = ceil_money(total_metal_value)
    total_making_charges = ceil_money(total_making_charges)

    subtotal = ceil_money(total_metal_value + total_making_charges)

    gst_rate = flt(doc.get("gst_rate"))
    gst_amount = flt2(subtotal * gst_rate / 100)

    old_gold_credit = flt(doc.get("old_gold_credit"))
    max_credit = subtotal + gst_amount
    if max_credit <= 0:
        # return (negative-bill) invoices can never carry an old-gold
        # credit; without this guard the clamp below would set the credit
        # to the negative max and zero out grand_total.
        old_gold_credit = 0
    elif old_gold_credit > max_credit:
        old_gold_credit = flt2(max_credit)

    grand_total = ceil_money(subtotal + gst_amount - old_gold_credit)

    total_paid = _sales_payments_total(doc)
    balance_amount = max(0, grand_total - total_paid)
    balance_amount = ceil_money(balance_amount)

    tcs_amount = _compute_tcs_amount(doc, grand_total)

    return {
        "gross_total_weight": gross_total_weight,
        "net_total_weight": net_total_weight,
        "total_chargeable_weight": total_chargeable_weight,
        "total_metal_value": total_metal_value,
        "total_making_charges": total_making_charges,
        "subtotal": subtotal,
        "gst_amount": gst_amount,
        "old_gold_credit": old_gold_credit,
        "grand_total": grand_total,
        "tcs_amount": tcs_amount,
        "total_paid": total_paid,
        "balance_amount": balance_amount,
    }


def _compute_tcs_amount(doc, grand_total):
    """
    TCS on sales above a threshold (settings-driven, default 0.1% above
    5,00,000 as per 206C(1H) style collection). Whole-rupee (ceil).

    Mirrors the client-side calculate_sales(): a return (negative-bill)
    invoice never carries TCS.
    """

    if flt(grand_total) <= 0:
        return 0.0

    try:
        settings = frappe.get_doc("Jewellery Settings")
        threshold = flt(settings.get("tcs_threshold"))
        if threshold <= 0:
            threshold = 500000
        rate = flt(settings.get("tcs_rate"))
        if rate <= 0:
            rate = 0.1
    except Exception:
        threshold = 500000
        rate = 0.1

    if flt(grand_total) < threshold:
        return 0.0

    # Allow per-invoice override via the linked field if the user set it.
    rate = flt(doc.get("tcs_rate")) or rate

    return ceil_money(flt(grand_total) * rate / 100)


def _autofill_old_gold_credit(doc):
    """Mirror of client autofill_old_gold_credit()."""
    if not doc.get("old_gold_receipt"):
        return
    if flt(doc.get("old_gold_credit")) > 0:
        return

    credit = 0.0
    try:
        value = frappe.db.get_value(
            "Old Gold Receipt", doc.get("old_gold_receipt"), "credit_amount"
        )
        if value is not None:
            credit = flt(value)
    except Exception:
        credit = 0.0

    if credit > 0:
        doc.old_gold_credit = credit


def recalc_sales_invoice(doc, method=None):
    """validate hook — recompute item maths and parent totals in place."""
    for item in doc.get("items") or []:
        _calc_sales_item(item)

    _autofill_old_gold_credit(doc)

    summary = compute_sales_summary(doc)
    for field, value in summary.items():
        doc.set(field, value)


# ---------------------------------------------------------------------------
# JEWELLERY PURCHASE INVOICE
# ---------------------------------------------------------------------------

def _calc_purchase_item(item):
    weight = flt(item.get("net_weight"))
    if weight <= 0:
        weight = flt(item.get("gross_weight"))

    purity = flt(item.get("purity_percentage"))
    wastage = flt(item.get("wastage_percentage"))
    pure_weight_24k = round3(weight * (purity + wastage) / 100)

    pure_rate = flt(item.get("rate_24k"))
    metal_value = ceil_money(pure_weight_24k * pure_rate)

    making = flt(item.get("making_charges"))
    stone = flt(item.get("stone_charges"))
    other = flt(item.get("other_charges"))
    total_amount = ceil_money(metal_value + making + stone + other)

    item.pure_weight_24k = pure_weight_24k
    item.metal_value = metal_value
    item.total_amount = total_amount


def compute_purchase_summary(doc):
    """Pure recomputation; returns dict of parent field -> value."""
    gross_total_weight = 0.0
    net_total_weight = 0.0
    total_pure_weight_24k = 0.0
    total_metal_value = 0.0
    total_making_charges = 0.0
    total_stone_charges = 0.0
    total_other_charges = 0.0

    for row in doc.get("items") or []:
        gross_total_weight += flt(row.get("gross_weight"))

        net_weight = flt(row.get("net_weight"))
        if net_weight <= 0:
            net_weight = flt(row.get("gross_weight"))
        net_total_weight += net_weight

        total_pure_weight_24k += flt(row.get("pure_weight_24k"))
        total_metal_value += flt(row.get("metal_value"))
        total_making_charges += flt(row.get("making_charges"))
        total_stone_charges += flt(row.get("stone_charges"))
        total_other_charges += flt(row.get("other_charges"))

    gross_total_weight = round3(gross_total_weight)
    net_total_weight = round3(net_total_weight)
    total_pure_weight_24k = round3(total_pure_weight_24k)
    total_metal_value = ceil_money(total_metal_value)
    total_making_charges = ceil_money(total_making_charges)
    total_stone_charges = ceil_money(total_stone_charges)
    total_other_charges = ceil_money(total_other_charges)

    subtotal = ceil_money(
        total_metal_value
        + total_making_charges
        + total_stone_charges
        + total_other_charges
    )

    gst_rate = flt(doc.get("gst_rate"))
    gst = flt2(subtotal * gst_rate / 100)

    grand_total = ceil_money(subtotal + gst)

    total_paid = 0.0
    for payment in doc.get("payments") or []:
        total_paid += flt(payment.get("amount"))
    total_paid = ceil_money(total_paid)

    balance_amount = max(0, grand_total - total_paid)
    balance_amount = ceil_money(balance_amount)

    return {
        "gross_total_weight": gross_total_weight,
        "net_total_weight": net_total_weight,
        "total_pure_weight_24k": total_pure_weight_24k,
        "total_metal_value": total_metal_value,
        "total_making_charges": total_making_charges,
        "total_stone_charges": total_stone_charges,
        "total_other_charges": total_other_charges,
        "subtotal": subtotal,
        "gst": gst,
        "grand_total": grand_total,
        "total_paid": total_paid,
        "balance_amount": balance_amount,
    }


def recalc_purchase_invoice(doc, method=None):
    """validate hook — recompute item maths and parent totals in place."""
    for item in doc.get("items") or []:
        _calc_purchase_item(item)

    summary = compute_purchase_summary(doc)
    for field, value in summary.items():
        doc.set(field, value)


# ---------------------------------------------------------------------------
# JEWELLERY OPENING STOCK
# ---------------------------------------------------------------------------

def compute_opening_summary(doc):
    total_weight = 0.0
    total_value = 0.0
    for row in doc.get("items") or []:
        weight = flt(row.get("weight"))
        rate = flt(row.get("rate"))
        total_weight += weight
        total_value += weight * rate
    return {
        "total_opening_weight": round3(total_weight),
        "total_opening_value": ceil_money(total_value),
    }


def recalc_opening_stock(doc, method=None):
    """validate hook — recompute opening totals in place."""
    summary = compute_opening_summary(doc)
    for field, value in summary.items():
        doc.set(field, value)


# ---------------------------------------------------------------------------
# JEWELLERY ORDER
# ---------------------------------------------------------------------------

def _order_item_idxs(doc):
    return {row.idx for row in doc.get("jewellery_items") or []}


def _charge_item_list(charge, valid_idxs):
    """JS charge_item_list(): '1,2,3' -> [1,2,3] filtered by valid idxs."""
    raw = (charge.get("applicable_items") or "").strip()
    if not raw or raw == "0":
        return []
    out = []
    for part in raw.split(","):
        try:
            n = int(str(part).strip())
        except (TypeError, ValueError):
            continue
        if n in valid_idxs and n not in out:
            out.append(n)
    return out


def _calc_order_customer_side(item):
    net_weight = flt(item.get("net_weight"))
    if net_weight <= 0 and flt(item.get("gross_weight")) > 0:
        net_weight = flt(item.get("gross_weight"))
        item.net_weight = round3(net_weight)

    wastage = flt(item.get("wastage_percentage"))
    rate = flt(item.get("rate_per_gram"))
    making = flt(item.get("making_charges"))
    hallmark = flt(item.get("hallmark_charges"))
    other = flt(item.get("other_charges"))

    # NOTE: equivalent_weight is NOT rounded before money maths
    # (only the stored value is rounded to 3dp).
    equivalent_weight = net_weight * (100 + wastage) / 100
    metal_value = equivalent_weight * rate
    quoted_amount = ceil_money(metal_value + making + hallmark + other)

    item.equivalent_weight = round3(equivalent_weight)
    item.quoted_amount = quoted_amount
    item.total_amount = quoted_amount


def _calc_order_worker_side(item):
    metal_weight = flt(item.get("worker_metal_weight"))
    purity = flt(item.get("worker_purity_percentage")) or 92

    pure_weight = metal_weight * purity / 100

    wastage_percentage = flt(item.get("worker_wastage_percentage"))
    wastage_weight = flt(item.get("worker_wastage_weight"))

    if wastage_percentage > 0:
        equivalent_weight = metal_weight * (purity + wastage_percentage) / 100
    elif wastage_weight > 0:
        equivalent_weight = pure_weight + wastage_weight
    else:
        equivalent_weight = pure_weight

    biscuit_rate = flt(item.get("worker_biscuit_rate"))
    metal_value = equivalent_weight * biscuit_rate

    hallmark = flt(item.get("worker_hallmark_charges"))
    document = flt(item.get("worker_document_charges"))
    travel = flt(item.get("worker_travel_charges"))
    other = flt(item.get("worker_other_charges"))

    total_worker_cost = metal_value + hallmark + document + travel + other

    item.worker_pure_weight = round3(pure_weight)
    item.worker_equivalent_weight = round3(equivalent_weight)
    item.worker_metal_value = ceil_money(metal_value)
    item.worker_total_cost = ceil_money(total_worker_cost)


def _set_worker_charge_summaries(doc, item, charges):
    """JS set_worker_charge_summaries(): roll single-item charges into item."""
    hallmark = 0.0
    document = 0.0
    travel = 0.0
    other = 0.0

    for charge in charges:
        amount = flt(charge.get("amount"))
        if amount <= 0:
            continue
        charge_type = charge.get("charge_type")
        if charge_type == "Hallmark":
            hallmark += amount
        elif charge_type == "Certificate / Document":
            document += amount
        elif charge_type == "Bus / Travel":
            travel += amount
        else:
            other += amount

    item.worker_hallmark_charges = flt2(hallmark)
    item.worker_document_charges = flt2(document)
    item.worker_travel_charges = flt2(travel)
    item.worker_other_charges = flt2(other)

    _calc_order_worker_side(item)


def _calc_all_worker_other_charge_totals(doc):
    valid = _order_item_idxs(doc)
    all_charges = doc.get("worker_other_charge_details") or []

    for item in doc.get("jewellery_items") or []:
        charges = [
            c
            for c in all_charges
            if _charge_item_list(c, valid) == [item.idx]
        ]
        _set_worker_charge_summaries(doc, item, charges)


def compute_order_worker_total(doc):
    """JS update_order_worker_total(): item costs + shared/whole-order charges."""
    total = 0.0
    valid = _order_item_idxs(doc)
    for item in doc.get("jewellery_items") or []:
        total += flt(item.get("worker_total_cost"))
    for charge in doc.get("worker_other_charge_details") or []:
        if len(_charge_item_list(charge, valid)) != 1:
            total += flt(charge.get("amount"))
    return ceil_money(total)


def compute_order_summary(doc):
    """JS calculate_order_totals()."""
    subtotal = 0.0
    for row in doc.get("jewellery_items") or []:
        item_total = flt(row.get("total_amount")) + flt(
            row.get("delivery_amount_adjustment")
        )
        if item_total < 0:
            item_total = 0
        subtotal += item_total
    subtotal = ceil_money(subtotal)

    discount = ceil_money(flt(doc.get("discount")))
    grand_total = subtotal - discount
    if grand_total < 0:
        grand_total = 0

    total_paid = 0.0
    for payment in doc.get("payments") or []:
        total_paid += flt(payment.get("amount"))
    total_paid = ceil_money(total_paid)

    balance = grand_total - total_paid
    if balance < 0:
        balance = 0
    balance = ceil_money(balance)

    return {
        "subtotal": subtotal,
        "grand_total": grand_total,
        "advance_amount": total_paid,
        "balance_amount": balance,
    }


def _calc_order_delivery_amount(item):
    """JS calculate_delivery_amount(): final_amount field."""
    final_amount = flt(item.get("total_amount")) + flt(
        item.get("delivery_amount_adjustment")
    )
    if final_amount < 0:
        final_amount = 0
    item.final_amount = ceil_money(final_amount)


def recalc_order(doc, method=None):
    """validate hook — recompute order money maths in place."""
    for item in doc.get("jewellery_items") or []:
        _calc_order_customer_side(item)
        _calc_order_delivery_amount(item)
        _calc_order_worker_side(item)

    _calc_all_worker_other_charge_totals(doc)

    doc.total_worker_cost = compute_order_worker_total(doc)

    summary = compute_order_summary(doc)
    for field, value in summary.items():
        doc.set(field, value)

def add_boot_settings(bootinfo):
    """
    Inject Jewellery Settings into frappe.boot so the client-side sales
    calculator can mirror the server TCS threshold/rate without an extra
    round-trip.
    """

    settings = frappe.get_doc("Jewellery Settings")
    bootinfo.jewellery_settings_tcs_threshold = flt(settings.get("tcs_threshold")) or 500000
    bootinfo.jewellery_settings_tcs_rate = flt(settings.get("tcs_rate")) or 0.1
