# Where every database table appears

31 tables. Each one is either drawn on the ERD or has a written reason for
not being drawn. Nothing is unaccounted for.

This table belongs in the logical layer chapter, next to the ERD. It is
what turns "the diagram doesn't show everything" into a stated design
decision.

## Drawn on the ERD — 13 business entities

| Table | On the ERD as |
|---|---|
| `customer` | Customer |
| `project` | Project |
| `payment_schedule` | PaymentSchedule |
| `invoice` | Invoice |
| `payment` | Payment (weak entity) |
| `supplier` | Supplier |
| `purchase_order` | PurchaseOrder |
| `product` | Product |
| `project_product` | ProjectProduct (weak entity) |
| `cost` | Cost (ISA supertype) |
| `project_cost` | ProjectCost (ISA subtype) |
| `operational_cost` | OperationalCost (ISA subtype) |
| `cashflow_forecast` | CashflowForecast |

## Not drawn — attribute domains, 10 tables

Each stores the set of values one attribute may take. Conceptually these
are domains, not entities: `status` is an attribute of Project with a
limited value set, and the table is how that limit is enforced.

Implemented as tables rather than CHECK constraints so that adding a value
is a data change instead of a schema migration, and so each value can
carry attributes of its own — `ref_invoice_status.counts_as_receivable`
is what stops cancelled invoices being counted as money owed.

All ten, with their values, are in the data dictionary.

`ref_milestone_type` · `ref_project_status` · `ref_schedule_status` ·
`ref_invoice_status` · `ref_order_status` · `ref_payment_method` ·
`ref_product_category` · `ref_cost_category` · `ref_direct_cost_type` ·
`ref_overhead_category`

## Not drawn — analytical layer, 5 tables

The OLAP star schema. A different workload with its own modelling
convention, shown as a dimensional diagram in the technical layer chapter.
Drawing a dimensional model in Chen notation would mix two conventions in
one diagram.

`fact_daily_cashflow` · `dim_date` · `dim_project` · `dim_customer` ·
`dim_cost_type`

## Not drawn — pipeline and audit, 3 tables

Support the import process and the accountability duty under Art. 5(2)
GDPR. They record what the system did; they are not things the business
has.

`etl_run` · `stg_sevdesk_invoice` · `data_erasure_log`
