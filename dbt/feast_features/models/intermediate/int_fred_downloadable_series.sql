/*
  Series that have at least one observation in fred.time_series (macro downloader output).
  Used as the HP filter input universe.
*/
select
    s.series_id,
    s.title,
    s.frequency,
    s.units,
    count(ts.observation_date) as observation_count,
    min(ts.observation_date) as first_observation_date,
    max(ts.observation_date) as last_observation_date
from {{ ref('stg_fred_series') }} as s
inner join {{ ref('stg_fred_time_series') }} as ts
    on ts.series_id = s.series_id
group by
    s.series_id,
    s.title,
    s.frequency,
    s.units
