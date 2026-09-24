# Frappe Jewellery, Pawn & Lending Suite

A complete open-source business suite on **Frappe Framework + ERPNext**:

| App | On the Apps screen | What it does |
|-----|--------------------|--------------|
| `jewellery_management` | **Sri Sai Krishna Jewellery** | Jewellery ERP — orders, workers, billing, GST, weight-based stock, old gold, HUID, repairs, reports, dashboard |
| `pawn_shop` | **Pawn Shop** | Pawn shop + Khatabook village lending — pledges, interest, release, weekly collections, refinance, combined accounting |
| `lending` | **Lending** | Official [frappe/lending](https://github.com/frappe/lending) — loans, disbursement, repayment, reports |

---

## 👉 Read this first: **[README_FIRST.md](README_FIRST.md)**

`README_FIRST.md` is the full onboarding guide. It covers:

- The **exact daily steps** (`sudo systemctl start mariadb` → `cd ~/frappe-bench`
  → `bench start` → open `http://library.local:8000/desk`)
- The **tested system configuration** (Kali/Debian, Python 3.14, MariaDB 11.8,
  Node 24, Bench 5.31, Frappe/ERPNext 17.x)
- **How to install from scratch** (Frappe framework first) and why you cannot
  just "install one file"
- **How to ship a complete image** for non-technical users (VM/Docker/backup)
- The **gray-page / missing-sidebar fix** (§7) and a Frappe forced-sync trap
- **Features** of all three apps + combined 3-business accounting
- **Known issues / future fixes** and the **advantages** of the open-source stack

---

## Quick start (already-installed machine)

```bash
sudo systemctl start mariadb
cd ~/frappe-bench
bench start
# open http://library.local:8000/desk
```

## Install (existing Frappe/ERPNext bench)

```bash
cd ~/frappe-bench
bench get-app https://github.com/ShyberDev/jewellery_management --branch "Frappe Jewellery, Pawn & Lending Suite"
bench get-app https://github.com/frappe/lending
# pawn_shop: copy apps/pawn_shop into your bench (no public remote yet)
bench --site library.local install-app jewellery_management
bench --site library.local install-app lending
bench --site library.local install-app pawn_shop
bench build
```

---

## Documentation

- **[README_FIRST.md](README_FIRST.md)** — start here.
- **[docs/AI_HANDOFF.md](docs/AI_HANDOFF.md)** — full engineering log, decisions,
  verification and warnings (§16–§18 cover the new apps).

## License

MIT
