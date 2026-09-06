#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
for action in format compile credo; do
  for file in mix-hook.sh json-string.sh vendor/JSON.sh vendor/LICENSE.MIT vendor/README.md; do
    source_file="$root/scripts/mix-hooks/$file"
    target="$root/plugins/mix-$action/hooks/$file"
    if [[ ${1:-} == --check ]]; then
      if ! cmp -s "$source_file" "$target"; then
        echo "Outdated bundle: $target. Run bash scripts/sync-mix-hooks.sh" >&2
        exit 1
      fi
    else
      mkdir -p "$(dirname "$target")"
      cp "$source_file" "$target"
    fi
  done
done
