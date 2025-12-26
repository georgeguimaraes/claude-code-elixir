#!/bin/bash
set -euo pipefail

input=$(cat)

# Extract file_path or filePath from JSON using bash regex
if [[ "$input" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  file_path="${BASH_REMATCH[1]}"
elif [[ "$input" =~ \"filePath\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  file_path="${BASH_REMATCH[1]}"
else
  exit 0
fi

if [[ "$file_path" == *.ex || "$file_path" == *.exs ]]; then
  if [ -f "$file_path" ]; then
    if output=$(mix format "$file_path" 2>&1); then
      echo "Formatted: $file_path"
    else
      echo "Format warning: $output" >&2
    fi
  fi
fi

exit 0
