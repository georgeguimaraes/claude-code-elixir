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

# Run credo on .ex and .exs files
if [[ "$file_path" == *.ex || "$file_path" == *.exs ]]; then
  if [ -f "$file_path" ]; then
    # Find mix.exs by walking up from the file
    dir=$(dirname "$file_path")
    while [[ "$dir" != "/" ]]; do
      if [[ -f "$dir/mix.exs" ]]; then
        cd "$dir"
        # Check if credo is available
        if ! mix help credo &>/dev/null; then
          # Credo not installed, skip check silently
          exit 0
        fi
        if output=$(mix credo "$file_path" 2>&1); then
          echo "Credo passed: $file_path"
        else
          echo "Credo issues found:"
          echo "$output"
          exit 1
        fi
        break
      fi
      dir=$(dirname "$dir")
    done
  fi
fi

exit 0
