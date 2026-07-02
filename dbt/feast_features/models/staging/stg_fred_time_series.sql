with source as (
    select
        series_id,
        date as observation_date,
        value
    from {{ source('fred', 'time_series') }}
    where value is not null
)

select * from source
