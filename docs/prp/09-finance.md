# 09 — Finance: invoices, payments, expenses

> Golden rule: **the browser never decides money.** The browser sends only what the person typed (quantity, price, discount, tax %, payment amount). Every total, balance, status and number is calculated and checked by the database/server.

Tables used: `invoices`, `invoice_items`, `number_sequences`, `payments`, `expenses`, `expense_categories`, `services_products`, `organization_settings` (see `04-database.md`).

---

## 1. Currency

- **One currency per organization** (D-12), chosen at onboarding (default PKR).
- Each invoice copies the organization currency into `invoices.currency` when created; the browser cannot set it.
- The OWNER can change the organization currency **only until the first invoice is issued** (after that, old and new totals would mix currencies).
- Display: `Intl.NumberFormat` (the browser's built-in money formatter) with the currency code, 2 decimals, e.g. `Rs 12,500.00` / `PKR 12,500.00`.
- All money columns are `numeric(12,2)`; quantities `numeric(12,3)`; rates `numeric(5,2)`.

## 2. Invoice lines and totals

### 2.1 What the user enters per line
`description`, `quantity` (> 0, up to 3 decimals), `unit`, `unit_price` (≥ 0), `discount_amount` (≥ 0, default 0 — D-11), `tax_rate` % (0–100, default = item's rate, else organization default — D-10).
Picking a service/product fills description, unit, price and tax % (copied, editable on the draft).

### 2.2 How the database calculates (trigger `recalc_invoice_totals`)

Per line (rounded **half up** to 2 decimals at each step):

```
line_subtotal = round(quantity × unit_price, 2)
check:          0 ≤ discount_amount ≤ line_subtotal
taxable       = line_subtotal − discount_amount
line_tax      = round(taxable × tax_rate / 100, 2)
line_total    = taxable + line_tax
```

Per invoice (sums of the rounded lines, so the printed lines always add up exactly):

```
subtotal       = Σ line_subtotal
discount_total = Σ discount_amount
tax_total      = Σ line_tax
total          = subtotal − discount_total + tax_total
amount_paid    = Σ payments.amount where status = 'completed'
balance_due    = total − amount_paid        (generated column)
```

Worked example (tax 0% unless shown):

| Line | Qty | Price | Discount | Tax % | Subtotal | Tax | Line total |
|---|---|---|---|---|---|---|---|
| Marble slab (sq ft) | 12.5 | 850.00 | 625.00 | 0 | 10,625.00 | 0.00 | 10,000.00 |
| Installation | 1 | 5,000.00 | 0 | 16 | 5,000.00 | 800.00 | 5,800.00 |
| **Invoice** | | | **625.00** | | **15,625.00** | **800.00** | **15,800.00** |

(The 16% is only an example number; the software does not know any tax law — D-10.)

### 2.3 Tax

- **No tax rule is assumed.** Decided design (D-10): an optional tax % per line, an organization-wide default rate (starts at **0**) and a tax label (e.g. "Sales Tax") printed on invoices.
- Tax registration number (free text) is printed if filled in settings.
- Tax-inclusive prices, withholding tax, multiple taxes per line, tax reports for filing: **not in V1** (future, only if you define the rules).

## 3. Invoice statuses

| Status | Meaning | Set by |
|---|---|---|
| `draft` | Being prepared; no number; editable; invisible to the client | Default |
| `sent` | Issued: has a number, locked, visible to the client, no payment yet | `issue_invoice()` |
| `partially_paid` | Some money received, balance > 0 | Payment trigger |
| `paid` | Balance = 0 | Payment trigger |
| `void` | Cancelled with a reason; kept for history; excluded from totals | `void_invoice()` |
| *overdue* (computed, not stored) | `sent`/`partially_paid` and `due_date` < today (organization timezone) | Calculated on display and in reports |

```
draft ──issue──► sent ──payment──► partially_paid ──payment──► paid
  │                │                     │                       │
  └─delete         └──void (no payments)─┘◄── reversal moves back ┘
```

- A payment reversal recalculates the status: balance = total → `sent`; 0 < balance < total → `partially_paid`.
- `void` is allowed only when there are **no completed payments** (reverse them first). This keeps "money received" always tied to a valid invoice.
- An invoice with total 0 can be issued (warning) and is immediately `paid`.

## 4. Edit rules

| Action | Draft | Sent / partially paid / paid | Void |
|---|---|---|---|
| Edit lines, customer, dates, notes | ✅ | ❌ (D-31) | ❌ |
| Delete | ✅ | ❌ | ❌ |
| Issue | ✅ | — | — |
| Void (reason required) | — | ✅ if no completed payments | — |
| Duplicate as new draft | ✅ | ✅ | ✅ |
| Record payment | ❌ | ✅ (not `paid`) | ❌ |
| Print view | ✅ (watermark "DRAFT") | ✅ | ✅ (watermark "VOID") |

**Decided (D-31):** issued invoices are never edited. Correct a mistake by **Void + Duplicate as new draft** (the new invoice gets a new number). Reason: what the customer received never silently changes, and the history is complete.

## 5. Invoice numbering

Format (D-13): `{PREFIX}-{YYYY}-{NNNN}` → `INV-2026-0001`.
- `PREFIX` from `organization_settings.invoice_prefix` (default `INV`), `YYYY` = year of the **issue date**, `NNNN` = counter padded to 4 digits (grows to 5 digits after 9999 automatically).
- Counter per organization per year, starts again at 0001 each year.
- The number is given **at issue time**, not when the draft is created, so deleting drafts never leaves gaps.

**How we guarantee no duplicates, even when two people issue at the same moment:**

Inside `issue_invoice(invoice_id)` (one database transaction):

```sql
-- 1. lock the invoice row so it cannot be issued twice
select * from public.invoices
 where id = p_invoice_id and organization_id = v_org
 for update;                                   -- must be status 'draft', ≥ 1 line

-- 2. get the next counter value (atomic "insert or add 1")
insert into public.number_sequences (organization_id, sequence_type, period_year, last_value)
values (v_org, 'invoice', v_year, 1)
on conflict (organization_id, sequence_type, period_year)
do update set last_value = public.number_sequences.last_value + 1,
              updated_at = now()
returning last_value into v_next;

-- 3. build the number and issue
update public.invoices
   set invoice_number = v_prefix || '-' || v_year || '-' || lpad(v_next::text, 4, '0'),
       status = 'sent', sent_at = now(), sent_by = private.current_user_id(), bill_to = <customer snapshot>
 where id = p_invoice_id;
```

- Step 2 **locks the counter row** until the transaction finishes. A second person issuing at the same time waits a few milliseconds, then gets the next number.
- If anything fails, the whole transaction is undone — including the counter — so no number is lost or skipped.
- `unique (organization_id, invoice_number)` is a final safety net.
- Nobody can read or edit `number_sequences` directly (RLS on, no policies).

## 6. Payments

| Rule | V1 decision |
|---|---|
| What a payment belongs to | Exactly **one invoice** (D-14) |
| Amount | > 0 and ≤ current balance (**no overpayment** — D-14). Suggested amount = full balance |
| Advance payments / credit / one payment over several invoices | Not in V1 (D-14) → record separately per invoice |
| Payment date | Required, not in the future (organization timezone); back-dating allowed |
| Methods | Fixed list (D-15): `cash`, `bank_transfer`, `jazzcash`, `easypaisa`, `cheque`, `card`, `other` + free "reference" (cheque no., transaction ID) |
| Invoices that accept payments | `sent`, `partially_paid` (not `draft`, `paid`, `void`) |
| Editing a payment | ❌ — reverse and record again |
| Deleting a payment | ❌ never (D-32) |
| Reversing | Reason required; status `reversed`; invoice recalculated; client and OWNER notified |
| Cheque that bounces | Record when received; if it bounces → reverse with reason "Cheque bounced" |
| Receipt | Printable receipt view per payment (organization details, customer, invoice number, amount, method, date). No separate receipt numbering in V1 |

`record_payment()` in one transaction: lock the invoice (`for update`) → check organization, status and balance → insert payment (customer copied from invoice) → update `amount_paid` → recalculate status → log → notify. Locking stops two people from both recording the "last" payment and overpaying.

## 7. Expenses

- Fields: category (required), amount (> 0), date, method (same list as payments), payee, description, reference, project (optional), receipts (documents).
- Currency = organization currency.
- **Editing** allowed for OWNER/ADMIN/ACCOUNTANT while `recorded` (expenses are internal, never sent to anyone); every change is in the activity log with old → new values.
- **Void** with reason instead of delete. Void expenses are excluded from reports.
- **Categories**: per organization, starter list created at onboarding (Rent, Utilities, Salaries & wages, Transport, Materials, Office supplies, Marketing, Other), rename/add/archive allowed; archived categories cannot be used for new expenses but stay on old ones.
- Employee expense claims/approval: not in V1 (D-20).

## 8. Validation summary (server + database)

| Check | Zod (server) | Database |
|---|---|---|
| Quantity > 0, ≤ 3 decimals | ✅ | check constraint |
| Money ≥ 0 (price, discount), > 0 (payment, expense), ≤ 2 decimals | ✅ | check constraint + `numeric(12,2)` |
| Discount ≤ line subtotal | ✅ | check / trigger |
| Tax % 0–100 | ✅ | check constraint |
| Due date ≥ issue date | ✅ | check constraint |
| Totals / amount paid / balance / status / number | ignored if sent | calculated by triggers/functions |
| Customer, project, item belong to this organization | ✅ (load by org) | composite foreign keys + RLS |
| Payment ≤ balance | ✅ | `record_payment()` + `amount_paid ≤ total` check |

## 9. Financial reports (Step 20)

All calculated in the database with date filters; void invoices, void expenses and reversed payments are excluded.

| Report | Formula |
|---|---|
| Invoiced (sales) | Σ `total` of invoices with status ≠ draft/void, by `issue_date` |
| Received | Σ `amount` of completed payments, by `payment_date` (also by method) |
| Receivables / unpaid | Σ `balance_due` of `sent` + `partially_paid` invoices |
| Aging | Receivables grouped by days past due date: not due, 1–30, 31–60, 61–90, 90+ |
| Customer statement | For one customer and period: invoices, payments, running balance |
| Expenses | Σ `amount` of recorded expenses by category / month / project |
| Income vs expenses (D-41) | **Received − Expenses** for the period, labelled "cash basis", with "Invoiced" shown next to it for comparison |
| Project summary | Invoiced and received for invoices linked to the project, expenses linked to the project |

## 10. Printing / PDF

**Decided (D-40):** a clean **print view** page (`/invoices/[id]/print`) with organization logo, details, tax label and registration number, bill-to snapshot, lines, totals, payments, notes, terms. The user prints or uses the browser's "Save as PDF". No server-generated PDF files and no emailing invoices in V1.

## 11. Automated tests (Step 15/16)

- Line calculations: rounding half up (e.g. 0.005 → 0.01), discounts, tax, 3-decimal quantities, zero-price lines.
- Invoice totals equal the sum of lines after add / edit / delete of lines.
- Totals sent by the browser are ignored.
- Two parallel `issue_invoice()` calls → two different, consecutive numbers; new year → counter restarts.
- Editing/deleting an issued invoice → refused.
- Payments: partial → `partially_paid`; full → `paid`; over balance → refused; reversal → balance and status restored; void with payments → refused.
- Client of customer A cannot read invoices/payments of customer B; clients never see drafts.

## 12. Decisions for this file (answered 2026-09-23 — "use recommendation")

| # | Question | Decision (answered 2026-09-23) | Why |
|---|---|---|---|
| D-40 | Invoice PDF and emailing | **Print view + browser "Save as PDF"**; no emailing of invoices in V1. | No extra PDF library or email volume; businesses can send the PDF by WhatsApp. |
| D-41 | Basis of the "Income vs expenses" report | **Cash basis** (money received − expenses paid), with "Invoiced" shown next to it. | Easiest for small businesses to understand and matches their bank/cash; not a formal accounting statement. |

Referenced: D-10, D-11, D-12, D-13, D-14, D-15, D-20, D-31, D-32.
