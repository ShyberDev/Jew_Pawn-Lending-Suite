"""FIFO metal ledger for jewellery stock (Brick C).

Reads the submitted Jewellery Stock Transaction ledger and produces, per
Retail Stock Item + Purity bucket:

- a lot register: IN rows open lots, OUT rows consume the oldest lot first
  (FIFO) at the lot's rate;
- realised P&L per OUT row = OUT stock_value minus the FIFO cost of the
  consumed grams;
- valuation of the open stock at purchase cost (book value) plus the
  provisional (mark-to-market) P&L at the current metal rate.

Cost basis
----------
The lot rate is the JST ``rate_24k`` per gross gram, WITHOUT a purity
adjustment.  This deliberately mirrors the shop's own conventions used by the
invoices and the dashboard (metals priced at one rate per gram regardless of
alloy): purchase metal_value = chargeable_weight x rate_24k, dashboard
stock_value = gross grams x current metal rate.  As a result the report holds
the exact identity

    book_value + provisional = open_weight x current_rate   (per metal)

and for a bucket the realised total can be cross-checked as

    realised_total = open_book + out_metal_value - in_metal_value

where in/out metal value = weight x rate_24k.

Order-transfer OUT rows (``reference_type = Jewellery Order``) typically pair
with an identical Order-Transfer IN lot at rate 0 (goods delivered straight
to a customer); FIFO consumes that zero-rate lot first, so they net to zero
realised.  If an order transfer OUT ever lands ahead of a real purchase lot,
it will consume costed metal - the pairing convention prevents this: create
the transfer IN before any external OUT on the same bucket.

Rounding follows the app-wide contract: weights half-up to 3 decimals,
money half-up to 2 decimals (never Python ``round`` at display time).
"""

from decimal import ROUND_HALF_UP, Decimal

import frappe
from frappe.utils import flt


def round3(value):
    """Weights: round half-up to 3 decimals."""
    return Decimal(str(value)).quantize(
        Decimal("0.001"), rounding=ROUND_HALF_UP
    )


def round2(value):
    """Money: round half-up to 2 decimals."""
    return Decimal(str(value)).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_UP
    )


def fmt(value):
    """Display helper: float or number string (keep integers whole)."""
    if value is None:
        return None
    d = Decimal(str(value))
    if d == d.to_integral_value():
        return int(d)
    return float(d)


def get_current_metal_rates():
    """
    Latest active Metal Rate per metal - exactly the same rule the dashboard
    uses for stock_value (ORDER BY rate_date DESC LIMIT 1, active=1).
    """
    rates = {}
    for metal in ("Gold", "Silver"):
        r = frappe.db.sql(
            """SELECT rate_per_gram FROM `tabMetal Rate`
               WHERE metal=%s AND active=1
               ORDER BY rate_date DESC LIMIT 1""",
            metal,
        )
        rates[metal] = flt(r[0][0]) if r else 0
    return rates


def bucket_rows(retail_stock_item, purity, as_of=None):
    """
    Submitted JST rows for one bucket in ledger order
    (transaction_date, then name for deterministic FIFO).
    """
    filters = {
        "retail_stock_item": retail_stock_item,
        "purity": purity,
        "docstatus": 1,
    }
    rows = frappe.get_all(
        "Jewellery Stock Transaction",
        filters=filters,
        fields=[
            "name",
            "transaction_date",
            "transaction_type",
            "reference_type",
            "reference_no",
            "movement",
            "weight",
            "rate_24k",
            "stock_value",
        ],
        order_by="transaction_date asc, name asc",
    )
    if as_of:
        rows = [
            r for r in rows
            if str(r.transaction_date) <= str(as_of)
        ]
    return rows


def fifo_process(rows, current_rate):
    """
    Run FIFO over one bucket's rows (already in ledger order).

    Returns a dict with:
      rows            per-row ledger entries (dicts, report-ready)
      open_lots       remaining lots [{weight, rate, name, date}]
      open_weight     sum of remaining lot weight (round3)
      book_value      open stock at purchase cost (round2)
      provisional     open weight x (current_rate - lot rate) (round2)
      realised_total  sum of OUT realised (round2)
      current_rate    rate used for provisional (round2)
    """
    lots = []           # FIFO queue of open lots
    ledger = []
    realised_total = Decimal("0")

    for r in rows:
        weight = Decimal(str(flt(r.weight)))
        rate = Decimal(str(flt(r.rate_24k or 0)))
        stock_value = Decimal(str(flt(r.stock_value or 0)))

        entry = {
            "date": r.transaction_date,
            "jst": r.name,
            "reference": "%s: %s" % (r.reference_type, r.reference_no),
            "transaction_type": r.transaction_type,
            "movement": r.movement,
            "weight": round3(weight),
            "rate": round2(rate),
            "metal_value": round2(weight * rate),
            "stock_value": round2(stock_value),
            "lot_rate": None,
            "fifo_cost": None,
            "realised": None,
            "balance": None,
        }

        if r.movement == "In":
            lots.append(
                {
                    "weight": weight,
                    "rate": rate,
                    "name": r.name,
                    "date": r.transaction_date,
                }
            )
        else:  # Out: consume oldest lot(s) first
            consume = weight
            fifo_cost = Decimal("0")
            lot_weighted_rate = Decimal("0")

            while consume > Decimal("0.0000001") and lots:
                lot = lots[0]
                take = min(consume, lot["weight"])
                fifo_cost += take * lot["rate"]
                lot_weighted_rate += take * lot["rate"]
                lot["weight"] = round3(lot["weight"] - take)
                consume = round3(consume - take)
                if lot["weight"] <= Decimal("0.0000001"):
                    lots.pop(0)

            if consume > Decimal("0.0000001"):
                # no open lot cover (should not happen under normal flow):
                # value the uncovered grams at the current rate
                fifo_cost += consume * Decimal(str(current_rate))
                lot_weighted_rate += consume * Decimal(str(current_rate))

            entry["lot_rate"] = round2(
                (lot_weighted_rate / weight) if weight else Decimal("0")
            )
            entry["fifo_cost"] = round2(fifo_cost)
            entry["realised"] = round2(stock_value - fifo_cost)
            realised_total += entry["realised"]

        entry["balance"] = round3(
            sum(lot["weight"] for lot in lots)
        )
        ledger.append(entry)

    open_lots = [lot for lot in lots if lot["weight"] > Decimal("0.0000001")]
    open_weight = round3(sum(lot["weight"] for lot in open_lots))
    book_value = round2(
        sum(lot["weight"] * lot["rate"] for lot in open_lots)
    )
    provisional = round2(
        sum(
            lot["weight"] * (Decimal(str(current_rate)) - lot["rate"])
            for lot in open_lots
        )
    )

    return {
        "rows": ledger,
        "open_lots": open_lots,
        "open_weight": open_weight,
        "book_value": book_value,
        "provisional": provisional,
        "realised_total": round2(realised_total),
        "current_rate": round2(current_rate),
    }


def _bucket_metal_map():
    return {
        p.name: p.metal
        for p in frappe.get_all(
            "Metal Purity",
            fields=["name", "metal"],
        )
    }


def fifo_all(as_of=None, retail_stock_item=None, purity=None):
    """
    FIFO ledger + valuation for every non-empty bucket, plus grand totals.

    Filters (optional) narrow the bucket list; ``as_of`` limits rows to
    transaction_date <= as_of for every processed bucket.
    """
    where = ["docstatus = 1"]
    values = []
    if retail_stock_item:
        where.append("retail_stock_item = %s")
        values.append(retail_stock_item)
    if purity:
        where.append("purity = %s")
        values.append(purity)

    buckets = frappe.db.sql(
        """SELECT DISTINCT retail_stock_item rsi, purity
           FROM `tabJewellery Stock Transaction`
           WHERE %s
           ORDER BY rsi, purity"""
        % " AND ".join(where),
        values,
        as_dict=True,
    )

    rates = get_current_metal_rates()
    metal_map = _bucket_metal_map()
    results = []

    for b in buckets:
        metal = metal_map.get(b.purity, "Gold")
        current_rate = rates.get(metal, 0)
        rows = bucket_rows(b.rsi, b.purity, as_of)
        if not rows:
            continue
        processed = fifo_process(rows, current_rate)
        results.append(
            {
                "retail_stock_item": b.rsi,
                "purity": b.purity,
                "metal": metal,
                "current_rate": processed["current_rate"],
                "rows": processed["rows"],
                "open_weight": processed["open_weight"],
                "open_lots_count": len(processed["open_lots"]),
                "book_value": processed["book_value"],
                "provisional": processed["provisional"],
                "realised_total": processed["realised_total"],
            }
        )

    gold_open = silver_open = Decimal("0")
    gold_book = silver_book = Decimal("0")
    gold_prov = silver_prov = Decimal("0")
    total_book = Decimal("0")
    total_prov = Decimal("0")
    total_realised = Decimal("0")
    total_open = Decimal("0")

    for res in results:
        total_open += res["open_weight"]
        total_book += res["book_value"]
        total_prov += res["provisional"]
        total_realised += res["realised_total"]
        if res["metal"] == "Silver":
            silver_open += res["open_weight"]
            silver_book += res["book_value"]
            silver_prov += res["provisional"]
        else:
            gold_open += res["open_weight"]
            gold_book += res["book_value"]
            gold_prov += res["provisional"]

    totals = {
        "open_weight": round3(total_open),
        "book_value": round2(total_book),
        "provisional": round2(total_prov),
        "realised_total": round2(total_realised),
        "gold": {
            "open_weight": round3(gold_open),
            "book_value": round2(gold_book),
            "provisional": round2(gold_prov),
            "current_rate": rates.get("Gold", 0),
        },
        "silver": {
            "open_weight": round3(silver_open),
            "book_value": round2(silver_book),
            "provisional": round2(silver_prov),
            "current_rate": rates.get("Silver", 0),
        },
    }

    return {
        "buckets": results,
        "totals": totals,
        "rates": rates,
    }


@frappe.whitelist()
def fifo_valuation(as_of=None):
    """
    Lightweight valuation snapshot (for the dashboard / portal):
    open weight, book value, realised and provisional P&L per metal.
    """
    data = fifo_all(as_of=as_of)
    return {
        "as_of": as_of,
        "rates": data["rates"],
        "totals": data["totals"],
    }