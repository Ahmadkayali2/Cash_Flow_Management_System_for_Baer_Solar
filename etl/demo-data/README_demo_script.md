# Demo CSV files — Baer Solar cash flow pipeline

Upload these through the Retool "Import CSV" screen (or POST them to the
Edge Function `ingest-sevdesk-invoices`) **in numbered order**. Each file
is built to make one specific behaviour visible on screen.

Format the ETL expects — header row exactly:

    invoice_number,project_id,invoice_date,due_date,amount,status

- `invoice_number` — the natural key from SEVDESK. Reruns match on this.
- `project_id` — must exist in `project`.
- `invoice_date`, `due_date` — ISO `YYYY-MM-DD`. `due_date` may not precede `invoice_date`.
- `amount` — positive decimal, max 2 places.
- `status` — must exist in `ref_invoice_status`: Issued, Partially Paid, Paid, Overdue, Cancelled.

---

## 1. `01_batch_clean.csv` — the happy path
4 valid invoices for Nürnberg, Hamburg, Leipzig and Dresden.

**Say:** "This is a normal weekly SEVDESK export."
**Show:** run status `Succeeded`, 4 promoted, 0 rejected. Outstanding
receivables and the 30-day chart both move. Each invoice was tagged
Stage 1 or Stage 2 automatically — nobody typed a milestone.

## 2. `02_batch_with_errors.csv` — validation
6 rows, 4 deliberately broken, one per validation rule.

**Say:** "Real exports contain mistakes. Nothing invalid reaches the
operational tables."
**Show:** status `Partial`, 2 promoted, 4 rejected, each with its reason:

| Row | Rejection reason |
|-----|------------------|
| RE-2026-0207 | project_id 99 does not exist |
| RE-2026-0208 | invoice_date is not YYYY-MM-DD: 21-09-2026 |
| RE-2026-0209 | amount is not a positive decimal: -500.00 |
| RE-2026-0210 | unknown invoice status: Draft |

The two good rows still went through — a bad row does not sink the batch.

## 3. `03_batch_rerun_identical.csv` — idempotency
Byte-identical to file 1.

**Say:** "The owner uploads the same file twice by accident."
**Show:** invoice count unchanged. A second `etl_run` row is logged, so
the event is auditable, but no duplicate invoices exist. The upsert
matches on `invoice_number`.

## 4. `04_batch_threshold_rule.csv` — the EUR 3,000 rule
The rule the owner only remembered halfway through the project.

**Say:** "Any payment under EUR 3,000 is not a milestone."
**Show:**

| Invoice | Amount | Project value | Result |
|---------|--------|---------------|--------|
| RE-2026-0211 | 15,660.00 | 34,800 | STAGE_2_COMMISSIONING (45%) |
| RE-2026-0212 |    480.00 | 34,800 | **ADJUSTMENT** — no stage slot |
| RE-2026-0213 |  2,450.00 |  2,450 | SINGLE_PAYMENT (100%) |
| RE-2026-0214 |  2,890.00 | 31,200 | **ADJUSTMENT** — no stage slot |

Two different reasons for two different outcomes: RE-2026-0213 is a small
*project*, so the whole thing is one payment. RE-2026-0214 is a small
*invoice* on a large project, so it is billed on its own and does not
consume a stage.

## 5. Where the liquidity case is shown

There is no fifth file, and that is a deliberate correction rather than an
omission. An earlier version of this script had
`05_batch_liquidity_stress.csv`, described as pushing five October
milestones into the forecast window to produce the dip. Tested on
14 September 2026, it moved nothing on the chart at all: the totals, the
minimum and maximum position and the five liquidity alert days were
byte-identical before and after the import.

The reason is in BR-3, and it is worth being able to say out loud. Cash in
comes from `payment_schedule` rows, and a schedule row's date is the
project's `start_date` plus its `due_offset_days`. Those rows exist from the
moment the project does. Importing an invoice links it to its schedule row
and moves that row from `Pending` to `Invoiced`, and BR-3 counts `Pending`,
`Invoiced` and `Overdue` alike. So **no invoice CSV can change the forecast
line.** It changes the receivables figure, which is money billed but not yet
paid, and that is a different question from when money arrives.

Nothing that moves the forecast out is importable either: cash out comes
from purchase orders and operational costs, and the import pipeline accepts
invoices only.

**So show the dip where it already is.** After `rpc_rebase_demo_dates()`, the
chart opens below zero and crosses the buffer twice more. That is stronger
than an upload, because it is the current position of the business rather
than a scenario loaded to make a point.

**Say:** "The squeeze is not something I loaded to show you. It is what the
forecast says about the next thirty days as the data stands."

---

## Re-anchoring the calendar before a rehearsal or the defence

The demonstration data is synthetic and its dates were authored around
13 September 2026. The forecast window is forward-looking, so every day
that passes pushes another supplier obligation out of the window. One day
after those dates were written, the 10,600 EUR dip on day one had already
dropped out and `v_liquidity_alert` returned nothing worth showing.

Run this first, before the reset:

```sql
SELECT rpc_rebase_demo_dates();
```

It shifts every business date in the demonstration dataset by the same
whole number of days, so the newest purchase order always sits three days
before today, then reruns the pipeline. Amounts, relationships and every
business rule are untouched: only the calendar moves. Running it twice on
the same day does nothing the second time, and the report tells you the
shift it applied:

```json
{
  "shiftDays": 1,
  "rowsShifted": { "project": 13, "purchase_order": 9, "invoice": 17, ... },
  "liquidityAlerts": [ 2 NEGATIVE days at -10,600, 3 BELOW_BUFFER days ],
  "kpiAfterRebase": { "outstanding_receivables": 57500, ... }
}
```

Verified on 14 September 2026: after the rebase the KPI cards, the five
liquidity alert days, the 5 overdue / 3 due-soon split on Supplier Watch
and the star schema totals all match the figures in Chapters 8 and 9
exactly, and no amount or row count changed.

## Resetting between rehearsals

Run in the Supabase SQL editor:

```sql
DELETE FROM invoice WHERE invoice_number LIKE 'RE-2026-02%';
CALL sp_run_cashflow_pipeline(30);
```

The `etl_run` history is deliberately left intact — an audit log you can
delete is not an audit log.
