-- ============================================================================
-- Baer Solar cash flow management system
-- Business logic and automation, generated directly from the live
-- Supabase project (tppnycgtsrgbnukemtoh). These eleven functions and
-- procedures implement the business rules described in Chapter 5, the
-- pipeline described in Chapter 8, and the erasure procedure described
-- in Chapter 6.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- set_updated_at: the shared trigger function behind all eleven
-- created_at/updated_at audit triggers (Chapter 7, Chapter 8).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$function$;


-- ----------------------------------------------------------------------------
-- sp_generate_payment_schedule: BR-1 (Chapter 5).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE public.sp_generate_payment_schedule(IN p_project_id bigint)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $procedure$
DECLARE v_total NUMERIC(12,2);
BEGIN
    SELECT total_value INTO v_total FROM project WHERE project_id = p_project_id;
    IF v_total IS NULL THEN
        RAISE EXCEPTION 'Project % does not exist', p_project_id;
    END IF;

    INSERT INTO payment_schedule
        (project_id, milestone_code, due_offset_days, expected_amount, status, created_by)
    SELECT p_project_id, mt.milestone_code, mt.default_due_offset_days,
           round(v_total * mt.percentage / 100, 2), 'Pending', 'rule:BR-1'
    FROM ref_milestone_type mt
    WHERE mt.is_milestone
      AND mt.part_of_split = (v_total >= 3000)
    ON CONFLICT (project_id, milestone_code) DO UPDATE
        SET expected_amount = EXCLUDED.expected_amount;
END;
$procedure$;


-- ----------------------------------------------------------------------------
-- sp_apply_milestone_rules: BR-2 (Chapter 5). Recomputes every invoice's
-- classification each run rather than only new ones, then links a
-- classified invoice to its schedule row and advances that row's status.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE public.sp_apply_milestone_rules(IN p_project_id bigint DEFAULT NULL::bigint)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $procedure$
DECLARE
    v_threshold CONSTANT NUMERIC(12,2) := 3000.00;
BEGIN
    WITH scope AS (
        SELECT i.invoice_id, i.project_id, i.invoice_date, i.invoice_number,
               i.amount, p.total_value
        FROM invoice i
        JOIN project p ON p.project_id = i.project_id
        WHERE p_project_id IS NULL OR i.project_id = p_project_id
    ),
    classified AS (
        SELECT s.*,
               (s.total_value < v_threshold) AS project_below_threshold,
               (s.amount      < v_threshold) AS invoice_below_threshold
        FROM scope s
    ),
    sequenced AS (
        SELECT c.*,
               CASE WHEN c.project_below_threshold OR c.invoice_below_threshold THEN NULL
                    ELSE row_number() OVER (
                            PARTITION BY c.project_id
                            ORDER BY c.invoice_date, c.invoice_number)
               END AS milestone_rank
        FROM classified c
    ),
    resolved AS (
        SELECT invoice_id,
               CASE
                   WHEN project_below_threshold THEN 'SINGLE_PAYMENT'
                   WHEN invoice_below_threshold THEN 'ADJUSTMENT'
                   WHEN milestone_rank = 1      THEN 'STAGE_1_ROOF'
                   WHEN milestone_rank = 2      THEN 'STAGE_2_COMMISSIONING'
                   ELSE 'ADJUSTMENT'
               END AS milestone_code
        FROM sequenced
    )
    UPDATE invoice i
    SET milestone_code = r.milestone_code
    FROM resolved r
    WHERE i.invoice_id = r.invoice_id
      AND i.milestone_code IS DISTINCT FROM r.milestone_code;

    -- Only real milestones consume a schedule slot.
    UPDATE invoice i
    SET schedule_id = ps.schedule_id
    FROM payment_schedule ps
    JOIN ref_milestone_type mt ON mt.milestone_code = ps.milestone_code
    WHERE ps.project_id = i.project_id
      AND ps.milestone_code = i.milestone_code
      AND mt.is_milestone
      AND (p_project_id IS NULL OR i.project_id = p_project_id)
      AND i.schedule_id IS DISTINCT FROM ps.schedule_id;

    UPDATE payment_schedule ps SET status = 'Invoiced'
    WHERE ps.status = 'Pending'
      AND (p_project_id IS NULL OR ps.project_id = p_project_id)
      AND EXISTS (SELECT 1 FROM invoice i WHERE i.schedule_id = ps.schedule_id);

    UPDATE payment_schedule ps SET status = 'Paid'
    WHERE ps.status <> 'Paid'
      AND (p_project_id IS NULL OR ps.project_id = p_project_id)
      AND EXISTS (SELECT 1 FROM invoice i
                  WHERE i.schedule_id = ps.schedule_id AND i.status = 'Paid');
END;
$procedure$;


-- ----------------------------------------------------------------------------
-- sp_refresh_cashflow_forecast: BR-3 (Chapter 5). Clears future rows and
-- reinserts all three flows for the horizon: customer milestones, supplier
-- orders, and operational overhead.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE public.sp_refresh_cashflow_forecast(IN p_horizon_days integer DEFAULT 30)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $procedure$
BEGIN
    DELETE FROM cashflow_forecast WHERE forecast_date >= CURRENT_DATE;

    -- incoming: unsettled customer milestones
    INSERT INTO cashflow_forecast
        (project_id, forecast_date, expected_cash_in, expected_cash_out, net_cashflow, flow_source, created_by)
    SELECT ps.project_id,
           p.start_date + ps.due_offset_days,
           ps.expected_amount, 0, ps.expected_amount,
           'customer_milestone', 'rule:BR-3'
    FROM payment_schedule ps
    JOIN project p ON p.project_id = ps.project_id
    WHERE ps.status IN ('Pending','Invoiced','Overdue')
      AND p.start_date + ps.due_offset_days
          BETWEEN CURRENT_DATE AND CURRENT_DATE + p_horizon_days;

    -- outgoing: supplier obligations, triggered by the order date
    INSERT INTO cashflow_forecast
        (project_id, forecast_date, expected_cash_in, expected_cash_out, net_cashflow, flow_source, created_by)
    SELECT po.project_id,
           po.order_date + s.payment_terms_days,
           0, po.total_amount, -po.total_amount,
           'supplier_order', 'rule:BR-3'
    FROM purchase_order po
    JOIN supplier s ON s.supplier_id = po.supplier_id
    JOIN ref_order_status ros ON ros.status_code = po.status
    WHERE ros.counts_as_payable
      AND po.order_date + s.payment_terms_days
          BETWEEN CURRENT_DATE AND CURRENT_DATE + p_horizon_days;

    -- outgoing: scheduled overhead
    INSERT INTO cashflow_forecast
        (project_id, forecast_date, expected_cash_in, expected_cash_out, net_cashflow, flow_source, created_by)
    SELECT NULL, c.cost_date, 0, c.amount, -c.amount, 'operational_overhead', 'rule:BR-3'
    FROM cost c
    JOIN operational_cost oc ON oc.cost_id = c.cost_id
    WHERE c.cost_date BETWEEN CURRENT_DATE AND CURRENT_DATE + p_horizon_days;
END;
$procedure$;


-- ----------------------------------------------------------------------------
-- sp_refresh_cashflow_star: rebuilds the OLAP star schema (Chapter 8,
-- section 8.4). Operational overhead is read directly from cost/
-- operational_cost so it can carry a real cost_type_key; customer
-- milestones and supplier orders keep cost_type_key null, a documented
-- boundary rather than an oversight, since cashflow_forecast has already
-- lost the cost_id a lookup would need and neither flow has a real cost
-- type to begin with.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE public.sp_refresh_cashflow_star(IN p_horizon_days integer DEFAULT 30)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $procedure$
BEGIN
    INSERT INTO dim_date (date_key, full_date, day_of_week, day_of_month, month_name, month_num, quarter, year, is_weekend)
    SELECT to_char(d,'YYYYMMDD')::INT, d::DATE, trim(to_char(d,'Day')),
           extract(day FROM d)::INT, trim(to_char(d,'Month')), extract(month FROM d)::INT,
           extract(quarter FROM d)::INT, extract(year FROM d)::INT,
           extract(isodow FROM d) >= 6
    FROM generate_series(CURRENT_DATE - 30, CURRENT_DATE + p_horizon_days, INTERVAL '1 day') d
    ON CONFLICT (date_key) DO NOTHING;

    INSERT INTO dim_project (project_id, project_name, status, total_value)
    SELECT project_id, project_name, status, total_value FROM project
    ON CONFLICT (project_id) DO UPDATE
        SET project_name = EXCLUDED.project_name,
            status       = EXCLUDED.status,
            total_value  = EXCLUDED.total_value;

    INSERT INTO dim_customer (customer_id, customer_name, city, postal_code)
    SELECT customer_id, first_name || ' ' || last_name, city, postal_code FROM customer
    ON CONFLICT (customer_id) DO UPDATE
        SET customer_name = EXCLUDED.customer_name,
            city          = EXCLUDED.city,
            postal_code   = EXCLUDED.postal_code;

    INSERT INTO dim_cost_type (cost_category, cost_subcategory, is_indirect)
    SELECT 'Direct Project', type_code, FALSE FROM ref_direct_cost_type
    UNION ALL
    SELECT 'Operational Overhead', category_code, TRUE FROM ref_overhead_category
    ON CONFLICT (cost_category, cost_subcategory) DO NOTHING;

    DELETE FROM fact_daily_cashflow
    WHERE date_key >= to_char(CURRENT_DATE,'YYYYMMDD')::INT;

    INSERT INTO fact_daily_cashflow
        (date_key, project_key, customer_key, cost_type_key,
         expected_cash_in, expected_cash_out, net_cashflow)
    SELECT date_key, project_key, customer_key, cost_type_key,
           sum(expected_cash_in), sum(expected_cash_out),
           sum(expected_cash_in) - sum(expected_cash_out)
    FROM (
        -- Customer milestones and supplier orders: this schema does not
        -- classify either by cost type (a purchase order has no link to
        -- ref_direct_cost_type), so cost_type_key stays null here. That is
        -- a real boundary in the data, not an oversight.
        SELECT to_char(cf.forecast_date,'YYYYMMDD')::INT AS date_key,
               dp.project_key,
               dc.customer_key,
               NULL::BIGINT AS cost_type_key,
               cf.expected_cash_in,
               cf.expected_cash_out
        FROM cashflow_forecast cf
        LEFT JOIN project p       ON p.project_id   = cf.project_id
        LEFT JOIN dim_project dp  ON dp.project_id  = cf.project_id
        LEFT JOIN dim_customer dc ON dc.customer_id = p.customer_id
        WHERE cf.forecast_date >= CURRENT_DATE
          AND cf.flow_source IN ('customer_milestone', 'supplier_order')

        UNION ALL

        -- Operational overhead: read straight from cost/operational_cost
        -- rather than from cashflow_forecast, because cashflow_forecast
        -- flattens away the cost_id a cost-type lookup needs. Overhead has
        -- no project or customer, matching the OLTP model where
        -- operational_cost carries no project_id.
        SELECT to_char(c.cost_date,'YYYYMMDD')::INT AS date_key,
               NULL::BIGINT AS project_key,
               NULL::BIGINT AS customer_key,
               dct.cost_type_key,
               0::NUMERIC AS expected_cash_in,
               c.amount AS expected_cash_out
        FROM cost c
        JOIN operational_cost oc ON oc.cost_id = c.cost_id
        JOIN dim_cost_type dct
          ON dct.cost_category = 'Operational Overhead'
         AND dct.cost_subcategory = oc.overhead_category
        WHERE c.cost_date BETWEEN CURRENT_DATE AND CURRENT_DATE + p_horizon_days
    ) x
    GROUP BY 1,2,3,4;
END;
$procedure$;


-- ----------------------------------------------------------------------------
-- sp_validate_staging: the six checks described in Chapter 8, section 8.3.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE public.sp_validate_staging(IN p_run_id bigint)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $procedure$
BEGIN
    UPDATE stg_sevdesk_invoice s
    SET is_valid = FALSE,
        rejection_reason = CASE
            WHEN coalesce(trim(s.raw_invoice_number),'') = ''
                THEN 'invoice_number is empty'
            WHEN s.raw_project_id !~ '^[0-9]+$'
                THEN 'project_id is not a whole number: ' || coalesce(s.raw_project_id,'(null)')
            WHEN NOT EXISTS (SELECT 1 FROM project p WHERE p.project_id = s.raw_project_id::BIGINT)
                THEN 'project_id ' || s.raw_project_id || ' does not exist'
            WHEN s.raw_invoice_date !~ '^\d{4}-\d{2}-\d{2}$'
                THEN 'invoice_date is not YYYY-MM-DD: ' || coalesce(s.raw_invoice_date,'(null)')
            WHEN s.raw_due_date !~ '^\d{4}-\d{2}-\d{2}$'
                THEN 'due_date is not YYYY-MM-DD: ' || coalesce(s.raw_due_date,'(null)')
            WHEN s.raw_due_date::DATE < s.raw_invoice_date::DATE
                THEN 'due_date is before invoice_date'
            WHEN s.raw_amount !~ '^[0-9]+(\.[0-9]{1,2})?$'
                THEN 'amount is not a positive decimal: ' || coalesce(s.raw_amount,'(null)')
            WHEN NOT EXISTS (SELECT 1 FROM ref_invoice_status r WHERE r.status_code = s.raw_status)
                THEN 'unknown invoice status: ' || coalesce(s.raw_status,'(null)')
            ELSE NULL
        END
    WHERE s.run_id = p_run_id;

    UPDATE stg_sevdesk_invoice
    SET is_valid = TRUE
    WHERE run_id = p_run_id AND rejection_reason IS NULL;
END;
$procedure$;


-- ----------------------------------------------------------------------------
-- sp_promote_staging: upserts valid rows into invoice, matching on
-- invoice_number so a re-uploaded export updates rather than duplicates.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE public.sp_promote_staging(IN p_run_id bigint)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $procedure$
BEGIN
    INSERT INTO invoice (project_id, invoice_number, invoice_date, due_date, amount, status, created_by)
    SELECT s.raw_project_id::BIGINT,
           trim(s.raw_invoice_number),
           s.raw_invoice_date::DATE,
           s.raw_due_date::DATE,
           s.raw_amount::NUMERIC(12,2),
           s.raw_status,
           'etl:sevdesk'
    FROM stg_sevdesk_invoice s
    WHERE s.run_id = p_run_id AND s.is_valid
    ON CONFLICT (invoice_number) DO UPDATE
        SET project_id   = EXCLUDED.project_id,
            invoice_date = EXCLUDED.invoice_date,
            due_date     = EXCLUDED.due_date,
            amount       = EXCLUDED.amount,
            status       = EXCLUDED.status;

    UPDATE stg_sevdesk_invoice
    SET promoted_at = CURRENT_TIMESTAMP
    WHERE run_id = p_run_id AND is_valid;
END;
$procedure$;


-- ----------------------------------------------------------------------------
-- sp_run_cashflow_pipeline: regenerates schedules, reapplies milestone
-- rules, and refreshes both the forecast and the star schema, so one
-- import call leaves the whole downstream chain consistent.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE public.sp_run_cashflow_pipeline(IN p_horizon_days integer DEFAULT 30)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $procedure$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT project_id FROM project LOOP
        CALL sp_generate_payment_schedule(r.project_id);
    END LOOP;
    CALL sp_apply_milestone_rules(NULL);
    CALL sp_refresh_cashflow_forecast(p_horizon_days);
    CALL sp_refresh_cashflow_star(p_horizon_days);
END;
$procedure$;


-- ----------------------------------------------------------------------------
-- rpc_import_invoices: the single entry point Retool calls (Chapter 8,
-- section 8.3). Logs the run before touching anything else, lands every
-- field as raw text, validates, promotes, runs the pipeline, and records
-- Succeeded/Partial/Failed on the run row either way.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_import_invoices(p_records jsonb, p_filename text DEFAULT 'upload.csv'::text, p_user text DEFAULT 'retool'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_run       BIGINT;
    v_received  INT;
    v_promoted  INT;
    v_rejected  INT;
    v_status    TEXT;
    v_rejects   JSONB;
    v_kpi       JSONB;
BEGIN
    IF p_records IS NULL OR jsonb_typeof(p_records) <> 'array' THEN
        RAISE EXCEPTION 'records must be a JSON array';
    END IF;

    v_received := jsonb_array_length(p_records);
    IF v_received = 0 THEN
        RAISE EXCEPTION 'records is empty';
    END IF;

    INSERT INTO etl_run (source_system, source_filename, rows_received, triggered_by)
    VALUES ('SEVDESK', p_filename, v_received, p_user)
    RETURNING run_id INTO v_run;

    -- Land every field as raw text. Values are never trusted or cast here;
    -- sp_validate_staging decides what is acceptable, so the rules cannot
    -- drift between this path and the Edge Function.
    INSERT INTO stg_sevdesk_invoice
        (run_id, row_number, raw_invoice_number, raw_project_id,
         raw_invoice_date, raw_due_date, raw_amount, raw_status)
    SELECT v_run,
           (ord + 1)::INT,
           btrim(coalesce(e->>'invoice_number','')),
           btrim(coalesce(e->>'project_id','')),
           btrim(coalesce(e->>'invoice_date','')),
           btrim(coalesce(e->>'due_date','')),
           btrim(coalesce(e->>'amount','')),
           btrim(coalesce(e->>'status',''))
    FROM jsonb_array_elements(p_records) WITH ORDINALITY AS t(e, ord);

    CALL sp_validate_staging(v_run);
    CALL sp_promote_staging(v_run);
    CALL sp_run_cashflow_pipeline(30);

    SELECT count(*) FILTER (WHERE is_valid),
           count(*) FILTER (WHERE NOT is_valid)
      INTO v_promoted, v_rejected
      FROM stg_sevdesk_invoice WHERE run_id = v_run;

    v_status := CASE WHEN v_rejected = 0 THEN 'Succeeded'
                     WHEN v_promoted = 0 THEN 'Failed'
                     ELSE 'Partial' END;

    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'row', row_number, 'invoiceNumber', raw_invoice_number,
             'reason', rejection_reason) ORDER BY row_number), '[]'::jsonb)
      INTO v_rejects
      FROM stg_sevdesk_invoice WHERE run_id = v_run AND NOT is_valid;

    UPDATE etl_run
       SET finished_at = CURRENT_TIMESTAMP, status = v_status,
           rows_promoted = v_promoted, rows_rejected = v_rejected
     WHERE run_id = v_run;

    SELECT to_jsonb(k) INTO v_kpi FROM v_dashboard_kpi k;

    RETURN jsonb_build_object(
        'runId',         v_run,
        'sourceFile',    p_filename,
        'status',        v_status,
        'rowsReceived',  v_received,
        'upsertedCount', v_promoted,
        'rejectedCount', v_rejected,
        'rejections',    v_rejects,
        'kpi',           v_kpi);
EXCEPTION WHEN OTHERS THEN
    -- A failed run stays recorded rather than vanishing, which is the
    -- whole point of having a run log.
    IF v_run IS NOT NULL THEN
        UPDATE etl_run
           SET finished_at = CURRENT_TIMESTAMP, status = 'Failed',
               error_message = SQLERRM
         WHERE run_id = v_run;
    END IF;
    RAISE;
END;
$function$;


-- ----------------------------------------------------------------------------
-- execute_customer_pseudonymization: the erasure procedure (Chapter 6,
-- section 6.4). Refuses while open receivables exist (Art. 17(3)),
-- otherwise overwrites identifying columns, mirrors the change onto
-- dim_customer, and writes one append-only row to data_erasure_log.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE public.execute_customer_pseudonymization(IN target_customer_id bigint, IN requested_at timestamp with time zone, IN executed_by character varying)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $procedure$
DECLARE
    v_open_obligations INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM customer WHERE customer_id = target_customer_id) THEN
        RAISE EXCEPTION 'Customer % does not exist', target_customer_id;
    END IF;

    IF EXISTS (SELECT 1 FROM customer
               WHERE customer_id = target_customer_id AND pseudonymized_at IS NOT NULL) THEN
        RAISE NOTICE 'Customer % is already pseudonymised; nothing to do', target_customer_id;
        RETURN;
    END IF;

    -- Art. 17(3)(b)/(e): erasure may be refused while a legal obligation or
    -- claim is still running. Unsettled receivables are exactly that case.
    SELECT count(*) INTO v_open_obligations
    FROM invoice i
    JOIN project p       ON p.project_id = i.project_id
    JOIN ref_invoice_status s ON s.status_code = i.status
    WHERE p.customer_id = target_customer_id
      AND s.counts_as_receivable;

    IF v_open_obligations > 0 THEN
        RAISE EXCEPTION
          'Erasure refused: customer % still has % open invoice(s). Art. 17(3) applies.',
          target_customer_id, v_open_obligations;
    END IF;

    -- Identifying data is overwritten; financial records (invoice, payment,
    -- project) stay intact for the 7-year retention required by
    -- Section 147 AO / Section 257 HGB.
    UPDATE customer
       SET first_name       = 'ANONYMIZED',
           last_name        = 'ANONYMIZED',
           company_name     = NULL,
           email            = 'erased_' || customer_id || '@pseudonymized.invalid',
           phone            = NULL,
           street_name      = 'REDACTED',
           house_number     = '0',
           postal_code      = '00000',
           city             = 'REDACTED',
           pseudonymized_at = CURRENT_TIMESTAMP
     WHERE customer_id = target_customer_id;

    -- The analytical copy carries the same identifiers and must follow.
    UPDATE dim_customer
       SET customer_name = 'ANONYMIZED',
           city          = 'REDACTED',
           postal_code   = '00000'
     WHERE customer_id = target_customer_id;

    INSERT INTO data_erasure_log
        (subject_table, subject_id, requested_at, executed_by, legal_basis_note, columns_affected)
    VALUES
        ('customer', target_customer_id, requested_at, executed_by,
         'Art. 17 erasure honoured by pseudonymisation; financial records retained under Section 147 AO (7 years).',
         'first_name, last_name, company_name, email, phone, street_name, house_number, postal_code, city; dim_customer.customer_name, dim_customer.city, dim_customer.postal_code');
END;
$procedure$;


-- ----------------------------------------------------------------------------
-- rpc_pseudonymize_customer: thin wrapper so Retool (or any client) can
-- call the erasure procedure without supplying a timestamp itself.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_pseudonymize_customer(p_customer_id bigint, p_executed_by character varying DEFAULT 'retool'::character varying)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN CALL execute_customer_pseudonymization(p_customer_id, CURRENT_TIMESTAMP, p_executed_by); END;
$function$;

-- ---------------------------------------------------------------------
-- rpc_rebase_demo_dates
--
-- Demonstration helper, not a business rule.
--
-- The demonstration dataset is synthetic. Its dates were authored around
-- 13 September 2026, and because the forecast window is forward-looking,
-- every day that passes pushes another supplier obligation out of the
-- window until the dashboard has nothing left to show. This function
-- shifts every business date in the dataset by one whole number of days
-- so the same scenario sits in the window on whatever day it is run.
--
-- Anchor rule: the newest purchase order always sits 3 days before today,
-- which is the state the thesis figures were read in. The shift is derived
-- from the data itself, so running it twice on the same day is a no-op and
-- it needs no stored state and no extra table.
--
-- Amounts, relationships, statuses and every business rule are untouched.
-- Only the calendar moves.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_rebase_demo_dates()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    c_lag       CONSTANT INT := 3;
    v_max_order DATE;
    v_shift     INT;
    v_project   INT := 0;
    v_order     INT := 0;
    v_cost      INT := 0;
    v_invoice   INT := 0;
    v_payment   INT := 0;
    v_kpi       JSONB;
    v_alerts    JSONB;
BEGIN
    SELECT max(order_date) INTO v_max_order FROM purchase_order;

    IF v_max_order IS NULL THEN
        RETURN jsonb_build_object(
            'shiftDays', 0,
            'note', 'no purchase orders found; nothing to rebase');
    END IF;

    v_shift := (CURRENT_DATE - c_lag) - v_max_order;

    IF v_shift <> 0 THEN
        UPDATE project
           SET start_date               = start_date + v_shift,
               expected_completion_date = expected_completion_date + v_shift;
        GET DIAGNOSTICS v_project = ROW_COUNT;

        UPDATE purchase_order
           SET order_date             = order_date + v_shift,
               expected_delivery_date = expected_delivery_date + v_shift;
        GET DIAGNOSTICS v_order = ROW_COUNT;

        UPDATE cost
           SET cost_date = cost_date + v_shift;
        GET DIAGNOSTICS v_cost = ROW_COUNT;

        UPDATE invoice
           SET invoice_date = invoice_date + v_shift,
               due_date     = due_date + v_shift;
        GET DIAGNOSTICS v_invoice = ROW_COUNT;

        UPDATE payment
           SET payment_date = payment_date + v_shift;
        GET DIAGNOSTICS v_payment = ROW_COUNT;
    END IF;

    -- payment_schedule stores an offset, not a date, so the schedule, the
    -- classifications, the forecast and the star schema are all regenerated
    -- by the same pipeline the import uses.
    CALL sp_run_cashflow_pipeline(30);

    SELECT to_jsonb(k) INTO v_kpi FROM v_dashboard_kpi k;

    SELECT coalesce(
             jsonb_agg(jsonb_build_object(
                 'date',     full_date,
                 'position', cumulative_position,
                 'status',   liquidity_status) ORDER BY full_date),
             '[]'::jsonb)
      INTO v_alerts
      FROM v_liquidity_alert;

    RETURN jsonb_build_object(
        'shiftDays',       v_shift,
        'anchorRule',      format('newest purchase order sits %s days before today', c_lag),
        'rowsShifted',     jsonb_build_object(
                               'project',        v_project,
                               'purchase_order', v_order,
                               'cost',           v_cost,
                               'invoice',        v_invoice,
                               'payment',        v_payment),
        'liquidityAlerts', v_alerts,
        'kpiAfterRebase',  v_kpi);
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_rebase_demo_dates() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_rebase_demo_dates() TO postgres;
GRANT EXECUTE ON FUNCTION public.rpc_rebase_demo_dates() TO app_finance;
