{% macro normalize_city_name(column) %}
regexp_replace(
  regexp_replace(regexp_replace(regexp_replace(regexp_replace(
  regexp_replace(regexp_replace(
    lower({{ column }}),
    '[áàãâä]', 'a', 'g'),
    '[éèêë]', 'e', 'g'),
    '[íìîï]', 'i', 'g'),
    '[óòõôö]', 'o', 'g'),
    '[úùûü]', 'u', 'g'),
    '[ç]', 'c', 'g'),
  '[ \-]', '_', 'g')
{% endmacro %}
