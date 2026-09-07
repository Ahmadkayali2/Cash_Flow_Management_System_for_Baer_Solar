# Decision log

Every non-obvious choice in the project, why it was made, and what was
rejected. Written to be the source for the thesis and the revision
document for the defence.

Read it this way: if a jury asks "why did you do it like that", the answer
is in the third column. If they ask "did you consider anything else", it is
in the fourth.

Status: 22 tracked migrations, 31 tables, 206 columns, 29 foreign-key
links. Verified against the live Supabase project on 7 September 2026.

## Scope and technology

| # | Decision | Why | Rejected |
|---|---|---|---|
| 1 | Cash flow forecasting for Baer Solar | The owner interview named one problem clearly: suppliers want money before customers pay. A forecast answers that. A general "management system" would have answered nothing in particular. | A broader ERP-style project. Too large for 200 hours and too vague to defend. |
| 2 | PostgreSQL on Supabase | Native support for the constraints the model needs, plus a managed host, an HTTP API and Edge Functions in one product. No local install for a jury to reproduce. | MySQL, which was the Voorstel plan. Weaker constraint support. On-premise, which adds hosting work with no benefit for a project this size. |
| 3 | Retool for the interface | It connects directly to PostgreSQL and gives both a dashboard and a data-entry screen. The assignment asks for programmatic automation, and a BI tool alone would not have satisfied that. | Power BI, which was the Voorstel plan. It reads data but cannot run the import. Streamlit, which would have meant building and hosting a second application. |
| 4 | Thesis in English | Agreed with the supervisor. | Dutch, the default in the ECTS-fiche. Keep the supervisor's written agreement in the appendix. |

## Data model

| # | Decision | Why | Rejected |
|---|---|---|---|
| 5 | Reference tables instead of CHECK constraints | Adding a status becomes an INSERT instead of a schema migration, and each value carries its own attributes. `ref_invoice_status.counts_as_receivable` is what stops cancelled invoices being counted as money owed. | CHECK constraints, which were in the first version. Every new value needs DDL and no extra attributes are possible. PostgreSQL ENUM, which has the same migration problem. |
| 6 | Milestone percentage stored once, in `ref_milestone_type` | The first version stored `milestone_name` and `percentage` in the same row, so the name determined the percentage. That is a functional dependency whose determinant is not a candidate key, which breaks BCNF. | Keeping both columns. It was the actual BCNF violation in the model. |
| 7 | `payment_schedule.expected_amount` is stored, not derived | The agreed amount is fixed at contract time. If the contract value is corrected later, the amount already invoiced must not move. This is deliberate denormalisation with a business reason. | Deriving it from `project.total_value` on read. Cleaner in theory, wrong in accounting terms. |
| 8 | `UNIQUE (project_id, milestone_code)` | A project cannot carry the same milestone twice. The constraint enforces the business rule instead of the application enforcing it. | Application-level checks, which only bind clients that remember to run them. |
| 9 | ISA disjointness through a composite foreign key | `cost.cost_category` is the discriminator, and both subtypes carry it as a fixed value inside a composite key back to the supertype. A cost can no longer be both a project cost and an overhead. | A trigger, which is harder to explain. Nothing at all, which was the first version and allowed a cost in both subtypes. |
| 10 | `cost` has no `project_id`; the relationship sits on `ProjectCost` | Only direct costs belong to a project. Putting the column on the supertype would mean overheads carry a null project reference and the relationship would be a lie for half the rows. | Adding `project_id` to `cost`. It would have matched the older ERD, but the older ERD was wrong. |
| 11 | Surrogate keys everywhere, with `invoice_number` as a unique natural key | Stable joins, and the natural key gives the import something to match on so re-running a file updates instead of duplicating. | Natural keys as primary keys. Invoice numbering conventions change and the keys would have to change with them. |
| 12 | `updated_at` maintained by a trigger | PostgreSQL does not maintain it. Without the trigger the column stayed equal to `created_at` from 3 September, which made the audit trail worthless while looking correct. | Setting it in application code, which only works for writes that go through that code. |

## Business rules

| # | Decision | Why | Rejected |
|---|---|---|---|
| 13 | Milestones derived from `project.total_value`, not from invoices received | The contract value is known at quotation and never changes with the batch being processed. Using the sum of invoices meant the same invoice could be classified differently on two runs, which defeats the idempotent upsert. | Summing the invoices in the file. It was the first implementation and it was not deterministic. |
| 14 | A separate `ADJUSTMENT` classification with no percentage | The owner confirmed that a payment under 3,000 EUR is not a milestone. Tagging a 420 EUR correction as `SINGLE_PAYMENT` would claim one invoice is 100% of a 12,800 EUR project. | Reusing `SINGLE_PAYMENT` for both cases. It was the first implementation and it was semantically wrong. |
| 15 | Small project and small invoice are two different cases | A project under 3,000 EUR is genuinely a single payment. An invoice under 3,000 EUR on a large project is a standalone correction and must not consume a stage slot. | One rule for both, which is what the earlier documents implied and what made them contradict each other. |
| 16 | Supplier payment timed from the order date | Confirmed by the owner. The earlier dashboard used the expected delivery date, so the seven-day alert fired on the wrong day. | Delivery date. It is still stored, for logistics, but it does not drive money. |
| 17 | Business logic lives in the database | The rules apply to every client: the Retool screen, the Edge Function, or anyone with psql. Rules in the interface only bind users who go through that interface. | Keeping the milestone logic in the Retool frontend, which is where it started. It applied only to CSV uploads made on that one screen. |

## Pipeline

| # | Decision | Why | Rejected |
|---|---|---|---|
| 18 | A staging table between the file and the operational tables | Raw text lands first and is validated before anything is promoted. A bad row gets a readable reason instead of a constraint error, and the good rows still go through. | Writing straight into `invoice`. One bad row would fail the batch or, worse, insert something invalid. |
| 19 | One entry point, `rpc_import_invoices` | The first version made six round trips and used CALL statements, which the Retool client does not run. One function call removes every one of those failure points and gives the same behaviour to every caller. | Orchestrating from the client. It broke twice for two different reasons. |
| 20 | Every run recorded in `etl_run`, including failures | The owner's complaint is not knowing what happened. A run that fails silently repeats the problem the system exists to solve. | Logging only errors, or nothing. |
| 21 | Upsert on `invoice_number` | Re-uploading the same export updates rather than duplicates. Verified: the same batch run twice left the invoice count unchanged. | Insert-only with a manual duplicate check. |

## Analytical layer

| # | Decision | Why | Rejected |
|---|---|---|---|
| 22 | Separate star schema for reporting | The forecast query aggregates across dates and projects, which is an analytical pattern. Running it against the normalised tables means joining five of them for every dashboard refresh. | Reporting straight off the OLTP tables. Simpler, but it gives up the OLTP and OLAP distinction the assignment asks for. |
| 23 | Grain of one row per date per project | Matches the question the dashboard answers: what is the position on each of the next 30 days. | A finer grain per transaction, which would store more and answer nothing extra. |
| 24 | Type 1 dimensions, overwritten on load | The forecast answers what happens next, not what a project looked like last month. Slowly changing dimensions would add history nobody asks for. | Type 2 with history rows. More correct in general, unjustified here. |

## Privacy and access

| # | Decision | Why | Rejected |
|---|---|---|---|
| 25 | Row Level Security on all 31 tables, with three roles | Before this, anyone holding the public anon key could read and change every customer record. Roles are app_viewer (read), app_finance (read and write on transactional tables, inherits app_viewer), app_admin (delete plus write on dimensions and audit tables, inherits app_finance). Retool connects as a role that inherits app_finance, so it can run the pipeline and enter data but cannot delete. Verified directly: querying as anon or authenticated is refused at the grant level before RLS is even evaluated. | Supabase's own anon/authenticated/service_role split, which was the original plan for this decision. Rejected because those three map to "logged in or not", not to what a role should be allowed to do inside the business, which is what this system actually needs to restrict. Leaving RLS off, which is the Supabase default and was the state of the project until 6 September. |
| 26 | `security_invoker` on all nine views | A view runs with its owner's rights by default, so it would have returned exactly the data RLS was protecting, including the full personal-data export view. Found only after RLS was switched on. | The default. It looks safe and is not. |
| 27 | Pseudonymisation instead of deletion for Art. 17 | Financial records must be kept for seven years under Section 147 AO. Identifying fields are overwritten and the invoices stay, which satisfies both duties. | Deleting the customer row, which would break the accounting record and the retention obligation. |
| 28 | Erasure refused while receivables are open | Art. 17(3) allows refusal while a legal claim is running. The procedure checks and raises instead of proceeding. | Always erasing on request. |
| 29 | `data_erasure_log`, append only | Art. 5(2) requires the controller to demonstrate compliance. A record that can be edited afterwards demonstrates nothing. | No log, which was the state before 6 September. |

## Data

| # | Decision | Why | Rejected |
|---|---|---|---|
| 30 | Generated data for the demonstration, the real export for validation | One month of real data holds four invoices, which is too small to exercise the rules or fill a dashboard. It also contains real names and a real VAT ID. | Demonstrating on the real export. Too small, and it would put personal data in the repository. |
| 31 | Deterministic pseudonymisation of the real export | The same customer maps to the same fake identity in every monthly file, so relationships survive while the original cannot be recovered. | Random names, which would break the link between files. |
| 32 | Credit notes matched by document sequence, not by amount | A credit note reverses an earlier document, so the cancelled one has a lower number. Matching on amount alone deleted the live invoice and kept the cancelled one. | Matching on amount. It was the first implementation and it was wrong. |
| 33 | Automatic project matching not built | The DATEV export carries no project reference. No parsing can recover something the source system never recorded. Documented as future work with what would have to change at SEVDESK. | Guessing from the posting text, which would be unreliable and impossible to defend. |

## Documentation

| # | Decision | Why | Rejected |
|---|---|---|---|
| 34 | One ERD, business entities only | Reference tables implement attribute domains, the star schema is a different notation, and the pipeline tables are technical. All 18 are listed with a reason in the table mapping. | Drawing all 31 tables, which buries the business model. Two diagrams, which the assignment does not ask for. |
| 35 | Chen notation with min-max cardinality | The previous assessment failed the hybrid notation. Min-max states participation on both sides, which is more precise than 1 and N labels. | Crow's foot, which cannot be mixed with Chen. |
| 36 | Data dictionary generated from the live schema | It cannot drift from the database. Regenerating after a schema change takes one command. | Writing it by hand, which is how model and documentation come apart. |
| 37 | Automated ERD to database consistency check | The previous assessment found a relationship on the diagram with no foreign key behind it. The script catches that class of error. Tested by putting the original fault back in, which made it fail. | Checking by eye, which is what missed it the first time. |
| 38 | `sp_refresh_cashflow_star` fixed to populate `cost_type_key` | Found while writing the technical chapter: the procedure hardcoded `NULL` for every fact row, so `dim_cost_type` was loaded but never referenced. Overhead now reads `cost_type_key` from `cost`/`operational_cost` directly, since `cashflow_forecast` had already lost the `cost_id` needed to look it up. Verified: totals before and after the fix matched (123,030 EUR in, 90,970 EUR out), so no rows were double-counted or dropped. | Leaving it null and documenting it as a known limitation instead. Rejected because the fix was small and testable, and a jury question about an unused dimension is harder to defend than a fixed one. |
| 39 | Revoked the leftover `anon`/`authenticated` grant on `v_customer_data_export` | Found while writing the GDPR chapter: the view still carried Supabase's default SELECT grant to both roles from before RLS existed. RLS already returned zero rows to them, so this was not a working hole, but a grant with no purpose left in a finished build is not defensible either. Verified: `anon` now gets `permission denied for view` outright, and `app_finance` still sees all 30 customer rows unchanged. | Leaving it as a documented residual risk instead. Rejected once confirmed it did not affect any current behaviour: there was nothing to weigh against removing it. |

## Interface

| # | Decision | Why | Rejected |
|---|---|---|---|
| 40 | Supplier Watch gives OVERDUE and DUE_SOON two different shades of red instead of one | Found while writing the reporting chapter: `v_supplier_watch` already computes three distinct alert levels, but the frontend's `isAlerting()` function collapsed OVERDUE and DUE_SOON into the same background color, so an order six days overdue looked identical to one due tomorrow. Fixed in `/frontend/pages/SupplierWatch.tsx`: replaced `isAlerting()` with `getRowColor()`, returning `#7F1D1D` for OVERDUE and a lighter `#B91C1C` for DUE_SOON, with the legend above the table split into two labelled swatches. Verified by reading the published file after publishing: the change is live and no other file was touched. | Leaving it as a documented UI limitation. Rejected because the data already supported the distinction and the fix touched one function in one file. |

## Documentation corrections

| # | Decision | Why | Rejected |
|---|---|---|---|
| 41 | Corrected the view count from nine to ten, with `v_customer_minimised` documented as the one deliberate exception to `security_invoker` | Found while pulling the live schema for the appendix DDL: the schema has ten views, not nine, and `v_customer_minimised` genuinely has no `security_invoker` set. Checked the grants before treating it as a missed fix: `app_viewer` has no grant on `customer` at all, only on this view, so the view has to run with owner rights to expose its columns in the first place. Turning `security_invoker` on would break it, not secure it. | Silently correcting the count without checking why the tenth view differed, which would have missed a real design reason and possibly led to breaking a working view later. |
| 42 | Added the 6 foreign-key indexes the schema was missing, verified against the live database rather than assumed | Pulling the live DDL for the appendix showed 29 secondary indexes, not the 33 Chapter 8 claimed, and 8 foreign keys with no index at all. Checked each one before acting: 6 were genuinely missing (all pointing to small reference tables) and got a migration; the other 2, composite keys on `operational_cost` and `project_cost` back to `cost`, are already covered by their own primary key on `cost_id`, so a dedicated index would only duplicate it. Final count: 35. | Adding all 8 to hit a round number, which would have added two indexes that duplicate an existing primary key for no benefit. |

## Document assembly

| # | Decision | Why | Rejected |
|---|---|---|---|
| 43 | Manual, statically-numbered Table of Contents instead of a native Word TOC field | Assembling the full thesis in `docx-js` and converting with headless LibreOffice, the native `TableOfContents` field rendered its heading but an empty body: LibreOffice's `--convert-to pdf` does not recalculate TOC fields, that normally needs an interactive "Update Table" or a UNO macro, neither available in a one-shot command-line conversion. Since every chapter and appendix already sits behind an explicit page break, pagination does not depend on the TOC field at all, so the real page number for every heading was read directly off the rendered PDF (`pdftotext -layout`) and hard-coded into a manual TOC using right-aligned dot-leader tab stops. Confirmed twice that the listed numbers match the rendered PDF exactly, once before and once after later formatting fixes changed the page count from 100 to 84. | Leaving the empty TOC and telling the reader to "update fields" themselves in Word, which is not something a submitted PDF can rely on the jury doing. |
| 44 | Table headers fixed to actually show text, and column widths made content-proportional instead of a flat equal split | Found while visually checking the assembled PDF: every table's header row (Risk/Before/Mitigation/Residual, the data dictionary's #/Attribute/Type/etc.) rendered as a blank grey bar. Cause: the header-bolding code tried to clone an already-built `TextRun` object with `{...run, bold: true}`, which only copies a `TextRun`'s own exposed properties, not the text it was constructed from, so the clone was bold but empty. Fixed by passing a `forceBold` flag into the run-building step directly instead of cloning after the fact. While in there, also fixed the data dictionary's 7-column table forcing identifiers like `customer_id` to wrap mid-word: column widths are now sized by each column's longest cell instead of splitting the page width evenly, with a minimum floor so a short column like "Tool" doesn't collapse to nothing next to long text columns. Re-checked page numbers against the TOC after this too, since the appendix got visibly shorter. | Leaving the flat equal-width split. Would have kept working for narrow tables but stayed broken for wide ones, and the blank header bug would have shipped to the jury unnoticed if the PDF hadn't been opened and read page by page. |
| 45 | Star schema figure replaced with a re-exported PNG, and image embedding fixed to stop reading SVG bytes as PNG headers | The assembled thesis's star schema figure (Chapter 8) was cropped mid-diagram, cutting off the bottom two dimension tables. Cause: the docx build script only had a `.svg` file for that figure, no matching `.png`, and its image-embedding step, given no PNG, fell back to reading the raw SVG XML bytes and parsing them as if they were a PNG file's fixed-offset header. Every SVG's XML declaration is close enough to identical that this produced the same nonsense width and height for any SVG in the project, and for this figure the fake height happened to work out to roughly 12.8 inches, taller than one page, so LibreOffice's renderer clipped it rather than resizing it. Fixed two ways: the build now always prefers an actual PNG file when one exists instead of the SVG, and a maximum-height cap was added alongside the existing maximum-width cap so a similarly wrong dimension read can no longer overflow a page again. Ahmad re-exported the star schema from edotor.net as a clean, correctly proportioned PNG, which is now the file the build uses. | Manually cropping or repositioning the broken image in the exported PDF, which would have had to be redone by hand every time the thesis was rebuilt. |
