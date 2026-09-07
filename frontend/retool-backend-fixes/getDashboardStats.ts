/**
 * Dashboard KPI tiles.
 *
 * CHANGED: two defects fixed by moving the logic into v_dashboard_kpi.
 *  - receivables used `status != 'Paid'`, which counted Cancelled
 *    invoices as money owed. It now uses ref_invoice_status.counts_as_receivable.
 *  - supplier due used expected_delivery_date instead of the order date.
 */
export default async function getDashboardStats() {
  const result = await bearSolar.query<{
    outstanding_receivables: string
    supplier_due_7_days: string
    projected_30day_net: string
    active_projects: string
    days_negative_next_30: string
  }>('SELECT * FROM v_dashboard_kpi')

  const k = result.data[0]
  return {
    outstandingReceivables: Number(k?.outstanding_receivables ?? 0),
    supplierPaymentsDue: Number(k?.supplier_due_7_days ?? 0),
    netCashPosition30d: Number(k?.projected_30day_net ?? 0),
    activeProjects: Number(k?.active_projects ?? 0),
    daysNegativeNext30: Number(k?.days_negative_next_30 ?? 0),
  }
}
