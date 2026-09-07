/**
 * Supplier Watch.
 *
 * CHANGED: the 7-day alert used to key off expected_delivery_date. The
 * owner confirmed the ORDER date starts the payment clock, so the alert
 * was firing on the wrong day. The rule now lives in v_supplier_watch and
 * this function only presents it.
 */
export default async function getSupplierWatch() {
  const result = await bearSolar.query<{
    order_id: string
    supplier_name: string
    project_name: string
    order_date: string
    payment_due_date: string
    days_until_due: string
    total_amount: string
    status: string
    alert_level: string
  }>(
    `SELECT order_id, supplier_name, project_name, order_date,
            payment_due_date, days_until_due, total_amount, status, alert_level
       FROM v_supplier_watch
      ORDER BY payment_due_date ASC`
  )
  return result.data.map((row) => ({
    order_id: Number(row.order_id),
    supplier_name: row.supplier_name,
    project_name: row.project_name,
    order_date: row.order_date,
    payment_due_date: row.payment_due_date,
    days_until_due: Number(row.days_until_due),
    total_amount: Number(row.total_amount),
    status: row.status,
    alert_level: row.alert_level, // OVERDUE | DUE_SOON | SCHEDULED
  }))
}
