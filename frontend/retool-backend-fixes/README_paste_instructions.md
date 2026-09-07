# Fixing the CSV upload

## What was wrong

The version in the editor called the database six times and used features
(multi-statement execution, `CALL`, parameter binding) that the Retool
client may not support. That is what produced the error.

The import now lives in a single database function,
`rpc_import_invoices(records jsonb, filename text, user text)`, which is
already deployed and tested. The Retool function is one query.

## Verified before you touch anything

Run directly against the database:

| Test | Result |
|---|---|
| 4 clean rows | `Succeeded`, 4 upserted, 0 rejected |
| the same 4 rows again | invoice count 21 → 21, no duplicates |
| 4 rows, 3 deliberately broken | `Partial`, 1 upserted, 3 rejected with reasons |

Rejection messages returned:

```
row 3  RE-2026-0207  project_id 99 does not exist
row 4  RE-2026-0208  invoice_date is not YYYY-MM-DD: 21-09-2026
row 5  RE-2026-0210  unknown invoice status: Draft
```

Test invoices were deleted afterwards, so the database is back to 17
invoices and your demo starts clean.

## What to paste

Replace `/backend/invoices/bulkUpsertInvoices.ts` with
`bulkUpsertInvoices.ts` from this folder. Then **Save** and **Publish**.

## Testing it in the Data tab

`records` (paste as JSON):

```json
[
  {"invoice_number":"RE-2026-0201","project_id":21,"invoice_date":"2026-09-15","due_date":"2026-09-22","amount":19140.00,"status":"Issued"},
  {"invoice_number":"RE-2026-0202","project_id":22,"invoice_date":"2026-09-18","due_date":"2026-09-25","amount":7562.50,"status":"Issued"},
  {"invoice_number":"RE-2026-0203","project_id":23,"invoice_date":"2026-09-22","due_date":"2026-09-29","amount":17160.00,"status":"Issued"},
  {"invoice_number":"RE-2026-0204","project_id":18,"invoice_date":"2026-09-14","due_date":"2026-09-21","amount":12330.00,"status":"Issued"}
]
```

`filename`: `01_batch_clean.csv`

Expected: `status: "Succeeded"`, `upsertedCount: 4`, `rejectedCount: 0`.

## The Import CSV screen

`ImportCsv.tsx` still computes milestones in the browser and sends a
`milestone_type` field. The import ignores it, so **uploads will work
without changing that file**. But the Milestone column on screen shows the
browser's guess, which can disagree with what the database decided.

Two optional cleanups, in order of value:

1. Delete the `processRows` function and send the parsed rows straight
   through. The milestone belongs to the database now.
2. Show the returned `rejections` in a table under the upload, so a
   partial import is visible instead of silent.

Neither is needed to make the upload work.

## Return value changed

`bulkUpsertInvoices` used to return `{ upsertedCount }`. It now returns the
full report: `runId`, `status`, `rowsReceived`, `upsertedCount`,
`rejectedCount`, `rejections[]` and the dashboard `kpi` after the run.
Existing code reading `result.upsertedCount` keeps working.
