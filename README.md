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

## Windows & Docker

- **Windows:** Frappe needs Linux. Run `windows/install-windows.ps1` once
  (Admin PowerShell) to set up WSL2 + Ubuntu, then run `./install.sh` inside
  Ubuntu. See `windows/README.md`.
- **Docker (any OS):** `./docker/build.sh` builds a Frappe/ERPNext image with all
  three apps; `docker/README.md` runs it via the `frappe_docker` stack.

## Keeping the bundle in sync

After changing the apps in your working bench:

```bash
./update-bundle.sh --commit --push
```

## Layout

```
install.sh          one-command installer (Linux / WSL2)
update-bundle.sh    sync bench apps -> this bundle
versions.env        pinned frappe/erpnext commits
README_FIRST.md     full onboarding guide
apps/               vendored apps (jewellery_management, lending, pawn_shop)
docker/             Containerfile + build script + Docker guide
windows/            WSL2 setup script + Windows guide
docs/AI_HANDOFF.md  engineering log
```

## License

MIT (the bundle's own code). Frappe and ERPNext are licensed by their respective
upstream projects.

---

*Tested on Kali GNU/Linux Rolling · Python 3.14 · MariaDB 11.8 · Node 24 ·
Bench 5.31 · Frappe/ERPNext 17.0.0-dev.*
