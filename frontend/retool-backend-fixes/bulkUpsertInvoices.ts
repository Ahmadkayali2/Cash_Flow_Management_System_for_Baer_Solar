/**
 * Bulk import of SEVDESK invoices.
 *
 * ONE QUERY, ONE ROUND TRIP
 * The whole import - open an audit run, stage the raw rows, validate,
 * promote, recompute the forecast and the star schema - happens inside the
 * database function rpc_import_invoices, which returns a JSON report.
 * Earlier versions issued six calls and used CALL statements, which the
 * Retool client does not run.
 *
 * Values are passed through the params array, never interpolated into the
 * SQL string. Retool's static analysis rejects interpolation, and rightly
 * so: this data comes from an uploaded file, which is untrusted input.
 *
 * Milestone classification is NOT done here. It is a business rule and
 * lives in the database, so it applies to every client - this screen, the
 * Edge Function, or anyone with psql - instead of only to uploads made
 * through this page.
 */
type InvoiceRecord = {
  invoice_number: string
  project_id: number
  invoice_date: string
  due_date: string
  amount: number
  status: string
}

type Params = { records: InvoiceRecord[]; filename?: string }

type ImportReport = {
  runId: number
  sourceFile: string
  status: 'Succeeded' | 'Partial' | 'Failed'
  rowsReceived: number
  upsertedCount: number
  rejectedCount: number
  rejections: { row: number; invoiceNumber: string; reason: string }[]
  kpi: Record<string, number>
}

export default async function bulkUpsertInvoices(req: { params: Params; user: User }) {
  const { records, filename } = req.params

  if (!Array.isArray(records) || records.length === 0) {
    throw new Error('No records provided')
  }

  // Send only the six fields the importer reads; anything else is noise.
  const payload = records.map((r) => ({
    invoice_number: r.invoice_number,
    project_id: r.project_id,
    invoice_date: r.invoice_date,
    due_date: r.due_date,
    amount: r.amount,
    status: r.status,
  }))

  const result = await bearSolar.query<{ report: ImportReport | string }>(
    'SELECT rpc_import_invoices($1::jsonb, $2, $3) AS report',
    [JSON.stringify(payload), filename ?? 'retool-upload.csv', req.user.email || 'retool']
  )

  const raw = result.data[0]?.report
  if (!raw) throw new Error('Import returned no report')

  // jsonb arrives as an object or as text depending on driver settings.
  const report: ImportReport = typeof raw === 'string' ? JSON.parse(raw) : raw
  return report
}
