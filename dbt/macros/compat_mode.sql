{% macro compat_mode(expr) %}
    {% if target.type == 'bigquery' %}
        APPROX_TOP_COUNT({{ expr }}, 1)[OFFSET(0)].value
    {% else %}
        mode({{ expr }})
    {% endif %}
{% endmacro %}
