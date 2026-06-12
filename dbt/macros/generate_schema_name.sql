
{% macro generate_schema_name(custom_schema_name, node) %}
    {%- if custom_schema_name is not none -%}
        {{ target.name }}_{{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.name }}_{{ target.schema | trim }}
    {%- endif -%}
{% endmacro %}
