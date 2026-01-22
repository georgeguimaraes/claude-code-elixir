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

# Only compile .ex files (not .exs scripts/tests - they're compiled on demand)
if [[ "$file_path" == *.ex ]]; then
  if [ -f "$file_path" ]; then
    # Find mix.exs by walking up from the file
    dir=$(dirname "$file_path")
    while [[ "$dir" != "/" ]]; do
      if [[ -f "$dir/mix.exs" ]]; then
        cd "$dir"

        # Check if any BEAM process is running with cwd in this project.
        # This catches Phoenix servers, IEx sessions, or any mix task that holds the build lock.
        # Running mix compile while another BEAM process holds the lock causes indefinite hangs.
        project_dir=$(pwd -P)
        if lsof -c beam.smp -a -d cwd 2>/dev/null | grep -q "$project_dir"; then
          echo "BEAM process running for this project (hot-reload active) - skipping compile"
          exit 0
        fi

        if output=$(mix compile --warnings-as-errors 2>&1); then
          echo "Compiled successfully"
        else
          echo "Compilation error:"
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
