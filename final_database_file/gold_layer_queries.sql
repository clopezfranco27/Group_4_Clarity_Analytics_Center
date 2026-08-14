-- ---------------------------------------------------------------------
-- Q1. What does each removal cost, and is that rising or falling?
-- ---------------------------------------------------------------------
WITH budget AS (
    SELECT fiscal_year, SUM(net_operating_cost) AS noc
    FROM gold_fact_budget
    GROUP BY fiscal_year
),
enforcement AS (
    SELECT fiscal_year, SUM(metric_value) AS removals
    FROM gold_fact_enforcement
    WHERE metric_name = 'removals'
    GROUP BY fiscal_year
),
joined AS (
    SELECT b.fiscal_year,
           b.noc,
           e.removals,
           b.noc * 1.0 / e.removals AS cost
    FROM budget b
    JOIN enforcement e ON e.fiscal_year = b.fiscal_year
)
SELECT fiscal_year,
       ROUND(noc / 1e9, 2)                      AS net_operating_cost_bn,
       removals,
       ROUND(cost)                              AS cost_per_removal_usd,
       ROUND(100.0 * (cost - LAG(cost) OVER (ORDER BY fiscal_year))
             / LAG(cost) OVER (ORDER BY fiscal_year), 1)
                                                AS cost_change_pct
FROM joined
ORDER BY fiscal_year;


-- --------------------------------------------------------------------------
-- Q2. Is falling output due to fewer staff or lower productivity per agent?
-- --------------------------------------------------------------------------
WITH month_ends AS (
    SELECT DISTINCT month_end_date, fiscal_year
    FROM gold_dim_date
    WHERE is_month_end = 1
      AND fiscal_year BETWEEN 2020 AND 2025
),
monthly_head AS (
    SELECT me.fiscal_year,
           me.month_end_date,
           COUNT(DISTINCT a.agent_id) AS month_headcount
    FROM month_ends me
    JOIN gold_fact_assignment a
      ON a.start_date <= me.month_end_date
     AND (a.end_date IS NULL OR a.end_date > me.month_end_date)
    GROUP BY me.fiscal_year, me.month_end_date
),
staffing AS (
    SELECT fiscal_year, AVG(month_headcount) AS avg_agents
    FROM monthly_head
    GROUP BY fiscal_year
),
enforcement AS (
    SELECT fiscal_year, SUM(metric_value) AS removals
    FROM gold_fact_enforcement
    WHERE metric_name = 'removals'
    GROUP BY fiscal_year
)
SELECT e.fiscal_year,
       e.removals,
       ROUND(s.avg_agents, 1)                     AS avg_active_agents,
       ROUND(e.removals / s.avg_agents, 1)        AS removals_per_agent,
       ROUND(100.0 * (e.removals - LAG(e.removals) OVER (ORDER BY e.fiscal_year))
             / LAG(e.removals) OVER (ORDER BY e.fiscal_year), 1) AS removals_yoy_pct,
       ROUND(100.0 * (s.avg_agents - LAG(s.avg_agents) OVER (ORDER BY e.fiscal_year))
             / LAG(s.avg_agents) OVER (ORDER BY e.fiscal_year), 1) AS headcount_yoy_pct
FROM enforcement e
JOIN staffing s ON s.fiscal_year = e.fiscal_year
WHERE e.fiscal_year >= 2021          -- FY2020 headcount is a ramp artifact
ORDER BY e.fiscal_year;


-- ---------------------------------------------------------------------
-- Q3. Which regions are losing staff fastest, and is it worsening?
-- ---------------------------------------------------------------------
WITH months AS (
    SELECT DISTINCT month_end_date
    FROM gold_dim_date
    WHERE is_month_end = 1
      AND month_end_date >= '2020-01-01'
      AND month_end_date <= '2026-07-31'
),
monthly AS (
    SELECT m.month_end_date,
           a.region_name,
           COUNT(DISTINCT CASE
               WHEN a.start_date <= m.month_end_date
                AND (a.end_date IS NULL OR a.end_date > m.month_end_date)
               THEN a.agent_id END) AS headcount,
           COUNT(DISTINCT CASE
               WHEN a.end_date IS NOT NULL
                AND date(a.end_date, 'start of month', '+1 month', '-1 day') = m.month_end_date
               THEN a.agent_id END) AS leavers
    FROM months m
    CROSS JOIN gold_fact_assignment a
    GROUP BY m.month_end_date, a.region_name
    HAVING headcount > 0 OR leavers > 0
),
rolling AS (
    SELECT month_end_date,
           region_name,
           headcount,
           SUM(leavers) OVER (
               PARTITION BY region_name
               ORDER BY month_end_date
               ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
           ) AS leavers_ttm,
           AVG(headcount) OVER (
               PARTITION BY region_name
               ORDER BY month_end_date
               ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
           ) AS avg_headcount_ttm
    FROM monthly
)
SELECT region_name,
       MAX(CASE WHEN month_end_date = '2024-09-30'
                THEN ROUND(100.0 * leavers_ttm / avg_headcount_ttm, 1) END) AS attrition_fy24_pct,
       MAX(CASE WHEN month_end_date = '2026-07-31'
                THEN ROUND(100.0 * leavers_ttm / avg_headcount_ttm, 1) END) AS attrition_latest_pct,
       MAX(CASE WHEN month_end_date = '2026-07-31' THEN headcount END)      AS headcount_now
FROM rolling
GROUP BY region_name
ORDER BY attrition_latest_pct DESC;


-- ---------------------------------------------------------------------
-- Q4. Which Treasury lines get revised most after the books close?
-- ---------------------------------------------------------------------
WITH paired AS (
    SELECT f.statement_fiscal_year AS fiscal_year,
           li.line_item_description,
           MAX(CASE WHEN f.is_restated = 0 THEN f.position_billion_amount END) AS first_published_bn,
           MAX(CASE WHEN f.is_restated = 1 THEN f.position_billion_amount END) AS restated_bn
    FROM gold_fact_treasury f
    JOIN gold_dim_treasury_line li ON li.treasury_line_key = f.treasury_line_key
    WHERE li.is_additive = 1          -- detail lines only, never subtotals
    GROUP BY f.statement_fiscal_year, li.line_item_description
)
SELECT line_item_description,
       COUNT(*)                                          AS years_comparable,
       SUM(CASE WHEN restated_bn <> first_published_bn THEN 1 ELSE 0 END) AS years_revised,
       ROUND(AVG(ABS(restated_bn - first_published_bn)), 1) AS avg_revision_bn,
       ROUND(MAX(ABS(restated_bn - first_published_bn)), 1) AS largest_revision_bn
FROM paired
WHERE first_published_bn IS NOT NULL
  AND restated_bn IS NOT NULL
GROUP BY line_item_description
HAVING years_revised > 0
ORDER BY avg_revision_bn DESC
LIMIT 10;
