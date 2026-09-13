# Baer Solar — Cash Flow Management and Financial Planning

Eindproject, Postgraduaat Databeheer, Karel de Grote Hogeschool, academic year
2025-2026. This repository is the working product: the database, the automation
logic, the ETL script and the frontend queries behind the dashboard. The
reasoning, the design decisions and the academic write-up are in the thesis,
submitted separately through Canvas.

## The problem this solves

Baer Solar is a small residential solar installer in Germany. Its suppliers want
payment upfront or within days of an order, while its customers pay in two stages
spread across the length of an installation. The owner tracked this in accounting
software that records what already happened and forecasts nothing, so he had no
reliable answer to the question he asks most weeks: can he safely pay a supplier.

This project answers that question. Five business rules generate a payment
schedule from a project's contract value, classify each invoice against that
schedule, produce a rolling 30-day cash flow forecast, flag a supplier payment
approaching its due date, and flag a day the forecast falls below a cash safety
margin. All five run inside PostgreSQL, so the same logic applies whichever
client calls it.

## Stack

- **Database:** PostgreSQL 17 on Supabase, with row-level security on all 31 tables
- **Interface:** Retool, connected straight to the database
- **Automation:** SQL procedures and views in `db/functions.sql`, plus a Python
  ETL script for the one external input, `etl/datev_to_baer.py`

## Layout

```
db/           Full schema DDL and the business-logic functions, both dumped from
              the live database so they cannot drift from it
docs/         Data dictionary, functional dependencies, table mapping, and the
              script that checks the ERD against the live database
erd/          Entity-relationship diagram and star schema, as Graphviz source
              (.dot) and rendered PNGs
etl/          The DATEV-to-Baer-Solar transform script, and synthetic demo CSVs
              for trying the import pipeline end to end
frontend/     Retool backend query fixes, with before/after context and the test
              each fix was checked against
screenshots/  The four dashboard screens: Dashboard, Active Projects, Supplier
              Watch and Import CSV
```

## Rebuilding it from scratch

1. Create a PostgreSQL 15+ database. A free Supabase project is the easiest way,
   and this project used Supabase specifically for its built-in row-level
   security and role model.
2. Run `db/schema.sql`, then `db/functions.sql`.
3. Load sample data, either way:
   - Upload the CSVs in `etl/demo-data/` through a frontend wired to
     `rpc_import_invoices`. `frontend/retool-backend-fixes/README_paste_instructions.md`
     documents what that call expects and what each demo file is built to show.
   - Or run `etl/datev_to_baer.py` against a real DATEV `Buchungsstapel` export to
     produce the same CSV shapes from real bookkeeping data. The script
     pseudonymises customer and supplier names before anything leaves it; see the
     script's own header.
4. Point Retool, or any frontend that can call Postgres functions, at the
   database. Connect as the role matching what the frontend should be allowed to
   do: `db/schema.sql` defines `app_viewer`, `app_finance` and `app_admin`, and
   row-level security is scoped to those three.

## Checking the diagram against the database

`docs/check_erd_vs_db.py` enforces one rule: the ERD may show less than the
database, and it may never show something different from it. A drawn entity,
attribute or relationship with nothing behind it is an error, and so is a table
that is neither drawn nor listed as a declared exclusion.

```bash
# 1. run docs/export_schema.sql in the Supabase SQL editor, save the result as schema.json
# 2. compare
python3 docs/check_erd_vs_db.py erd/erd_conceptual_chen.dot schema.json
```

`docs/consistency_check.txt` is the last passing output: 13 entities, 62
attributes and 11 relationships checked against 31 tables, 206 columns and 29
foreign keys, with 86 passing checks, 18 declared gaps and zero errors.

The script has been wrong once. An earlier version anchored its attribute pattern
to the start of a line, and the `.dot` file declares two attributes on most
lines, so it read 35 of the 62 attributes and reported a clean pass on all of
them. Chapter 10 of the thesis covers what that cost and how it was found.

## The live system

The dashboard runs at `https://ahmadkayali2--bear-solars-mvp.retool.app`. Row-level
security is enforced on every table, and this is a real running system rather
than a sandbox, so treat the link accordingly.

## What is deliberately not here

No real customer or supplier data from the owner's accounting export. Everything
needed to run and demonstrate the system is either synthetic (`etl/demo-data/`)
or holds no personal data at all: the schema, the functions and the ERD. This
follows the project's own GDPR chapter, which argues for minimising what leaves
the system and especially what did not need to leave it in the first place.

Internal working documents used while building this, including the design
decision log, are not in this repository either. What they hold that matters is
written up in the thesis itself.
