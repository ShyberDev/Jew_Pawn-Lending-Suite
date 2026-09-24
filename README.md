# Jew_Pawn-Lending-Suite

**One bundle. One command. A complete open-source jewellery + pawn + lending ERP.**

This repository bundles everything you need in a single download:

- **Frappe Framework** + **ERPNext** *(fetched automatically at pinned commits)*
- **Jewellery ERP** (`jewellery_management`)
- **Pawn Shop + Khatabook** (`pawn_shop`)
- **Money Lending** (`lending`, patched with the desk sidebar fix)

## Install in one command

```bash
git clone https://github.com/ShyberDev/Jew_Pawn-Lending-Suite.git
cd Jew_Pawn-Lending-Suite
./install.sh
```

Then:

```bash
sudo systemctl start mariadb
cd ~/frappe-bench
bench start
# open http://library.local:8000/desk
```

## 📖 Read this first

**[`README_FIRST.md`](README_FIRST.md)** is the full onboarding guide: what the
suite is, the exact tested configuration, the one-command install, the desk
sidebar/grey-page fix, every feature, known issues, backup/restore and how to
hand the system to a non-technical user.

## What's inside

| App | Route | Purpose |
|-----|-------|---------|
| Sri Sai Krishna Jewellery | `/app/jewellery` | Orders, workers, weight-based stock, GST, HUID, repairs, reports |
| Pawn Shop | `/app/pawn` | Gold/silver pledges, interest, release, Khatabook village lending, refinance |
| Lending | `/app/lending` | Loan application → disbursement → repayment |

All three share one database, one login and a **Combined Business Profit and
Loss** report.

## Layout

```
install.sh          one-command installer
versions.env        pinned frappe/erpnext commits
README_FIRST.md     full onboarding guide
apps/               vendored apps (jewellery_management, lending, pawn_shop)
docs/AI_HANDOFF.md  engineering log
```

## License

MIT (the bundle's own code). Frappe and ERPNext are licensed by their respective
upstream projects.

---

*Tested on Kali GNU/Linux Rolling · Python 3.14 · MariaDB 11.8 · Node 24 ·
Bench 5.31 · Frappe/ERPNext 17.0.0-dev.*
