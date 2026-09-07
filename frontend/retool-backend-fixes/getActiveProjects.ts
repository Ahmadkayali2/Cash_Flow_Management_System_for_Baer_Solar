/**
 * Active projects.
 *
 * CHANGED: the INNER JOIN on invoice hid every project that had not been
 * invoiced yet — exactly the new projects the owner most needs to see.
 * Now a LEFT JOIN, filtered on non-terminal statuses, with milestone
 * progress included.
 */
export default async function getActiveProjects() {
  const result = await bearSolar.query<{
    project_id: string
    project_name: string
    total_value: string
    status: string
    invoiced_to_date: string
    received_to_date: string
    milestones_paid: string
    milestones_total: string
  }>(
    `SELECT p.project_id, p.project_name, p.total_value, p.status,
            COALESCE(pr.invoiced_to_date, 0) AS invoiced_to_date,
            COALESCE(pr.received_to_date, 0) AS received_to_date,
            COUNT(ps.schedule_id) FILTER (WHERE ps.status = 'Paid') AS milestones_paid,
            COUNT(ps.schedule_id)                                   AS milestones_total
       FROM project p
       JOIN ref_project_status rs ON rs.status_code = p.status
       LEFT JOIN v_project_profitability pr ON pr.project_id = p.project_id
       LEFT JOIN payment_schedule ps        ON ps.project_id = p.project_id
      WHERE NOT rs.is_terminal
      GROUP BY p.project_id, p.project_name, p.total_value, p.status,
               pr.invoiced_to_date, pr.received_to_date, rs.sort_order
      ORDER BY rs.sort_order, p.start_date`
  )
  return result.data.map((row) => ({
    project_id: Number(row.project_id),
    project_name: row.project_name,
    total_value: Number(row.total_value),
    status: row.status,
    invoiced_to_date: Number(row.invoiced_to_date),
    received_to_date: Number(row.received_to_date),
    milestone_progress: `${row.milestones_paid}/${row.milestones_total}`,
  }))
}
