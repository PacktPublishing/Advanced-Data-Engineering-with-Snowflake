{# =====================================================================
   DCM macros: reusable grant helpers
   =====================================================================
   Macros live in sources/macros/ and render into definition files as Jinja.
   Keeping the grant pattern in one place means every object grants read
   access the same way, and a change to the policy touches one file.

   Usage in a definition file:
     {{ grant_select('gold_db' ~ env_suffix ~ '.transactions.foo_dt',
                     'TRANSFORMER' ~ env_suffix) }}
   ===================================================================== #}

{% macro grant_select(object_name, role_name) -%}
GRANT SELECT ON {{ object_name }} TO ROLE {{ role_name }};
{%- endmacro %}

{% macro grant_usage(object_type, object_name, role_name) -%}
GRANT USAGE ON {{ object_type }} {{ object_name }} TO ROLE {{ role_name }};
{%- endmacro %}
