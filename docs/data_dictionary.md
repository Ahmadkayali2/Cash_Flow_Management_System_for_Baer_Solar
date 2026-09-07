# Data Dictionary — Baer Solar Cash Flow Management System

Generated directly from the live PostgreSQL schema (Supabase project `tppnycgtsrgbnukemtoh`), so every entity, attribute, data type and key in this document is guaranteed to match the deployed database and the DDL scripts.

**31 tables, 206 attributes.**

Key: PK primary key · FK foreign key · UQ unique · N nullable

---

## Operational entities (OLTP)

### `customer`

*Entity.* The person or company that buys an installation. Holds personal data; lawful basis Art. 6(1)(b) performance of a contract.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `customer_id` | BIGINT | PK |  | seq customer_customer_id… | Surrogate key. |
| 2 | `first_name` | VARCHAR(100) | - |  |  | Given name. Personal data; overwritten on erasure. |
| 3 | `last_name` | VARCHAR(100) | - |  |  | Family name. Personal data; overwritten on erasure. |
| 4 | `company_name` | VARCHAR(150) | - | Y |  | Trading name when the customer is a business. Null for private customers. |
| 5 | `email` | VARCHAR(255) | UQ |  |  | Contact address, unique. Personal data; replaced by a non-routable value on erasure. |
| 6 | `phone` | VARCHAR(50) | - | Y |  | Contact number. Personal data; cleared on erasure. |
| 7 | `street_name` | VARCHAR(150) | - |  |  | Street, stored separately from the number so the address is atomic (1NF). |
| 8 | `house_number` | VARCHAR(20) | - |  |  | House number, textual because German numbers may carry a letter (12A). |
| 9 | `postal_code` | VARCHAR(20) | - |  |  | Postcode, textual to preserve leading zeros. |
| 10 | `city` | VARCHAR(100) | - |  |  | City. |
| 11 | `country` | VARCHAR(50) | - |  | 'Germany' | Country, defaults to Germany. |
| 12 | `created_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: when the row was created. |
| 13 | `updated_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: maintained by a trigger on every UPDATE. |
| 14 | `created_by` | VARCHAR(100) | - |  | 'system' | Audit column: which process or user created the row. |
| 15 | `pseudonymized_at` | TIMESTAMPTZ | - | Y |  | Set when an Art. 17 erasure has been executed. Null means the record is intact. |

### `project`

*Entity.* One solar installation job for one customer, from quotation to completion. The unit the whole cash-flow model is built around.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `project_id` | BIGINT | PK |  | seq project_project_id_s… | Surrogate key. |
| 2 | `customer_id` | BIGINT | FK |  |  | The customer this project belongs to. |
| 3 | `project_name` | VARCHAR(150) | - |  |  | Human-readable job name, usually place plus system size. |
| 4 | `status` | VARCHAR(50) | FK |  |  | Lifecycle state, constrained to ref_project_status. |
| 5 | `total_value` | DECIMAL(12,2) | - |  |  | Agreed contract value. Rules BR-1 and BR-2 read this, never the sum of invoices received, so classification stays deterministic. |
| 6 | `start_date` | DATE | - |  |  | Agreed start. Milestone due dates are calculated from it. |
| 7 | `expected_completion_date` | DATE | - | Y |  | Planned completion. Informational. |
| 8 | `created_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: when the row was created. |
| 9 | `updated_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: maintained by a trigger on every UPDATE. |
| 10 | `created_by` | VARCHAR(100) | - |  | 'system' | Audit column: which process or user created the row. |

### `payment_schedule`

*Entity.* The agreed billing milestones for a project, generated from the contract value by rule BR-1.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `schedule_id` | BIGINT | PK |  | seq payment_schedule_sch… | Surrogate key. |
| 2 | `project_id` | BIGINT | FK, UQ |  |  | The project being billed. |
| 3 | `due_offset_days` | INTEGER | - |  |  | Days after project start when this milestone falls due. |
| 4 | `expected_amount` | DECIMAL(12,2) | - |  |  | Amount expected for this milestone. Stored rather than derived because the agreed amount must not move if the contract value is later corrected. |
| 5 | `status` | VARCHAR(50) | FK |  | 'Pending' | Milestone state, constrained to ref_schedule_status. |
| 6 | `created_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: when the row was created. |
| 7 | `updated_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: maintained by a trigger on every UPDATE. |
| 8 | `created_by` | VARCHAR(100) | - |  | 'system' | Audit column: which process or user created the row. |
| 9 | `milestone_code` | VARCHAR(30) | FK, UQ |  |  | Which milestone. The percentage lives in ref_milestone_type, not here: storing it in both places was the BCNF violation that this design removes. |

### `invoice`

*Entity.* A customer invoice imported from SEVDESK. Classified against a milestone by rule BR-2.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `invoice_id` | BIGINT | PK |  | seq invoice_invoice_id_s… | Surrogate key. |
| 2 | `project_id` | BIGINT | FK |  |  | The project invoiced. |
| 3 | `schedule_id` | BIGINT | FK | Y |  | The milestone this invoice settles. Null for adjustments, which never consume a milestone slot. |
| 4 | `invoice_number` | VARCHAR(50) | UQ |  |  | Document number from SEVDESK. Natural key: the import upserts on it, which is what makes re-uploading a file safe. |
| 5 | `invoice_date` | DATE | - |  |  | Issue date. Rule BR-2 orders invoices by this to derive the milestone sequence. |
| 6 | `due_date` | DATE | - |  |  | Payment due date. |
| 7 | `amount` | DECIMAL(12,2) | - |  |  | Invoice total. |
| 8 | `status` | VARCHAR(50) | FK |  |  | Invoice state, constrained to ref_invoice_status. |
| 9 | `created_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: when the row was created. |
| 10 | `updated_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: maintained by a trigger on every UPDATE. |
| 11 | `created_by` | VARCHAR(100) | - |  | 'system' | Audit column: which process or user created the row. |
| 12 | `milestone_code` | VARCHAR(30) | FK | Y |  | Milestone derived by BR-2, or ADJUSTMENT for a standalone bill below the EUR 3,000 threshold. |

### `payment`

*Weak entity.* Money actually received against an invoice. Has no meaning without its invoice, so it is existence-dependent on it.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `payment_id` | BIGINT | PK |  | seq payment_payment_id_s… | Surrogate key. |
| 2 | `invoice_id` | BIGINT | FK |  |  | The invoice being settled. Identifying: a payment cannot exist without one. |
| 3 | `payment_date` | DATE | - |  |  | Value date the money arrived. |
| 4 | `amount` | DECIMAL(12,2) | - |  |  | Amount received; must be greater than zero. |
| 5 | `payment_method` | VARCHAR(50) | FK |  |  | How it was paid, constrained to ref_payment_method. |
| 6 | `created_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: when the row was created. |
| 7 | `updated_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: maintained by a trigger on every UPDATE. |
| 8 | `created_by` | VARCHAR(100) | - |  | 'system' | Audit column: which process or user created the row. |

### `supplier`

*Entity.* A wholesaler Baer Solar buys equipment from, with its credit limit and payment terms.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `supplier_id` | BIGINT | PK |  | seq supplier_supplier_id… | Surrogate key. |
| 2 | `supplier_name` | VARCHAR(100) | UQ |  |  | Supplier name, unique. |
| 3 | `credit_limit` | DECIMAL(12,2) | - |  |  | Credit the supplier extends. |
| 4 | `payment_terms_days` | INTEGER | - |  |  | Days from ORDER date to payment. The owner confirmed the order date starts the clock, not delivery. |
| 5 | `contact_email` | VARCHAR(255) | - |  |  | Ordering address. |
| 6 | `created_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: when the row was created. |
| 7 | `updated_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: maintained by a trigger on every UPDATE. |
| 8 | `created_by` | VARCHAR(100) | - |  | 'system' | Audit column: which process or user created the row. |

### `purchase_order`

*Entity.* An order placed with a supplier for one project. The payment obligation starts on the order date.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `order_id` | BIGINT | PK |  | seq purchase_order_order… | Surrogate key. |
| 2 | `supplier_id` | BIGINT | FK |  |  | Supplier the order was placed with. |
| 3 | `project_id` | BIGINT | FK |  |  | Project the order is for. |
| 4 | `order_date` | DATE | - |  |  | Order date. Payment due = this plus supplier.payment_terms_days. |
| 5 | `expected_delivery_date` | DATE | - |  |  | Expected delivery. Logistics only; deliberately NOT used for payment timing. |
| 6 | `total_amount` | DECIMAL(12,2) | - |  |  | Order total. |
| 7 | `status` | VARCHAR(50) | FK |  |  | Order state, constrained to ref_order_status. |
| 8 | `created_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: when the row was created. |
| 9 | `updated_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: maintained by a trigger on every UPDATE. |
| 10 | `created_by` | VARCHAR(100) | - |  | 'system' | Audit column: which process or user created the row. |

### `product`

*Entity.* Catalogue of equipment: modules, inverters, mounting systems, batteries, cabling.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `product_id` | BIGINT | PK |  | seq product_product_id_s… | Surrogate key. |
| 2 | `product_name` | VARCHAR(150) | - |  |  | Manufacturer and model. |
| 3 | `category` | VARCHAR(50) | FK |  |  | Equipment category, constrained to ref_product_category. |
| 4 | `unit_cost` | DECIMAL(12,2) | - |  |  | Purchase cost per unit. |
| 5 | `created_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: when the row was created. |
| 6 | `updated_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: maintained by a trigger on every UPDATE. |
| 7 | `created_by` | VARCHAR(100) | - |  | 'system' | Audit column: which process or user created the row. |

### `project_product`

*Weak entity.* Which products, and how many, are used in a project. Resolves the many-to-many between Project and Product.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `project_id` | BIGINT | PK, FK |  |  | Part of the composite key. Identifying. |
| 2 | `product_id` | BIGINT | PK, FK |  |  | Part of the composite key. Identifying. |
| 3 | `quantity` | INTEGER | - |  |  | Units used. Depends on the whole composite key, which is what makes this table 2NF-compliant. |
| 4 | `unit_price_charged` | DECIMAL(12,2) | - |  |  | Price charged to this customer, which may differ from the catalogue cost. |
| 5 | `created_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: when the row was created. |
| 6 | `updated_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: maintained by a trigger on every UPDATE. |
| 7 | `created_by` | VARCHAR(100) | - |  | 'system' | Audit column: which process or user created the row. |

### `cost`

*Entity (supertype).* Any cost the business incurs. Specialised into a direct project cost or an operational overhead.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `cost_id` | BIGINT | PK |  | seq cost_cost_id_seq') | Surrogate key. |
| 2 | `amount` | DECIMAL(12,2) | - |  |  | Cost amount. |
| 3 | `cost_date` | DATE | - |  |  | Date the cost falls due. |
| 4 | `cost_category` | VARCHAR(50) | FK, UQ |  |  | Discriminator for the ISA hierarchy. Part of the composite foreign key that makes the two subtypes mutually exclusive. |
| 5 | `created_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: when the row was created. |
| 6 | `updated_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: maintained by a trigger on every UPDATE. |
| 7 | `created_by` | VARCHAR(100) | - |  | 'system' | Audit column: which process or user created the row. |

### `project_cost`

*Entity (subtype).* A cost attributable to one specific project: materials or labour.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `cost_id` | BIGINT | PK, FK |  |  | Primary key and foreign key to the supertype. |
| 2 | `project_id` | BIGINT | FK |  |  | Project the cost is charged to. |
| 3 | `direct_cost_type` | VARCHAR(50) | FK |  |  | Materials or Labor, constrained to ref_direct_cost_type. |
| 4 | `cost_category` | VARCHAR(50) | FK |  | 'Direct Project' | Fixed to Direct Project. Half of the composite key that enforces ISA disjointness. |

### `operational_cost`

*Entity (subtype).* A company-wide cost not tied to any project: rent, advertising, fuel, insurance, software.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `cost_id` | BIGINT | PK, FK |  |  | Primary key and foreign key to the supertype. |
| 2 | `overhead_category` | VARCHAR(50) | FK |  |  | Overhead type, constrained to ref_overhead_category. |
| 3 | `cost_category` | VARCHAR(50) | FK |  | 'Operational Overhead' | Fixed to Operational Overhead. Half of the composite key that enforces ISA disjointness. |

### `cashflow_forecast`

*Entity.* One expected cash movement on one date, produced by rule BR-3. The operational forecast the star schema is loaded from.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `forecast_id` | BIGINT | PK |  | seq cashflow_forecast_fo… | Surrogate key. |
| 2 | `project_id` | BIGINT | FK | Y |  | Project the movement belongs to. Null for company overheads, which belong to no project. |
| 3 | `forecast_date` | DATE | - |  |  | Date the movement is expected. |
| 4 | `net_cashflow` | DECIMAL(12,2) | - |  |  | In minus out. Derived and stored so the dashboard reads one column. |
| 5 | `created_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: when the row was created. |
| 6 | `updated_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Audit column: maintained by a trigger on every UPDATE. |
| 7 | `created_by` | VARCHAR(100) | - |  | 'system' | Audit column: which process or user created the row. |
| 8 | `expected_cash_in` | DECIMAL(12,2) | - |  | 0 | Money expected in on this date. |
| 9 | `expected_cash_out` | DECIMAL(12,2) | - |  | 0 | Money expected out on this date. |
| 10 | `flow_source` | VARCHAR(30) | - | Y |  | Which rule produced the row: customer_milestone, supplier_order or operational_overhead. |

### `etl_run`

*Entity.* One execution of the import pipeline. Gives the owner an audit trail and makes a failed run diagnosable.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `run_id` | BIGINT | PK |  | seq etl_run_run_id_seq') | Surrogate key. |
| 2 | `source_system` | VARCHAR(50) | - |  | 'SEVDESK' | Origin system, currently always SEVDESK. |
| 3 | `source_filename` | VARCHAR(255) | - | Y |  | Uploaded filename, so a run can be traced back to a file. |
| 4 | `started_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | Run start. |
| 5 | `finished_at` | TIMESTAMPTZ | - | Y |  | Run end. Null while running or if the process died. |
| 6 | `status` | VARCHAR(20) | - |  | 'Running' | Running, Succeeded, Failed or Partial. |
| 7 | `rows_received` | INTEGER | - |  | 0 | Rows in the uploaded file. |
| 8 | `rows_promoted` | INTEGER | - |  | 0 | Rows that passed validation and reached the invoice table. |
| 9 | `rows_rejected` | INTEGER | - |  | 0 | Rows that failed validation. |
| 10 | `error_message` | TEXT | - | Y |  | Failure reason when the run itself broke. |
| 11 | `triggered_by` | VARCHAR(100) | - |  | 'system' | Who or what started the run. |

### `stg_sevdesk_invoice`

*Entity (staging).* Raw CSV rows exactly as uploaded, before validation. Deliberately untyped so bad input is rejected with a readable reason instead of crashing.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `stg_id` | BIGINT | PK |  | seq stg_sevdesk_invoice_… | Surrogate key. |
| 2 | `run_id` | BIGINT | FK |  |  | The import run this row arrived in. |
| 3 | `row_number` | INTEGER | - |  |  | Line number in the uploaded file, counting the header as line 1, so a rejection message points at a line the owner can find. |
| 4 | `raw_invoice_number` | VARCHAR(100) | - | Y |  | Raw text as uploaded. Untyped on purpose. |
| 5 | `raw_project_id` | VARCHAR(100) | - | Y |  | Raw text as uploaded. |
| 6 | `raw_invoice_date` | VARCHAR(100) | - | Y |  | Raw text as uploaded. |
| 7 | `raw_due_date` | VARCHAR(100) | - | Y |  | Raw text as uploaded. |
| 8 | `raw_amount` | VARCHAR(100) | - | Y |  | Raw text as uploaded. |
| 9 | `raw_status` | VARCHAR(100) | - | Y |  | Raw text as uploaded. |
| 10 | `is_valid` | BOOLEAN | - |  | false | Set by sp_validate_staging. Only valid rows are promoted. |
| 11 | `rejection_reason` | TEXT | - | Y |  | Why the row failed, in language the owner can act on. |
| 12 | `promoted_at` | TIMESTAMPTZ | - | Y |  | When the row reached the invoice table. |

### `data_erasure_log`

*Entity (compliance).* Register of GDPR Art. 17 erasure requests and what was done about them. Required for Art. 5(2) accountability.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `erasure_id` | BIGINT | PK |  | seq data_erasure_log_era… | Surrogate key. |
| 2 | `subject_table` | VARCHAR(100) | - |  |  | Table the data subject lives in. |
| 3 | `subject_id` | BIGINT | - |  |  | Identifier of the data subject. |
| 4 | `requested_at` | TIMESTAMPTZ | - |  | now() | When the subject asked. |
| 5 | `executed_at` | TIMESTAMPTZ | - |  | CURRENT_TIMESTAMP | When it was carried out. |
| 6 | `executed_by` | VARCHAR(100) | - |  | CURRENT_USER | Who carried it out. |
| 7 | `legal_basis_note` | VARCHAR(500) | - |  |  | Why erasure took this form, e.g. financial records retained under Section 147 AO. |
| 8 | `columns_affected` | TEXT | - |  |  | Exactly which columns were overwritten. |

## Reference entities (attribute domains)

### `ref_milestone_type`

*Reference.* Domain of billing milestones, and the single place the 55/45/100 percentages are stored.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `milestone_code` | VARCHAR(30) | PK |  |  | Primary key. |
| 2 | `milestone_label` | VARCHAR(100) | UQ |  |  | Display name. |
| 3 | `percentage` | DECIMAL(5,2) | - | Y |  | Share of contract value. Null for ADJUSTMENT, which is not a milestone. |
| 4 | `default_due_offset_days` | INTEGER | - |  |  | Default days after project start. |
| 5 | `part_of_split` | BOOLEAN | - |  |  | True for the two stages of the 55/45 split. |
| 6 | `description` | VARCHAR(200) | - |  |  | Explanation of when this milestone applies. |
| 7 | `is_milestone` | BOOLEAN | - |  | true | False for ADJUSTMENT, so it never generates or consumes a schedule row. |

### `ref_project_status`

*Reference.* Domain of project lifecycle states.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `status_code` | VARCHAR(50) | PK |  |  | Primary key of the domain. |
| 2 | `description` | VARCHAR(200) | - |  |  | Human-readable explanation of the domain value. |
| 3 | `sort_order` | INTEGER | UQ |  |  | Display order for the domain values. |
| 4 | `is_terminal` | BOOLEAN | - |  | false | True when no further work is expected, so the project drops off the active list. |

### `ref_schedule_status`

*Reference.* Domain of milestone states.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `status_code` | VARCHAR(50) | PK |  |  | Primary key of the domain. |
| 2 | `description` | VARCHAR(200) | - |  |  | Human-readable explanation of the domain value. |
| 3 | `sort_order` | INTEGER | UQ |  |  | Display order for the domain values. |

### `ref_invoice_status`

*Reference.* Domain of invoice states, and which of them count as an outstanding receivable.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `status_code` | VARCHAR(50) | PK |  |  | Primary key of the domain. |
| 2 | `description` | VARCHAR(200) | - |  |  | Human-readable explanation of the domain value. |
| 3 | `sort_order` | INTEGER | UQ |  |  | Display order for the domain values. |
| 4 | `counts_as_receivable` | BOOLEAN | - |  |  | Whether this state means money is still owed. Drives the receivables KPI, so cancelled invoices are no longer counted. |

### `ref_order_status`

*Reference.* Domain of purchase-order states, and which of them count as a payable.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `status_code` | VARCHAR(50) | PK |  |  | Primary key of the domain. |
| 2 | `description` | VARCHAR(200) | - |  |  | Human-readable explanation of the domain value. |
| 3 | `sort_order` | INTEGER | UQ |  |  | Display order for the domain values. |
| 4 | `counts_as_payable` | BOOLEAN | - |  |  | Whether this state means money is still owed to a supplier. |

### `ref_payment_method`

*Reference.* Domain of payment methods.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `method_code` | VARCHAR(50) | PK |  |  | Primary key of the domain. |
| 2 | `description` | VARCHAR(200) | - |  |  | Human-readable explanation of the domain value. |
| 3 | `settlement_days` | INTEGER | - |  |  | Typical days from initiation to value date. Used when timing an expected receipt. |

### `ref_product_category`

*Reference.* Domain of equipment categories.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `category_code` | VARCHAR(50) | PK |  |  | Primary key of the domain. |
| 2 | `description` | VARCHAR(200) | - |  |  | Human-readable explanation of the domain value. |

### `ref_cost_category`

*Reference.* Domain separating direct project costs from operational overhead.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `category_code` | VARCHAR(50) | PK |  |  | Primary key of the domain. |
| 2 | `description` | VARCHAR(200) | - |  |  | Human-readable explanation of the domain value. |
| 3 | `is_indirect` | BOOLEAN | - |  |  | True for overhead, false for direct project cost. |

### `ref_direct_cost_type`

*Reference.* Domain of direct cost types.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `type_code` | VARCHAR(50) | PK |  |  | Primary key of the domain. |
| 2 | `description` | VARCHAR(200) | - |  |  | Human-readable explanation of the domain value. |

### `ref_overhead_category`

*Reference.* Domain of overhead categories.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `category_code` | VARCHAR(50) | PK |  |  | Primary key of the domain. |
| 2 | `description` | VARCHAR(200) | - |  |  | Human-readable explanation of the domain value. |

## Analytical layer (OLAP star schema)

### `dim_date`

*Dimension.* Conformed date spine for the analytical layer.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `date_key` | INTEGER | PK |  |  | Surrogate key in YYYYMMDD form, so the fact table sorts chronologically without a join. |
| 2 | `full_date` | DATE | UQ |  |  | The actual date. |
| 3 | `day_of_week` | VARCHAR(15) | - |  |  | Weekday name, for reporting. |
| 4 | `day_of_month` | INTEGER | - |  |  | Day number within the month. |
| 5 | `month_name` | VARCHAR(15) | - |  |  | Month name, for axis labels. |
| 6 | `month_num` | INTEGER | - |  |  | Month number, for sorting. |
| 7 | `quarter` | INTEGER | - |  |  | Calendar quarter. |
| 8 | `year` | INTEGER | - |  |  | Calendar year. |
| 9 | `is_weekend` | BOOLEAN | - |  |  | True on Saturday and Sunday. Bank transfers do not settle at weekends, which matters for liquidity timing. |

### `dim_project`

*Dimension.* Project attributes for analysis, type-1 overwrite.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `project_key` | BIGINT | PK |  | seq dim_project_project_… | Surrogate key for the dimension, separate from the operational project_id. |
| 2 | `project_id` | BIGINT | UQ |  |  | Natural key back to the operational project. The ETL upserts on this. |
| 3 | `project_name` | VARCHAR(150) | - |  |  | Project name at load time. |
| 4 | `status` | VARCHAR(50) | - |  |  | Project status at load time. Type-1: overwritten, no history kept. |
| 5 | `total_value` | DECIMAL(12,2) | - |  |  | Contract value at load time. |

### `dim_customer`

*Dimension.* Customer attributes for analysis. Follows pseudonymisation of the operational record.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `customer_key` | BIGINT | PK |  | seq dim_customer_custome… | Surrogate key for the dimension. |
| 2 | `customer_id` | BIGINT | UQ |  |  | Natural key back to the operational customer. |
| 3 | `customer_name` | VARCHAR(200) | - |  |  | Display name. Overwritten with ANONYMIZED when the operational record is pseudonymised, so an Art. 17 erasure reaches the analytical layer too. |
| 4 | `city` | VARCHAR(100) | - |  |  | City, for geographic analysis. Redacted on erasure. |
| 5 | `postal_code` | VARCHAR(20) | - |  |  | Postcode, for geographic analysis. Redacted on erasure. |

### `dim_cost_type`

*Dimension.* Cost classification for analysis.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `cost_type_key` | BIGINT | PK |  | seq dim_cost_type_cost_t… | Surrogate key for the dimension. |
| 2 | `cost_category` | VARCHAR(50) | UQ |  |  | Direct Project or Operational Overhead. |
| 3 | `cost_subcategory` | VARCHAR(50) | UQ |  |  | The specific type, e.g. Materials, Rent, Advertising. |
| 4 | `is_indirect` | BOOLEAN | - |  |  | True for overhead. Lets a report split direct from indirect without a join. |

### `fact_daily_cashflow`

*Fact.* One row per date per project: expected cash in, out and net. Grain is date x project.

| # | Attribute | Type | Key | N | Default | Description |
|---|---|---|---|---|---|---|
| 1 | `fact_id` | BIGINT | PK |  | seq fact_daily_cashflow_… | Surrogate key. |
| 2 | `date_key` | INTEGER | FK |  |  | Date dimension. Mandatory: every fact happens on a day. |
| 3 | `project_key` | BIGINT | FK | Y |  | Project dimension. Null for company overhead, which belongs to no project. |
| 4 | `customer_key` | BIGINT | FK | Y |  | Customer dimension. Null for outgoing movements. |
| 5 | `cost_type_key` | BIGINT | FK | Y |  | Cost type dimension. Null for incoming movements. |
| 6 | `expected_cash_in` | DECIMAL(12,2) | - |  | 0.00 | Additive measure: money expected in. |
| 7 | `expected_cash_out` | DECIMAL(12,2) | - |  | 0.00 | Additive measure: money expected out. |
| 8 | `net_cashflow` | DECIMAL(12,2) | - |  |  | Additive measure: in minus out. Summing this over a date range gives the projected position. |

