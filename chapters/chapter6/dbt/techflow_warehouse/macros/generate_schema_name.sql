{% macro generate_schema_name(custom_schema_name, node) -%}
    {#- Use the model's custom schema verbatim instead of dbt's default
        "<target.schema>_<custom_schema>" concatenation.

        Without this override, a model configured with schema='customers' running
        against a profile whose target schema is also 'customers' lands in
        silver_db.customers_customers, not silver_db.customers. The chapter, the
        README, and the CI clone all assume the plain schema name.

        CI isolation moves to a suffix on the target name rather than the profile's
        schema, so the CI target builds into '<schema>__ci' and matches the
        zero-copy clones that macros/ci/clone_prod_to_ci.sql creates. -#}
    {%- set base_schema = (custom_schema_name | trim)
        if custom_schema_name is not none
        else target.schema -%}

    {%- if target.name == 'ci' -%}
        {{ base_schema }}__ci
    {%- else -%}
        {{ base_schema }}
    {%- endif -%}
{%- endmacro %}
