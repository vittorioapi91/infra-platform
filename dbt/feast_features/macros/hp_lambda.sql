{% macro hp_lambda_for_frequency(frequency_col) %}
    case
        when lower({{ frequency_col }}) like '%annual%' then {{ var('hp_lambda_annual') }}
        when lower({{ frequency_col }}) like '%quarter%' then {{ var('hp_lambda_quarterly') }}
        when lower({{ frequency_col }}) like '%month%' then {{ var('hp_lambda_monthly') }}
        when lower({{ frequency_col }}) like '%week%' then {{ var('hp_lambda_weekly') }}
        when lower({{ frequency_col }}) like '%day%' then {{ var('hp_lambda_daily') }}
        else {{ var('hp_lambda_quarterly') }}
    end
{% endmacro %}
