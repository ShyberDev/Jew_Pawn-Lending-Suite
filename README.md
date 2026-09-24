# Pawn Shop + Khatabook

A Frappe Framework app for **pawn-broking** and **Khatabook-style village
lending**, with **combined 3-business accounting** (Shop / Money Lending / Pawn /
Khatabook).

Part of the **[Frappe Jewellery, Pawn & Lending Suite](https://github.com/ShyberDev/jewellery_management)**
— read the suite's **`README_FIRST.md`** for full onboarding, the tested system
configuration, and the sidebar/app-context fix.

- **App name:** `pawn_shop`
- **Module:** `Pawn Shop`
- **Route:** `/app/pawn`
- **License:** MIT

---

## Features

### Pawn
- **Pawn Customer** — name, address, phone (shared with Khatabook).
- **Pawn Loan** with multiple **Pawn Items** (metal, hallmarked yes/no, gross/net
  weight, valuation). Market valuation from the `Metal Rate` master (Settings
  fallback), LTV, and `balance = principal + accrued interest − payments`.
- **Interest:** simple `loan_amount × rate%/month × (days/30)`, rounded **up**
  (ceil). Default from the customer override, else **Pawn Settings**
  (default **gold 3%/month, silver 4%/month**).
- **Pawn Release** (submittable): pays principal + interest → loan `Released`,
  balance 0 (withdrawal/release of the pledged item).
- Gold/silver/weight valuations and hallmarked vs non-hallmarked split.

### Khatabook (village lending)
- **Village** master; 12-weekly schedules
  (e.g. ₹5000 principal + ₹1000 interest = **12 × ₹500**), with
  `installment_amount = ceil(total_payable / count)`.
- **Khatabook Collection** (submittable): allocates oldest-first and flags
  `is_irregular` (late or partial) — irregular-payment tracking.
- **Khatabook Refinance** (submittable): closes the old loan and creates a new
  one with principal = old outstanding and flexible interest.
- Customer good/bad **rating**.

### Reports (module `Pawn Shop`, code-defined)
- **Pawn Monthly Profit and Loss** (chart)
- **Pawn Valuation**
- **Pawn Outstanding**
- **Khatabook Collection Sheet**
- **Khatabook Outstanding**
- **Combined Business Profit and Loss** (chart)

### Accounting & automation
- **`Business`** master types: Shop / Money Lending / Pawn / Khatabook.
- Combined P&L aggregates shop (JSI/JPI), lending (`Loan`/`Loan Repayment`),
  pawn and khatabook with a TOTAL row.
- Scheduler: `pawn_shop.tasks.mark_overdue_loans` (daily).

---

## DocTypes (11)

`Business`, `Village`, `Pawn Customer` (`PC-.YYYY.-.#####`), `Pawn Settings`
(Single), `Pawn Item` (child), `Pawn Loan` (`PL-`), `Pawn Release` (`PR-`,
submittable), `Khatabook Installment` (child), `Khatabook Loan` (`KL-`),
`Khatabook Collection` (`KC-`, submittable), `Khatabook Refinance` (`KR-`,
submittable).

---

## Installation

Requires a working **Frappe/ERPNext bench**.

```bash
cd ~/frappe-bench
bench get-app https://github.com/ShyberDev/Jew_Pawn-Lending-Suite --branch develop
bench --site <your-site> install-app pawn_shop
bench build --app pawn_shop
bench --site <your-site> migrate
```

Then open `/app/pawn`. If the workspace icon/header looks gray, see
**§7 of the suite `README_FIRST.md`** (set the workspace `standard = 1` and use a
valid lucide icon such as `hand-coins`).

---

## Rounding contract

Mirrors the jewellery app: `pawn_shop/utils.py` provides `money` (ceil),
`round3` / `round2` / `round_pct` (half-up, using `Decimal`, never Python
`round`).

## License

MIT
