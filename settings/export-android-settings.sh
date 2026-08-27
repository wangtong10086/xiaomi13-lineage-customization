#!/system/bin/sh
set -eu

for namespace in system secure global; do
  echo "[$namespace]"
  settings list "$namespace"
done

echo '[ime]'
printf 'default_input_method='
settings get secure default_input_method
printf 'enabled_input_methods='
settings get secure enabled_input_methods
printf 'selected_input_method_subtype='
settings get secure selected_input_method_subtype
