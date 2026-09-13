# Functional Dependencies — Baer Solar Cash Flow Management System

Every table in the schema, written as `determinant -> {dependents}` with a note saying why the determinant is a key. A table whose only determinants are candidate keys is in Boyce-Codd normal form, and BCNF implies third normal form, so this list is the proof for both. It is generated from the live schema of Supabase project `tppnycgtsrgbnukemtoh` rather than written by hand, so it cannot drift from the database. Chapter 7.3 of the thesis explains the one violation that was found and corrected; `../erd/figures/fd_payment_schedule.png` draws it.

Audit columns (`created_at`, `updated_at`, `created_by`) are part of the dependent set of their table and are shown where they exist.


### Business entities drawn on the ERD

**Customer (`customer`)**

```
customer_id -> {first_name, last_name, company_name, email, phone, street_name, house_number, postal_code, city, country, created_at, updated_at, created_by, pseudonymized_at}
email -> {customer_id, first_name, last_name, company_name, phone, street_name, house_number, postal_code, city, country, created_at, updated_at, created_by, pseudonymized_at}
```
Surrogate primary key. `email` is also UNIQUE, so it is a second candidate key and determines the same set; both determinants are keys, so the table is in BCNF.

**Project (`project`)**

```
project_id -> {customer_id, project_name, status, total_value, start_date, expected_completion_date, created_at, updated_at, created_by}
```
Surrogate primary key. No non-key column determines another: a project name is not unique, and status, value and dates are independent facts about one project.

**PaymentSchedule (`payment_schedule`)**

```
schedule_id -> {project_id, due_offset_days, expected_amount, status, created_at, updated_at, created_by, milestone_code}
(project_id + milestone_code) -> {schedule_id, due_offset_days, expected_amount, status, created_at, updated_at, created_by}
```
Surrogate primary key. This is the table the BCNF violation was in. `milestone_code` now determines nothing inside this table; what it used to determine lives in `ref_milestone_type`. (project_id, milestone_code) is UNIQUE, so it is a second candidate key.

**Invoice (`invoice`)**

```
invoice_id -> {project_id, schedule_id, invoice_number, invoice_date, due_date, amount, status, created_at, updated_at, created_by, milestone_code}
invoice_number -> {invoice_id, project_id, schedule_id, invoice_date, due_date, amount, status, created_at, updated_at, created_by, milestone_code}
```
Surrogate primary key. `invoice_number` is UNIQUE and is therefore a second candidate key, which is what the import pipeline upserts on. Both determinants are keys.

**Payment (`payment`)**

```
payment_id -> {invoice_id, payment_date, amount, payment_method, created_at, updated_at, created_by}
```
Surrogate primary key. A payment carries no column that determines another; two payments can share a date, an amount and a method.

**Supplier (`supplier`)**

```
supplier_id -> {supplier_name, credit_limit, payment_terms_days, contact_email, created_at, updated_at, created_by}
supplier_name -> {supplier_id, credit_limit, payment_terms_days, contact_email, created_at, updated_at, created_by}
```
Surrogate primary key. `supplier_name` is UNIQUE and is a second candidate key. Payment terms belong to the supplier, not to any other column in the row.

**PurchaseOrder (`purchase_order`)**

```
order_id -> {supplier_id, project_id, order_date, expected_delivery_date, total_amount, status, created_at, updated_at, created_by}
```
Surrogate primary key. The payment due date is not stored; it is computed from order_date plus the supplier's payment_terms_days, so no derived value can drift out of step here.

**Product (`product`)**

```
product_id -> {product_name, category, unit_cost, created_at, updated_at, created_by}
```
Surrogate primary key. `category` is a foreign key into ref_product_category and determines nothing else in this table.

**ProjectProduct (`project_product`)**

```
project_id + product_id -> {quantity, unit_price_charged, created_at, updated_at, created_by}
```
Composite primary key, the only one in the schema. Both non-key columns depend on the pair and on neither half alone, which is the second normal form check in 7.3.

**Cost (`cost`)**

```
cost_id -> {amount, cost_date, cost_category, created_at, updated_at, created_by}
(cost_id + cost_category) -> {amount, cost_date, created_at, updated_at, created_by}
```
Surrogate primary key. (cost_id, cost_category) is also UNIQUE, which is what lets each subtype`s composite foreign key pin the discriminator.

**ProjectCost (`project_cost`)**

```
cost_id -> {project_id, direct_cost_type, cost_category}
```
The primary key is also the foreign key back to `cost`, so a project cost is a cost and nothing else identifies it.

**OperationalCost (`operational_cost`)**

```
cost_id -> {overhead_category, cost_category}
```
Same shape as project_cost: the primary key is the foreign key back to `cost`.

**CashflowForecast (`cashflow_forecast`)**

```
forecast_id -> {project_id, forecast_date, net_cashflow, created_at, updated_at, created_by, expected_cash_in, expected_cash_out, flow_source}
```
Surrogate primary key. net_cashflow is stored as a generated value from the two cash columns and is marked derived on the ERD, so it is not an independent fact that could disagree with them.


### Reference tables (attribute domains)

All ten share one shape: the code itself is the primary key, chosen instead of generated, and every other column describes that code and nothing else. The only determinant in each is the key, so all ten are in BCNF.

**`ref_milestone_type`**

```
milestone_code -> {milestone_label, percentage, default_due_offset_days, part_of_split, description, is_milestone}
milestone_label -> {milestone_code, percentage, default_due_offset_days, part_of_split, description, is_milestone}
```

**`ref_project_status`**

```
status_code -> {description, sort_order, is_terminal}
sort_order -> {status_code, description, is_terminal}
```

**`ref_schedule_status`**

```
status_code -> {description, sort_order}
sort_order -> {status_code, description}
```

**`ref_invoice_status`**

```
status_code -> {description, sort_order, counts_as_receivable}
sort_order -> {status_code, description, counts_as_receivable}
```

**`ref_order_status`**

```
status_code -> {description, sort_order, counts_as_payable}
sort_order -> {status_code, description, counts_as_payable}
```

**`ref_payment_method`**

```
method_code -> {description, settlement_days}
```

**`ref_product_category`**

```
category_code -> {description}
```

**`ref_cost_category`**

```
category_code -> {description, is_indirect}
```

**`ref_direct_cost_type`**

```
type_code -> {description}
```

**`ref_overhead_category`**

```
category_code -> {description}
```


The ten reference tables share one shape: a natural code as the primary key, and a small set of columns that describe that code. `ref_milestone_type` is the one that matters most to Chapter 7, because `percentage` moved into it out of `payment_schedule` and it is the column that made the original design a BCNF violation.


### Analytical layer (star schema)

Each dimension is keyed on a surrogate key with a UNIQUE natural key back to the operational table it mirrors, and `fact_daily_cashflow` is keyed on its own surrogate key with the four dimension keys as foreign keys. Dimensions are type 1 and are overwritten on each load, so no historical version of a row can sit alongside the current one.

**`fact_daily_cashflow`**

```
fact_id -> {date_key, project_key, customer_key, cost_type_key, expected_cash_in, expected_cash_out, net_cashflow}
```

**`dim_date`**

```
date_key -> {full_date, day_of_week, day_of_month, month_name, month_num, quarter, year, is_weekend}
full_date -> {date_key, day_of_week, day_of_month, month_name, month_num, quarter, year, is_weekend}
```

**`dim_project`**

```
project_key -> {project_id, project_name, status, total_value}
project_id -> {project_key, project_name, status, total_value}
```

**`dim_customer`**

```
customer_key -> {customer_id, customer_name, city, postal_code}
customer_id -> {customer_key, customer_name, city, postal_code}
```

**`dim_cost_type`**

```
cost_type_key -> {cost_category, cost_subcategory, is_indirect}
(cost_category + cost_subcategory) -> {cost_type_key, is_indirect}
```


### Pipeline and audit

All three are append-only logs with a surrogate primary key. Each row records one event, and no column in any of them determines another.

**`etl_run`**

```
run_id -> {source_system, source_filename, started_at, finished_at, status, rows_received, rows_promoted, rows_rejected, error_message, triggered_by}
```

**`stg_sevdesk_invoice`**

```
stg_id -> {run_id, row_number, raw_invoice_number, raw_project_id, raw_invoice_date, raw_due_date, raw_amount, raw_status, is_valid, rejection_reason, promoted_at}
```

**`data_erasure_log`**

```
erasure_id -> {subject_table, subject_id, requested_at, executed_at, executed_by, legal_basis_note, columns_affected}
```


### What this proves

Every table above has exactly one determinant, or two where a natural key sits alongside a surrogate one, and in every case the determinant is a candidate key. No table has a determinant that is not a key, which is the Boyce-Codd condition. The single exception in the project's history, `milestone_name -> percentage` inside `payment_schedule`, no longer appears here because the column it determined was moved into `ref_milestone_type`, where `milestone_code` is the primary key and the dependency is therefore a key dependency. The only deliberate departure from full normalisation left in the schema is `payment_schedule.expected_amount`, discussed in 7.4: it duplicates a value derivable from `project.total_value` and `ref_milestone_type.percentage`, and it is stored on purpose so that correcting a contract value cannot silently change a milestone that has already been invoiced.
