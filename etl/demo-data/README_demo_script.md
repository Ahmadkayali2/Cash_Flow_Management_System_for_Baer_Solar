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

## 5. `05_batch_liquidity_stress.csv` — the business case
Pushes five October milestones into the forecast window.

**Say:** "This is the question the owner actually needs answered."
**Show:** the 30-day cumulative line and the liquidity alert. The dip
below the buffer is the working-capital squeeze he described in the
interview — produced by the system, not asserted in a slide.

---

## Resetting between rehearsals

Run in the Supabase SQL editor:

```sql
DELETE FROM invoice WHERE invoice_number LIKE 'RE-2026-02%';
CALL sp_run_cashflow_pipeline(30);
```

The `etl_run` history is deliberately left intact — an audit log you can
delete is not an audit log.
