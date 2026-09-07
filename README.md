# Baer Solar — Cash Flow Management and Financial Planning

Postgraduaat Databeheer, Karel de Grote Hogeschool — Eindproject.
Full write-up, reasoning, and academic context are in the thesis (submitted
separately through Canvas). This repository is the working product: the
database, the automation logic, and the frontend fixes behind it.

## What this is

Baer Solar is a small residential solar installer whose owner tracks money
with accounting software that records what already happened, not what is
coming. This project builds a database and a live dashboard that answer one
question directly: can he safely pay a supplier next week. Five business
rules generate a payment schedule, classify invoices, and forecast the next
30 days of cash flow, all running inside PostgreSQL rather than in
application code, so the same logic applies no matter what calls it.

## Stack

- **Database:** PostgreSQL 15 (built and run on Supabase)
- **Frontend / dashboard:** Retool, backed directly by the database
- **Automation:** SQL functions and procedures (`db/functions.sql`), plus a
  Python ETL script for the one external input (`etl/datev_to_baer.py`)

## Repository layout

```
db/            Full schema DDL and business-logic functions, generated
               directly from the live database so they cannot drift from it
etl/           The DATEV-to-Baer-Solar transform script, and safe synthetic
               demo CSVs for trying the import pipeline end to end
frontend/      Retool backend query fixes, with before/after context and
               the tests each fix was checked against
erd/           Entity-relationship diagram and star schema, as Graphviz
               source (.dot) and rendered PNGs
docs/          Data dictionary, table mapping, the ERD-to-database
               consistency check, and the project's decision log
screenshots/   The dashboard, active projects, supplier watch, and CSV
               import screens
```

## Reproducing it

1. Create a PostgreSQL 15+ database (a free Supabase project is the easiest
   way; this project used Supabase specifically for its built-in
   row-level-security and role model).
2. Run `db/schema.sql`, then `db/functions.sql`, against it.
3. Load sample data. Two options:
   - Upload the CSVs in `etl/demo-data/` through a frontend wired to
     `rpc_import_invoices` (see `frontend/retool-backend-fixes/README_paste_instructions.md`
     for what that call expects and what each demo file is built to show).
   - Or run `etl/datev_to_baer.py` against a real DATEV `Buchungsstapel`
     export to produce the same CSV shapes from real bookkeeping data. The
     script pseudonymises customer and supplier names before anything
     leaves it (see the script's own header).
4. Point a Retool app (or any frontend that can call Postgres functions) at
   the database. The three roles from `db/schema.sql`
   (`app_viewer`, `app_finance`, `app_admin`) are what row-level security is
   scoped to; connect as the role matching what the frontend should be
   allowed to do.
5. `docs/consistency_check.txt` and `docs/check_erd_vs_db.py` are the script
   and its last passing output for checking the ERD in the thesis still
   matches whatever database you end up with.

The live version of this product runs at
`https://ahmadkayali2--bear-solars-mvp.retool.app`. Row-level security is
enforced on every table, but this is a link to a real running system, not a
sandbox, so treat it accordingly.

## What's deliberately not in this repository

Real customer and supplier data from the owner's actual accounting export
is excluded on purpose. Everything needed to run and demonstrate the
system is either synthetic (`etl/demo-data/`) or has no personal data in it
at all (the schema, the functions, the ERD). This matches the project's own
GDPR chapter: minimise what leaves the system, especially anything that
did not need to leave it in the first place.

## Status

This is a first pass at a public structure, uploaded to have something in
place before the deadline. It will likely get reorganised (module
boundaries, a proper migrations folder instead of one schema dump, tests)
once the thesis itself is finished.
