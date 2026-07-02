select
    series_id,
    title,
    description,
    frequency,
    units,
    category_id,
    category_name,
    observation_start,
    observation_end,
    country,
    last_updated,
    popularity
from {{ source('fred', 'series') }}
