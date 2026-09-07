-- ============================================================================
-- Baer Solar cash flow management system
-- Full schema DDL, generated directly from the live Supabase project
-- (tppnycgtsrgbnukemtoh) rather than written by hand, so it cannot drift
-- from the database the thesis describes.
--
-- Order: tables, then constraints (primary key, unique, foreign key, check),
-- then secondary indexes, then triggers, then views.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- TABLES
-- ----------------------------------------------------------------------------

CREATE TABLE cashflow_forecast (
    forecast_id bigint NOT NULL DEFAULT nextval('cashflow_forecast_forecast_id_seq'::regclass),
    project_id bigint,
    forecast_date date NOT NULL,
    net_cashflow numeric(12,2) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by varchar(100) NOT NULL DEFAULT 'system'::character varying,
    expected_cash_in numeric(12,2) NOT NULL DEFAULT 0,
    expected_cash_out numeric(12,2) NOT NULL DEFAULT 0,
    flow_source varchar(30)
);

CREATE TABLE cost (
    cost_id bigint NOT NULL DEFAULT nextval('cost_cost_id_seq'::regclass),
    amount numeric(12,2) NOT NULL,
    cost_date date NOT NULL,
    cost_category varchar(50) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by varchar(100) NOT NULL DEFAULT 'system'::character varying
);

CREATE TABLE customer (
    customer_id bigint NOT NULL DEFAULT nextval('customer_customer_id_seq'::regclass),
    first_name varchar(100) NOT NULL,
    last_name varchar(100) NOT NULL,
    company_name varchar(150),
    email varchar(255) NOT NULL,
    phone varchar(50),
    street_name varchar(150) NOT NULL,
    house_number varchar(20) NOT NULL,
    postal_code varchar(20) NOT NULL,
    city varchar(100) NOT NULL,
    country varchar(50) NOT NULL DEFAULT 'Germany'::character varying,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by varchar(100) NOT NULL DEFAULT 'system'::character varying,
    pseudonymized_at timestamptz
);

CREATE TABLE data_erasure_log (
    erasure_id bigint NOT NULL DEFAULT nextval('data_erasure_log_erasure_id_seq'::regclass),
    subject_table varchar(100) NOT NULL,
    subject_id bigint NOT NULL,
    requested_at timestamptz NOT NULL DEFAULT now(),
    executed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    executed_by varchar(100) NOT NULL DEFAULT CURRENT_USER,
    legal_basis_note varchar(500) NOT NULL,
    columns_affected text NOT NULL
);

CREATE TABLE dim_cost_type (
    cost_type_key bigint NOT NULL DEFAULT nextval('dim_cost_type_cost_type_key_seq'::regclass),
    cost_category varchar(50) NOT NULL,
    cost_subcategory varchar(50) NOT NULL,
    is_indirect boolean NOT NULL
);

CREATE TABLE dim_customer (
    customer_key bigint NOT NULL DEFAULT nextval('dim_customer_customer_key_seq'::regclass),
    customer_id bigint NOT NULL,
    customer_name varchar(200) NOT NULL,
    city varchar(100) NOT NULL,
    postal_code varchar(20) NOT NULL
);

CREATE TABLE dim_date (
    date_key integer NOT NULL,
    full_date date NOT NULL,
    day_of_week varchar(15) NOT NULL,
    day_of_month integer NOT NULL,
    month_name varchar(15) NOT NULL,
    month_num integer NOT NULL,
    quarter integer NOT NULL,
    year integer NOT NULL,
    is_weekend boolean NOT NULL
);

CREATE TABLE dim_project (
    project_key bigint NOT NULL DEFAULT nextval('dim_project_project_key_seq'::regclass),
    project_id bigint NOT NULL,
    project_name varchar(150) NOT NULL,
    status varchar(50) NOT NULL,
    total_value numeric(12,2) NOT NULL
);

CREATE TABLE etl_run (
    run_id bigint NOT NULL DEFAULT nextval('etl_run_run_id_seq'::regclass),
    source_system varchar(50) NOT NULL DEFAULT 'SEVDESK'::character varying,
    source_filename varchar(255),
    started_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'Running'::character varying,
    rows_received integer NOT NULL DEFAULT 0,
    rows_promoted integer NOT NULL DEFAULT 0,
    rows_rejected integer NOT NULL DEFAULT 0,
    error_message text,
    triggered_by varchar(100) NOT NULL DEFAULT 'system'::character varying
);

CREATE TABLE fact_daily_cashflow (
    fact_id bigint NOT NULL DEFAULT nextval('fact_daily_cashflow_fact_id_seq'::regclass),
    date_key integer NOT NULL,
    project_key bigint,
    customer_key bigint,
    cost_type_key bigint,
    expected_cash_in numeric(12,2) NOT NULL DEFAULT 0.00,
    expected_cash_out numeric(12,2) NOT NULL DEFAULT 0.00,
    net_cashflow numeric(12,2) NOT NULL
);

CREATE TABLE invoice (
    invoice_id bigint NOT NULL DEFAULT nextval('invoice_invoice_id_seq'::regclass),
    project_id bigint NOT NULL,
    schedule_id bigint,
    invoice_number varchar(50) NOT NULL,
    invoice_date date NOT NULL,
    due_date date NOT NULL,
    amount numeric(12,2) NOT NULL,
    status varchar(50) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by varchar(100) NOT NULL DEFAULT 'system'::character varying,
    milestone_code varchar(30)
);

CREATE TABLE operational_cost (
    cost_id bigint NOT NULL,
    overhead_category varchar(50) NOT NULL,
    cost_category varchar(50) NOT NULL DEFAULT 'Operational Overhead'::character varying
);

CREATE TABLE payment (
    payment_id bigint NOT NULL DEFAULT nextval('payment_payment_id_seq'::regclass),
    invoice_id bigint NOT NULL,
    payment_date date NOT NULL,
    amount numeric(12,2) NOT NULL,
    payment_method varchar(50) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by varchar(100) NOT NULL DEFAULT 'system'::character varying
);

CREATE TABLE payment_schedule (
    schedule_id bigint NOT NULL DEFAULT nextval('payment_schedule_schedule_id_seq'::regclass),
    project_id bigint NOT NULL,
    due_offset_days integer NOT NULL,
    expected_amount numeric(12,2) NOT NULL,
    status varchar(50) NOT NULL DEFAULT 'Pending'::character varying,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by varchar(100) NOT NULL DEFAULT 'system'::character varying,
    milestone_code varchar(30) NOT NULL
);

CREATE TABLE product (
    product_id bigint NOT NULL DEFAULT nextval('product_product_id_seq'::regclass),
    product_name varchar(150) NOT NULL,
    category varchar(50) NOT NULL,
    unit_cost numeric(12,2) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by varchar(100) NOT NULL DEFAULT 'system'::character varying
);

CREATE TABLE project (
    project_id bigint NOT NULL DEFAULT nextval('project_project_id_seq'::regclass),
    customer_id bigint NOT NULL,
    project_name varchar(150) NOT NULL,
    status varchar(50) NOT NULL,
    total_value numeric(12,2) NOT NULL,
    start_date date NOT NULL,
    expected_completion_date date,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by varchar(100) NOT NULL DEFAULT 'system'::character varying
);

CREATE TABLE project_cost (
    cost_id bigint NOT NULL,
    project_id bigint NOT NULL,
    direct_cost_type varchar(50) NOT NULL,
    cost_category varchar(50) NOT NULL DEFAULT 'Direct Project'::character varying
);

CREATE TABLE project_product (
    project_id bigint NOT NULL,
    product_id bigint NOT NULL,
    quantity integer NOT NULL,
    unit_price_charged numeric(12,2) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by varchar(100) NOT NULL DEFAULT 'system'::character varying
);

CREATE TABLE purchase_order (
    order_id bigint NOT NULL DEFAULT nextval('purchase_order_order_id_seq'::regclass),
    supplier_id bigint NOT NULL,
    project_id bigint NOT NULL,
    order_date date NOT NULL,
    expected_delivery_date date NOT NULL,
    total_amount numeric(12,2) NOT NULL,
    status varchar(50) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by varchar(100) NOT NULL DEFAULT 'system'::character varying
);

CREATE TABLE ref_cost_category (
    category_code varchar(50) NOT NULL,
    description varchar(200) NOT NULL,
    is_indirect boolean NOT NULL
);

CREATE TABLE ref_direct_cost_type (
    type_code varchar(50) NOT NULL,
    description varchar(200) NOT NULL
);

CREATE TABLE ref_invoice_status (
    status_code varchar(50) NOT NULL,
    description varchar(200) NOT NULL,
    sort_order integer NOT NULL,
    counts_as_receivable boolean NOT NULL
);

CREATE TABLE ref_milestone_type (
    milestone_code varchar(30) NOT NULL,
    milestone_label varchar(100) NOT NULL,
    percentage numeric(5,2),
    default_due_offset_days integer NOT NULL,
    part_of_split boolean NOT NULL,
    description varchar(200) NOT NULL,
    is_milestone boolean NOT NULL DEFAULT true
);

CREATE TABLE ref_order_status (
    status_code varchar(50) NOT NULL,
    description varchar(200) NOT NULL,
    sort_order integer NOT NULL,
    counts_as_payable boolean NOT NULL
);

CREATE TABLE ref_overhead_category (
    category_code varchar(50) NOT NULL,
    description varchar(200) NOT NULL
);

CREATE TABLE ref_payment_method (
    method_code varchar(50) NOT NULL,
    description varchar(200) NOT NULL,
    settlement_days integer NOT NULL
);

CREATE TABLE ref_product_category (
    category_code varchar(50) NOT NULL,
    description varchar(200) NOT NULL
);

CREATE TABLE ref_project_status (
    status_code varchar(50) NOT NULL,
    description varchar(200) NOT NULL,
    sort_order integer NOT NULL,
    is_terminal boolean NOT NULL DEFAULT false
);

CREATE TABLE ref_schedule_status (
    status_code varchar(50) NOT NULL,
    description varchar(200) NOT NULL,
    sort_order integer NOT NULL
);

CREATE TABLE stg_sevdesk_invoice (
    stg_id bigint NOT NULL DEFAULT nextval('stg_sevdesk_invoice_stg_id_seq'::regclass),
    run_id bigint NOT NULL,
    row_number integer NOT NULL,
    raw_invoice_number varchar(100),
    raw_project_id varchar(100),
    raw_invoice_date varchar(100),
    raw_due_date varchar(100),
    raw_amount varchar(100),
    raw_status varchar(100),
    is_valid boolean NOT NULL DEFAULT false,
    rejection_reason text,
    promoted_at timestamptz
);

CREATE TABLE supplier (
    supplier_id bigint NOT NULL DEFAULT nextval('supplier_supplier_id_seq'::regclass),
    supplier_name varchar(100) NOT NULL,
    credit_limit numeric(12,2) NOT NULL,
    payment_terms_days integer NOT NULL,
    contact_email varchar(255) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by varchar(100) NOT NULL DEFAULT 'system'::character varying
);


-- ----------------------------------------------------------------------------
-- PRIMARY KEYS, UNIQUE CONSTRAINTS, FOREIGN KEYS, CHECK CONSTRAINTS
-- ----------------------------------------------------------------------------

ALTER TABLE cashflow_forecast ADD CONSTRAINT cashflow_forecast_pkey PRIMARY KEY (forecast_id);
ALTER TABLE cashflow_forecast ADD CONSTRAINT cashflow_forecast_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(project_id) ON DELETE RESTRICT;
ALTER TABLE cashflow_forecast ADD CONSTRAINT cashflow_forecast_expected_cash_in_check CHECK ((expected_cash_in >= (0)::numeric));
ALTER TABLE cashflow_forecast ADD CONSTRAINT cashflow_forecast_expected_cash_out_check CHECK ((expected_cash_out >= (0)::numeric));

ALTER TABLE cost ADD CONSTRAINT cost_pkey PRIMARY KEY (cost_id);
ALTER TABLE cost ADD CONSTRAINT uq_cost_id_category UNIQUE (cost_id, cost_category);
ALTER TABLE cost ADD CONSTRAINT cost_category_fkey FOREIGN KEY (cost_category) REFERENCES ref_cost_category(category_code) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE cost ADD CONSTRAINT cost_amount_check CHECK ((amount >= (0)::numeric));

ALTER TABLE customer ADD CONSTRAINT customer_pkey PRIMARY KEY (customer_id);
ALTER TABLE customer ADD CONSTRAINT customer_email_key UNIQUE (email);

ALTER TABLE data_erasure_log ADD CONSTRAINT data_erasure_log_pkey PRIMARY KEY (erasure_id);

ALTER TABLE dim_cost_type ADD CONSTRAINT dim_cost_type_pkey PRIMARY KEY (cost_type_key);
ALTER TABLE dim_cost_type ADD CONSTRAINT uq_dim_cost_type_natural UNIQUE (cost_category, cost_subcategory);

ALTER TABLE dim_customer ADD CONSTRAINT dim_customer_pkey PRIMARY KEY (customer_key);
ALTER TABLE dim_customer ADD CONSTRAINT uq_dim_customer_natural UNIQUE (customer_id);

ALTER TABLE dim_date ADD CONSTRAINT dim_date_pkey PRIMARY KEY (date_key);
ALTER TABLE dim_date ADD CONSTRAINT dim_date_full_date_key UNIQUE (full_date);

ALTER TABLE dim_project ADD CONSTRAINT dim_project_pkey PRIMARY KEY (project_key);
ALTER TABLE dim_project ADD CONSTRAINT uq_dim_project_natural UNIQUE (project_id);

ALTER TABLE etl_run ADD CONSTRAINT etl_run_pkey PRIMARY KEY (run_id);
ALTER TABLE etl_run ADD CONSTRAINT etl_run_status_check CHECK (((status)::text = ANY ((ARRAY['Running'::character varying, 'Succeeded'::character varying, 'Failed'::character varying, 'Partial'::character varying])::text[])));

ALTER TABLE fact_daily_cashflow ADD CONSTRAINT fact_daily_cashflow_pkey PRIMARY KEY (fact_id);
ALTER TABLE fact_daily_cashflow ADD CONSTRAINT fact_daily_cashflow_cost_type_key_fkey FOREIGN KEY (cost_type_key) REFERENCES dim_cost_type(cost_type_key) ON DELETE RESTRICT;
ALTER TABLE fact_daily_cashflow ADD CONSTRAINT fact_daily_cashflow_customer_key_fkey FOREIGN KEY (customer_key) REFERENCES dim_customer(customer_key) ON DELETE RESTRICT;
ALTER TABLE fact_daily_cashflow ADD CONSTRAINT fact_daily_cashflow_date_key_fkey FOREIGN KEY (date_key) REFERENCES dim_date(date_key) ON DELETE RESTRICT;
ALTER TABLE fact_daily_cashflow ADD CONSTRAINT fact_daily_cashflow_project_key_fkey FOREIGN KEY (project_key) REFERENCES dim_project(project_key) ON DELETE RESTRICT;
ALTER TABLE fact_daily_cashflow ADD CONSTRAINT fact_daily_cashflow_expected_cash_in_check CHECK ((expected_cash_in >= (0)::numeric));
ALTER TABLE fact_daily_cashflow ADD CONSTRAINT fact_daily_cashflow_expected_cash_out_check CHECK ((expected_cash_out >= (0)::numeric));

ALTER TABLE invoice ADD CONSTRAINT invoice_pkey PRIMARY KEY (invoice_id);
ALTER TABLE invoice ADD CONSTRAINT invoice_invoice_number_key UNIQUE (invoice_number);
ALTER TABLE invoice ADD CONSTRAINT invoice_milestone_code_fkey FOREIGN KEY (milestone_code) REFERENCES ref_milestone_type(milestone_code) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE invoice ADD CONSTRAINT invoice_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(project_id) ON DELETE RESTRICT;
ALTER TABLE invoice ADD CONSTRAINT invoice_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES payment_schedule(schedule_id) ON DELETE RESTRICT;
ALTER TABLE invoice ADD CONSTRAINT invoice_status_fkey FOREIGN KEY (status) REFERENCES ref_invoice_status(status_code) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE invoice ADD CONSTRAINT invoice_amount_check CHECK ((amount >= (0)::numeric));

ALTER TABLE operational_cost ADD CONSTRAINT operational_cost_pkey PRIMARY KEY (cost_id);
ALTER TABLE operational_cost ADD CONSTRAINT operational_cost_category_fkey FOREIGN KEY (overhead_category) REFERENCES ref_overhead_category(category_code) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE operational_cost ADD CONSTRAINT operational_cost_cost_fkey FOREIGN KEY (cost_id, cost_category) REFERENCES cost(cost_id, cost_category) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE operational_cost ADD CONSTRAINT chk_operational_cost_discriminator CHECK (((cost_category)::text = 'Operational Overhead'::text));

ALTER TABLE payment ADD CONSTRAINT payment_pkey PRIMARY KEY (payment_id);
ALTER TABLE payment ADD CONSTRAINT payment_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoice(invoice_id) ON DELETE RESTRICT;
ALTER TABLE payment ADD CONSTRAINT payment_method_fkey FOREIGN KEY (payment_method) REFERENCES ref_payment_method(method_code) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE payment ADD CONSTRAINT payment_amount_check CHECK ((amount > (0)::numeric));

ALTER TABLE payment_schedule ADD CONSTRAINT payment_schedule_pkey PRIMARY KEY (schedule_id);
ALTER TABLE payment_schedule ADD CONSTRAINT uq_payment_schedule_project_milestone UNIQUE (project_id, milestone_code);
ALTER TABLE payment_schedule ADD CONSTRAINT payment_schedule_milestone_code_fkey FOREIGN KEY (milestone_code) REFERENCES ref_milestone_type(milestone_code) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE payment_schedule ADD CONSTRAINT payment_schedule_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(project_id) ON DELETE RESTRICT;
ALTER TABLE payment_schedule ADD CONSTRAINT payment_schedule_status_fkey FOREIGN KEY (status) REFERENCES ref_schedule_status(status_code) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE payment_schedule ADD CONSTRAINT payment_schedule_due_offset_days_check CHECK ((due_offset_days >= 0));
ALTER TABLE payment_schedule ADD CONSTRAINT payment_schedule_expected_amount_check CHECK ((expected_amount >= (0)::numeric));

ALTER TABLE product ADD CONSTRAINT product_pkey PRIMARY KEY (product_id);
ALTER TABLE product ADD CONSTRAINT product_category_fkey FOREIGN KEY (category) REFERENCES ref_product_category(category_code) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE product ADD CONSTRAINT product_unit_cost_check CHECK ((unit_cost >= (0)::numeric));

ALTER TABLE project ADD CONSTRAINT project_pkey PRIMARY KEY (project_id);
ALTER TABLE project ADD CONSTRAINT project_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customer(customer_id) ON DELETE RESTRICT;
ALTER TABLE project ADD CONSTRAINT project_status_fkey FOREIGN KEY (status) REFERENCES ref_project_status(status_code) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE project ADD CONSTRAINT project_total_value_check CHECK ((total_value >= (0)::numeric));

ALTER TABLE project_cost ADD CONSTRAINT project_cost_pkey PRIMARY KEY (cost_id);
ALTER TABLE project_cost ADD CONSTRAINT project_cost_cost_fkey FOREIGN KEY (cost_id, cost_category) REFERENCES cost(cost_id, cost_category) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE project_cost ADD CONSTRAINT project_cost_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(project_id) ON DELETE RESTRICT;
ALTER TABLE project_cost ADD CONSTRAINT project_cost_type_fkey FOREIGN KEY (direct_cost_type) REFERENCES ref_direct_cost_type(type_code) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE project_cost ADD CONSTRAINT chk_project_cost_discriminator CHECK (((cost_category)::text = 'Direct Project'::text));

ALTER TABLE project_product ADD CONSTRAINT project_product_pkey PRIMARY KEY (project_id, product_id);
ALTER TABLE project_product ADD CONSTRAINT project_product_product_id_fkey FOREIGN KEY (product_id) REFERENCES product(product_id) ON DELETE RESTRICT;
ALTER TABLE project_product ADD CONSTRAINT project_product_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(project_id) ON DELETE RESTRICT;
ALTER TABLE project_product ADD CONSTRAINT project_product_quantity_check CHECK ((quantity > 0));
ALTER TABLE project_product ADD CONSTRAINT project_product_unit_price_charged_check CHECK ((unit_price_charged >= (0)::numeric));

ALTER TABLE purchase_order ADD CONSTRAINT purchase_order_pkey PRIMARY KEY (order_id);
ALTER TABLE purchase_order ADD CONSTRAINT purchase_order_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(project_id) ON DELETE RESTRICT;
ALTER TABLE purchase_order ADD CONSTRAINT purchase_order_status_fkey FOREIGN KEY (status) REFERENCES ref_order_status(status_code) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE purchase_order ADD CONSTRAINT purchase_order_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES supplier(supplier_id) ON DELETE RESTRICT;
ALTER TABLE purchase_order ADD CONSTRAINT purchase_order_total_amount_check CHECK ((total_amount >= (0)::numeric));

ALTER TABLE ref_cost_category ADD CONSTRAINT ref_cost_category_pkey PRIMARY KEY (category_code);
ALTER TABLE ref_direct_cost_type ADD CONSTRAINT ref_direct_cost_type_pkey PRIMARY KEY (type_code);

ALTER TABLE ref_invoice_status ADD CONSTRAINT ref_invoice_status_pkey PRIMARY KEY (status_code);
ALTER TABLE ref_invoice_status ADD CONSTRAINT ref_invoice_status_sort_order_key UNIQUE (sort_order);

ALTER TABLE ref_milestone_type ADD CONSTRAINT ref_milestone_type_pkey PRIMARY KEY (milestone_code);
ALTER TABLE ref_milestone_type ADD CONSTRAINT ref_milestone_type_milestone_label_key UNIQUE (milestone_label);
ALTER TABLE ref_milestone_type ADD CONSTRAINT ref_milestone_type_default_due_offset_days_check CHECK ((default_due_offset_days >= 0));
ALTER TABLE ref_milestone_type ADD CONSTRAINT ref_milestone_type_percentage_check CHECK (((percentage IS NULL) OR ((percentage > (0)::numeric) AND (percentage <= (100)::numeric))));

ALTER TABLE ref_order_status ADD CONSTRAINT ref_order_status_pkey PRIMARY KEY (status_code);
ALTER TABLE ref_order_status ADD CONSTRAINT ref_order_status_sort_order_key UNIQUE (sort_order);

ALTER TABLE ref_overhead_category ADD CONSTRAINT ref_overhead_category_pkey PRIMARY KEY (category_code);

ALTER TABLE ref_payment_method ADD CONSTRAINT ref_payment_method_pkey PRIMARY KEY (method_code);
ALTER TABLE ref_payment_method ADD CONSTRAINT ref_payment_method_settlement_days_check CHECK ((settlement_days >= 0));

ALTER TABLE ref_product_category ADD CONSTRAINT ref_product_category_pkey PRIMARY KEY (category_code);

ALTER TABLE ref_project_status ADD CONSTRAINT ref_project_status_pkey PRIMARY KEY (status_code);
ALTER TABLE ref_project_status ADD CONSTRAINT ref_project_status_sort_order_key UNIQUE (sort_order);

ALTER TABLE ref_schedule_status ADD CONSTRAINT ref_schedule_status_pkey PRIMARY KEY (status_code);
ALTER TABLE ref_schedule_status ADD CONSTRAINT ref_schedule_status_sort_order_key UNIQUE (sort_order);

ALTER TABLE stg_sevdesk_invoice ADD CONSTRAINT stg_sevdesk_invoice_pkey PRIMARY KEY (stg_id);
ALTER TABLE stg_sevdesk_invoice ADD CONSTRAINT stg_sevdesk_invoice_run_id_fkey FOREIGN KEY (run_id) REFERENCES etl_run(run_id) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE supplier ADD CONSTRAINT supplier_pkey PRIMARY KEY (supplier_id);
ALTER TABLE supplier ADD CONSTRAINT supplier_name_unique UNIQUE (supplier_name);
ALTER TABLE supplier ADD CONSTRAINT supplier_credit_limit_check CHECK ((credit_limit >= (0)::numeric));
ALTER TABLE supplier ADD CONSTRAINT supplier_payment_terms_days_check CHECK ((payment_terms_days >= 0));


-- ----------------------------------------------------------------------------
-- SECONDARY INDEXES (35)
-- Every foreign key gets one, except the two composite foreign keys on
-- operational_cost and project_cost back to cost(cost_id, cost_category):
-- cost_id alone is already that table's primary key, so a dedicated index
-- on the composite pair would only duplicate it.
-- ----------------------------------------------------------------------------

CREATE INDEX idx_cashflow_forecast_date ON cashflow_forecast USING btree (forecast_date);
CREATE INDEX idx_cashflow_forecast_project_id ON cashflow_forecast USING btree (project_id);
CREATE INDEX idx_cost_category_fk ON cost USING btree (cost_category);
CREATE INDEX idx_cost_date ON cost USING btree (cost_date);
CREATE INDEX idx_erasure_log_subject ON data_erasure_log USING btree (subject_table, subject_id);
CREATE INDEX idx_etl_run_started ON etl_run USING btree (started_at DESC);
CREATE INDEX idx_fact_cashflow_cost_type_key ON fact_daily_cashflow USING btree (cost_type_key);
CREATE INDEX idx_fact_cashflow_customer_key ON fact_daily_cashflow USING btree (customer_key);
CREATE INDEX idx_fact_cashflow_date_key ON fact_daily_cashflow USING btree (date_key);
CREATE INDEX idx_fact_cashflow_project_key ON fact_daily_cashflow USING btree (project_key);
CREATE INDEX idx_invoice_dates ON invoice USING btree (invoice_date, due_date);
CREATE INDEX idx_invoice_milestone ON invoice USING btree (milestone_code);
CREATE INDEX idx_invoice_project_id ON invoice USING btree (project_id);
CREATE INDEX idx_invoice_schedule_id ON invoice USING btree (schedule_id);
CREATE INDEX idx_invoice_status_fk ON invoice USING btree (status);
CREATE INDEX idx_operational_cost_category_fk ON operational_cost USING btree (overhead_category);
CREATE INDEX idx_payment_date ON payment USING btree (payment_date);
CREATE INDEX idx_payment_invoice_id ON payment USING btree (invoice_id);
CREATE INDEX idx_payment_method_fk ON payment USING btree (payment_method);
CREATE INDEX idx_payment_schedule_milestone ON payment_schedule USING btree (milestone_code);
CREATE INDEX idx_payment_schedule_project_id ON payment_schedule USING btree (project_id);
CREATE INDEX idx_payment_schedule_status_fk ON payment_schedule USING btree (status);
CREATE INDEX idx_product_category_fk ON product USING btree (category);
CREATE INDEX idx_project_customer_id ON project USING btree (customer_id);
CREATE INDEX idx_project_status_date ON project USING btree (status, start_date);
CREATE INDEX idx_project_status_fk ON project USING btree (status);
CREATE INDEX idx_project_cost_project_id ON project_cost USING btree (project_id);
CREATE INDEX idx_project_cost_type_fk ON project_cost USING btree (direct_cost_type);
CREATE INDEX idx_project_product_product_id ON project_product USING btree (product_id);
CREATE INDEX idx_purchase_order_date ON purchase_order USING btree (order_date);
CREATE INDEX idx_purchase_order_project_id ON purchase_order USING btree (project_id);
CREATE INDEX idx_purchase_order_status_fk ON purchase_order USING btree (status);
CREATE INDEX idx_purchase_order_supplier_id ON purchase_order USING btree (supplier_id);
CREATE INDEX idx_stg_invalid ON stg_sevdesk_invoice USING btree (run_id) WHERE (is_valid = false);
CREATE INDEX idx_stg_run ON stg_sevdesk_invoice USING btree (run_id);


-- ----------------------------------------------------------------------------
-- TRIGGERS (11 tables, one shared function)
-- ----------------------------------------------------------------------------

CREATE TRIGGER trg_cashflow_forecast_set_updated_at BEFORE UPDATE ON cashflow_forecast FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_cost_set_updated_at BEFORE UPDATE ON cost FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_customer_set_updated_at BEFORE UPDATE ON customer FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_invoice_set_updated_at BEFORE UPDATE ON invoice FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_payment_set_updated_at BEFORE UPDATE ON payment FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_payment_schedule_set_updated_at BEFORE UPDATE ON payment_schedule FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_product_set_updated_at BEFORE UPDATE ON product FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_project_set_updated_at BEFORE UPDATE ON project FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_project_product_set_updated_at BEFORE UPDATE ON project_product FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_purchase_order_set_updated_at BEFORE UPDATE ON purchase_order FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_supplier_set_updated_at BEFORE UPDATE ON supplier FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ----------------------------------------------------------------------------
-- VIEWS (10)
-- All ten are security_invoker except v_customer_minimised, which needs
-- owner rights on purpose: app_viewer has no grant on the customer table
-- at all, only on this view, so owner rights are how the view can expose
-- its minimised columns to that role in the first place.
-- ----------------------------------------------------------------------------

CREATE VIEW v_cashflow_30day WITH (security_invoker=true) AS
 SELECT d.full_date,
    COALESCE(sum(f.expected_cash_in), 0::numeric) AS cash_in,
    COALESCE(sum(f.expected_cash_out), 0::numeric) AS cash_out,
    COALESCE(sum(f.net_cashflow), 0::numeric) AS net_cashflow,
    sum(COALESCE(sum(f.net_cashflow), 0::numeric)) OVER (ORDER BY d.full_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_position
   FROM dim_date d
     LEFT JOIN fact_daily_cashflow f ON f.date_key = d.date_key
  WHERE d.full_date >= CURRENT_DATE AND d.full_date <= (CURRENT_DATE + 30)
  GROUP BY d.full_date
  ORDER BY d.full_date;

CREATE VIEW v_cost_isa_violations WITH (security_invoker=true) AS
 SELECT c.cost_id,
    c.cost_category,
    pc.cost_id IS NOT NULL AS has_project_subtype,
    oc.cost_id IS NOT NULL AS has_overhead_subtype
   FROM cost c
     LEFT JOIN project_cost pc ON pc.cost_id = c.cost_id
     LEFT JOIN operational_cost oc ON oc.cost_id = c.cost_id
  WHERE pc.cost_id IS NULL AND oc.cost_id IS NULL OR pc.cost_id IS NOT NULL AND oc.cost_id IS NOT NULL;

CREATE VIEW v_customer_data_export WITH (security_invoker=true) AS
 SELECT c.customer_id,
    c.first_name,
    c.last_name,
    c.company_name,
    c.email,
    c.phone,
    c.street_name,
    c.house_number,
    c.postal_code,
    c.city,
    c.country,
    p.project_id,
    p.project_name,
    p.status AS project_status,
    p.total_value,
    i.invoice_number,
    i.invoice_date,
    i.amount AS invoice_amount,
    i.status AS invoice_status,
    pay.payment_date,
    pay.amount AS payment_amount,
    pay.payment_method
   FROM customer c
     LEFT JOIN project p ON p.customer_id = c.customer_id
     LEFT JOIN invoice i ON i.project_id = p.project_id
     LEFT JOIN payment pay ON pay.invoice_id = i.invoice_id;

CREATE VIEW v_customer_minimised AS
 SELECT customer_id,
    city,
    "left"(postal_code::text, 2) AS postal_area,
    country,
    pseudonymized_at IS NOT NULL AS is_pseudonymised
   FROM customer c;

CREATE VIEW v_dashboard_kpi WITH (security_invoker=true) AS
 SELECT ( SELECT COALESCE(sum(i.amount), 0::numeric) AS "coalesce"
           FROM invoice i
             JOIN ref_invoice_status s ON s.status_code::text = i.status::text
          WHERE s.counts_as_receivable) AS outstanding_receivables,
    ( SELECT COALESCE(sum(v_supplier_watch.total_amount), 0::numeric) AS "coalesce"
           FROM v_supplier_watch
          WHERE v_supplier_watch.alert_level = ANY (ARRAY['DUE_SOON'::text, 'OVERDUE'::text])) AS supplier_due_7_days,
    ( SELECT COALESCE(sum(v_cashflow_30day.net_cashflow), 0::numeric) AS "coalesce"
           FROM v_cashflow_30day) AS projected_30day_net,
    ( SELECT count(*) AS count
           FROM project p
             JOIN ref_project_status r ON r.status_code::text = p.status::text
          WHERE NOT r.is_terminal) AS active_projects,
    ( SELECT count(*) AS count
           FROM v_liquidity_alert
          WHERE v_liquidity_alert.liquidity_status = 'NEGATIVE'::text) AS days_negative_next_30;

CREATE VIEW v_etl_rejections WITH (security_invoker=true) AS
 SELECT r.run_id,
    r.source_filename,
    r.started_at,
    s.row_number,
    s.raw_invoice_number,
    s.raw_project_id,
    s.raw_amount,
    s.rejection_reason
   FROM stg_sevdesk_invoice s
     JOIN etl_run r ON r.run_id = s.run_id
  WHERE s.is_valid = false
  ORDER BY r.started_at DESC, s.row_number;

CREATE VIEW v_liquidity_alert WITH (security_invoker=true) AS
 SELECT full_date,
    cumulative_position,
        CASE
            WHEN cumulative_position < 0::numeric THEN 'NEGATIVE'::text
            WHEN cumulative_position < 10000::numeric THEN 'BELOW_BUFFER'::text
            ELSE 'OK'::text
        END AS liquidity_status
   FROM v_cashflow_30day
  WHERE cumulative_position < 10000::numeric
  ORDER BY full_date;

CREATE VIEW v_payment_schedule WITH (security_invoker=true) AS
 SELECT ps.schedule_id,
    ps.project_id,
    ps.milestone_code,
    mt.milestone_label,
    mt.percentage,
    ps.due_offset_days,
    ps.expected_amount,
    ps.status,
    ps.created_at,
    ps.updated_at
   FROM payment_schedule ps
     JOIN ref_milestone_type mt ON mt.milestone_code::text = ps.milestone_code::text;

CREATE VIEW v_project_profitability WITH (security_invoker=true) AS
 SELECT p.project_id,
    p.project_name,
    c.city,
    p.status,
    p.total_value,
    COALESCE(dc.direct_cost, 0::numeric) AS direct_cost,
    COALESCE(po.supplier_cost, 0::numeric) AS supplier_cost,
    p.total_value - COALESCE(dc.direct_cost, 0::numeric) - COALESCE(po.supplier_cost, 0::numeric) AS gross_margin,
    round(100.0 * (p.total_value - COALESCE(dc.direct_cost, 0::numeric) - COALESCE(po.supplier_cost, 0::numeric)) / NULLIF(p.total_value, 0::numeric), 1) AS margin_pct,
    COALESCE(rec.invoiced, 0::numeric) AS invoiced_to_date,
    COALESCE(pay.received, 0::numeric) AS received_to_date
   FROM project p
     JOIN customer c ON c.customer_id = p.customer_id
     LEFT JOIN ( SELECT pc.project_id,
            sum(co.amount) AS direct_cost
           FROM project_cost pc
             JOIN cost co ON co.cost_id = pc.cost_id
          GROUP BY pc.project_id) dc ON dc.project_id = p.project_id
     LEFT JOIN ( SELECT purchase_order.project_id,
            sum(purchase_order.total_amount) AS supplier_cost
           FROM purchase_order
          GROUP BY purchase_order.project_id) po ON po.project_id = p.project_id
     LEFT JOIN ( SELECT invoice.project_id,
            sum(invoice.amount) AS invoiced
           FROM invoice
          GROUP BY invoice.project_id) rec ON rec.project_id = p.project_id
     LEFT JOIN ( SELECT i.project_id,
            sum(pm.amount) AS received
           FROM payment pm
             JOIN invoice i ON i.invoice_id = pm.invoice_id
          GROUP BY i.project_id) pay ON pay.project_id = p.project_id;

CREATE VIEW v_supplier_watch WITH (security_invoker=true) AS
 SELECT po.order_id,
    s.supplier_name,
    s.credit_limit,
    s.payment_terms_days,
    p.project_name,
    po.order_date,
    po.expected_delivery_date,
    po.order_date + s.payment_terms_days AS payment_due_date,
    po.order_date + s.payment_terms_days - CURRENT_DATE AS days_until_due,
    po.total_amount,
    po.status,
        CASE
            WHEN (po.order_date + s.payment_terms_days) < CURRENT_DATE THEN 'OVERDUE'::text
            WHEN (po.order_date + s.payment_terms_days - CURRENT_DATE) <= 7 THEN 'DUE_SOON'::text
            ELSE 'SCHEDULED'::text
        END AS alert_level
   FROM purchase_order po
     JOIN supplier s ON s.supplier_id = po.supplier_id
     JOIN project p ON p.project_id = po.project_id
     JOIN ref_order_status ros ON ros.status_code::text = po.status::text
  WHERE ros.counts_as_payable
  ORDER BY (po.order_date + s.payment_terms_days);
