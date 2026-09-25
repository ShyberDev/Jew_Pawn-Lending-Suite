#!/usr/bin/env python3
"""
export_excel.py — Excel exports + change-fingerprint for Jewellery Suite.

Runs against a Frappe bench site DIRECTLY through its database (safe read-only
extracts; nothing is ever written back to the site DB).

Produces (in the backup/exports directory):
  <STAMP>_full.xlsx   — every non-empty table in the site database (complete snapshot)
  <STAMP>_khata.xlsx  — money-lending module (khatabook loans/installments/collections/refinance)
  <STAMP>_pawn.xlsx   — pawn module (pawn loans/items/release/customers + villages + businesses)
  <STAMP>_customers.xlsx — customer & village master (shared reference file, good for sharing)

And a fingerprint sub-command that lets the backup script SKIP a run when the
data has not changed since the last backup (no duplicate backups on Drive).

Usage (from the bench root, with the bench python environment):
  env/bin/python tools/export_excel.py export --site library.local \
      --out sites/library.local/backups --stamp 20260925_161500
  env/bin/python tools/export_excel.py fingerprint --site library.local

The backup script calls both automatically.
"""
import argparse
import hashlib
import json
import os
import sys

import MySQLdb

# Tables whose content is part of the Khata (money-lending) module.
KHATA_TABLES = (
    "tabKhatabook Loan",
    "tabKhatabook Installment",
    "tabKhatabook Collection",
    "tabKhatabook Refinance",
)

# Tables that belong to the Pawn module.
PAWN_TABLES = (
    "tabPawn Loan",
    "tabPawn Item",
    "tabPawn Release",
    "tabPawn Customer",
)

# Shared master data used by both modules.
MASTER_TABLES = (
    "tabVillage",
    "tabBusiness",
)

# Sync machinery — kept out of the shareable module files, included in FULL.
SYNC_TABLES = (
    "tabSync Device",
    "tabSync ID Map",
    "tabSync Log",
)

MODULES = {
    "full": None,  # all non-empty tables
    "khata": KHATA_TABLES,
    "pawn": PAWN_TABLES,
    "customers": MASTER_TABLES,
}

# Frappe bookkeeping tables that should never appear in shared/export files
# (auth secrets, cache, session noise). Still present in the FULL DB snapshot
# via the database backup itself.
_PRIVATE_PREFIXES = (
    "__",
    "tabDefaultValue",
    "tabSession Default",
    "tabError Log",
)


def connect(site_dir):
    site_config = json.load(open(os.path.join(site_dir, "site_config.json")))
    return MySQLdb.connect(
        host=site_config.get("host_name") or "127.0.0.1",
        port=int(site_config.get("db_port", 3306)),
        user=site_config["db_user"],
        passwd=site_config["db_password"],
        db=site_config["db_name"],
        charset="utf8mb4",
    )


def table_names(conn):
    cur = conn.cursor()
    cur.execute("SHOW TABLES")
    return sorted(r[0] for r in cur.fetchall())


def column_names(conn, table):
    cur = conn.cursor()
    cur.execute("SHOW COLUMNS FROM `%s`" % table.replace("`", "``"))
    return [r[0] for r in cur.fetchall()]


def fetch_rows(conn, table, cap=200000):
    cur = conn.cursor()
    cur.execute("SELECT * FROM `%s`" % table.replace("`", "``"))
    rows = []
    truncated = False
    for i, row in enumerate(cur.fetchall()):
        if i >= cap:
            truncated = True
            break
        rows.append([cell_to_text(c) for c in row])
    return rows, truncated


def cell_to_text(value):
    if value is None:
        return ""
    if isinstance(value, (int, float)):
        return value
    if hasattr(value, "isoformat"):  # datetime / date / time
        return value.isoformat(sep=" ") if hasattr(value, "time") else value.isoformat()
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return str(value)


def write_sheet(wb, name, headers, rows, truncated):
    ws = wb.create_sheet(title=name[:31])
    ws.append(headers)
    for r in rows:
        ws.append(r)
    if truncated:
        ws.append(["(TRUNCATED at %d rows in export — full data is in the database backup)" % len(rows)])


def export_module(conn, module, out_path):
    from openpyxl import Workbook
    wb = Workbook()
    wb.remove(wb.active)
    tables = MODULES[module]
    for table in tables:
        if table not in all_tables:
            continue
        cols = column_names(conn, table)
        rows, truncated = fetch_rows(conn, table)
        if not rows:
            continue
        sheet_name = table.replace("tab", "").strip()
        write_sheet(wb, sheet_name, cols, rows, truncated)
    if not wb.sheetnames:
        print("  (module %s has no data — skipping file)" % module)
        return False
    wb.save(out_path)
    print("  wrote %s (%d sheets)" % (os.path.basename(out_path), len(wb.sheetnames)))
    return True


def export_full(conn, out_path):
    from openpyxl import Workbook
    wb = Workbook()
    wb.remove(wb.active)
    count = 0
    for table in all_tables:
        if table.startswith(_PRIVATE_PREFIXES):
            continue
        try:
            cols = column_names(conn, table)
            rows, truncated = fetch_rows(conn, table)
        except Exception as e:  # lock/privilege edge cases should not kill the run
            print("  skip %s (%s)" % (table, e))
            continue
        if not rows:
            continue
        sheet_name = table.replace("tab", "").strip()
        write_sheet(wb, sheet_name, cols, rows, truncated)
        count += 1
    if count == 0:
        print("  full export has no data")
        return False
    wb.save(out_path)
    print("  wrote %s (%d sheets)" % (os.path.basename(out_path), count))
    return True


def fingerprint_site(conn, db_name):
    """Stable fingerprint of the business data, to skip identical backups.

    Uses CHECKSUM TABLE ... EXTENDED (accurate even though InnoDB leaves
    information_schema.update_time NULL), hashed into a single digest.
    """
    cur = conn.cursor()
    cur.execute(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_schema=%s AND table_type='BASE TABLE' ORDER BY table_name",
        (db_name,),
    )
    tables = [r[0] for r in cur.fetchall()]
    tables = [t for t in tables if not t.startswith(_PRIVATE_PREFIXES)]

    digest = hashlib.sha256()
    # Chunk the checksums so the SQL statement stays small.
    for i in range(0, len(tables), 200):
        chunk = tables[i : i + 200]
        names = ",".join("`%s`" % t.replace("`", "``") for t in chunk)
        try:
            cur.execute("CHECKSUM TABLE %s EXTENDED" % names)
            for name, checksum in cur.fetchall():
                digest.update(("%s=%s\n" % (name, checksum)).encode("utf-8"))
        except Exception:
            # One flaky table must not silently disable the change-detector:
            # fall back to a per-table checksum, and if that also fails, skip it.
            for t in chunk:
                try:
                    cur.execute("CHECKSUM TABLE `%s` EXTENDED" % t.replace("`", "``"))
                    for name, checksum in cur.fetchall():
                        digest.update(("%s=%s\n" % (name, checksum)).encode("utf-8"))
                except Exception:
                    digest.update(("%s=ERR\n" % t).encode("utf-8"))
    return digest.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["export", "fingerprint"])
    ap.add_argument("--site", required=True)
    ap.add_argument("--out", default=None)
    ap.add_argument("--stamp", default="export")
    args = ap.parse_args()

    bench_root = os.getcwd()
    site_dir = os.path.join(bench_root, "sites", args.site)
    if not os.path.isdir(site_dir):
        sys.exit("site dir not found: %s" % site_dir)

    conn = connect(site_dir)
    global all_tables
    all_tables = table_names(conn)
    db_name = json.load(open(os.path.join(site_dir, "site_config.json")))["db_name"]

    if args.command == "fingerprint":
        print(fingerprint_site(conn, db_name))
        conn.close()
        return

    out_dir = args.out or os.path.join(site_dir, "backups")
    os.makedirs(out_dir, exist_ok=True)
    print("exporting site %s -> %s" % (args.site, out_dir))
    for module in ("full", "khata", "pawn", "customers"):
        path = os.path.join(out_dir, "%s_%s.xlsx" % (args.stamp, module))
        if module == "full":
            export_full(conn, path)
        else:
            export_module(conn, module, path)
    conn.close()
    print("done.")


if __name__ == "__main__":
    main()