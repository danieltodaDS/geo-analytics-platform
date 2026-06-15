{% macro compat_datediff(datepart, start, end) %}
    {% if target.type == 'bigquery' %}
        DATE_DIFF(DATE({{ end }}), DATE({{ start }}), {{ datepart }})
    {% else %}
        datediff('{{ datepart }}', {{ start }}, {{ end }})
    {% endif %}
{% endmacro %}
