{{ config(
    materialized='view',
    tags=['feast', 'hodrick_prescott'],
) }}

/*
  Hodrick-Prescott cycle/trend per series (populated by trading_agent._feast_.features.hodrick_prescott).
  Exported to Feast parquet via trading_agent._feast_.features.hp_feast_export.
*/
select *
from {{ source('feast_engineered', 'macro_hp_decomposition') }}
