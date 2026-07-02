{{ config(
    materialized='view',
    tags=['feast', 'lineage'],
) }}

/*
  Run-level lineage for HP decomposition (populated by trading_agent.features.macro.hodrick_prescott).
  dbt tests validate the latest materialization after the Python step.
*/
select *
from {{ source('feast_engineered', 'feature_transform_lineage') }}
