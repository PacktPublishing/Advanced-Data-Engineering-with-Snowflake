{% macro clone_prod_to_ci() %}
    {# Zero-copy clone of each prod schema into its __ci counterpart so CI runs
       against production-shaped data at no storage cost. The clone shares
       micro-partitions and pays only for divergence, which gives incremental
       models a real MERGE target and the row-count diff a production baseline.
       Run with: dbt run-operation clone_prod_to_ci --target ci #}
    {# One entry per schema any model builds into. macros/generate_schema_name.sql
       appends '__ci' on the ci target, so these clone names are exactly where the
       CI build writes. Add a row here whenever a model introduces a new schema. #}
    {% set schemas = [
        {'database': 'silver_db', 'schema': 'customers'},
        {'database': 'gold_db',   'schema': 'customers'},
        {'database': 'gold_db',   'schema': 'transactions'}
    ] %}

    {% if not execute %}
        {{ return('') }}
    {% endif %}

    {% for relation in schemas %}
        {% set clone_sql %}
            CREATE OR REPLACE SCHEMA {{ relation.database }}.{{ relation.schema }}__ci
                CLONE {{ relation.database }}.{{ relation.schema }}
        {% endset %}
        {{ log('Cloning ' ~ relation.database ~ '.' ~ relation.schema ~ ' into ' ~ relation.database ~ '.' ~ relation.schema ~ '__ci', info=True) }}
        {% do run_query(clone_sql) %}
    {% endfor %}
{% endmacro %}
