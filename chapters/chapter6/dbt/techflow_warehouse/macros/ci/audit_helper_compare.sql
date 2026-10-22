{% macro audit_helper_compare(model, primary_key=none) %}
    {# Primary key per model, used to align rows in the comparison. The default
       suits the customer models; add an entry for any model keyed differently. #}
    {% set audit_primary_keys = {
        'silver_customers': 'customer_id',
        'gold_customer_value': 'customer_id',
        'merchant_activity': 'merchant_id'
    } %}
    {% set ci_relation = ref(model) %}

    {#- The ci target builds into '<schema>__ci' (see macros/generate_schema_name.sql),
        so production is the same schema with that suffix removed. Swapping the
        suffix for '__prod' would point at a schema that does not exist, and the
        macro would log "no prod relation" and pass without comparing anything. -#}
    {% set prod_schema = ci_relation.schema | replace('__ci', '') %}
    {% set compare_key = primary_key
        or audit_primary_keys.get(model, 'customer_id') %}

    {% if not execute %}
        {{ return('') }}
    {% endif %}

    {% if prod_schema == ci_relation.schema %}
        {{ exceptions.raise_compiler_error(
            'audit_helper_compare expects the ci target (schema ' ~ ci_relation.schema
            ~ ' has no __ci suffix). Rerun with --target ci.'
        ) }}
    {% endif %}

    {% set prod_relation = adapter.get_relation(
        database=ci_relation.database,
        schema=prod_schema,
        identifier=ci_relation.identifier
    ) %}

    {% if prod_relation is none %}
        {{ exceptions.warn(
            'No prod relation for ' ~ model ~ ' at ' ~ ci_relation.database ~ '.'
            ~ prod_schema ~ '.' ~ ci_relation.identifier
            ~ '; treating as a new model with nothing to diff.'
        ) }}
        {{ return('') }}
    {% endif %}

    {% set compare_sql %}
        {{ audit_helper.compare_relations(
            a_relation=prod_relation,
            b_relation=ci_relation,
            primary_key=compare_key
        ) }}
    {% endset %}

    {% set results = run_query(compare_sql) %}
    {{ log('Row-count diff for ' ~ model ~ ' (key: ' ~ compare_key ~ ')', info=True) }}
    {% do results.print_table(max_rows=50) %}
{% endmacro %}
