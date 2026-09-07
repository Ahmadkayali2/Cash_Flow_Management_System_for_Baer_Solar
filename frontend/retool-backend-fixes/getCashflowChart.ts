/**
 * Cashflow chart.
 *
 * CHANGED: read straight from cashflow_forecast, which holds one signed
 * row per event — so the chart plotted individual transactions, not a
 * daily net. v_cashflow_30day aggregates per day and adds the cumulative
 * running position, which is the line the owner actually needs.
 */
export default async function getCashflowChart() {
  const result = await bearSolar.query<{
    full_date: string
    cash_in: string
    cash_out: string
    net_cashflow: string
    cumulative_position: string
  }>(
    `SELECT full_date, cash_in, cash_out, net_cashflow, cumulative_position
       FROM v_cashflow_30day ORDER BY full_date ASC`
  )
  return result.data.map((row) => ({
    forecast_date: row.full_date,
    cash_in: Number(row.cash_in),
    cash_out: Number(row.cash_out),
    net_cashflow: Number(row.net_cashflow),
    cumulative_position: Number(row.cumulative_position),
  }))
}
