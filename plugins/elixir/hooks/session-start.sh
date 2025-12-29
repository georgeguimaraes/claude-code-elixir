#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Only inject context if this is an Elixir project (mix.exs exists)
if [ ! -f "mix.exs" ]; then
    # Not an Elixir project, output empty response
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": ""
  }
}
EOF
    exit 0
fi

# Read the using-elixir-skills SKILL.md
skill_content=$(cat "${PLUGIN_ROOT}/skills/using-elixir-skills/SKILL.md" 2>&1 || echo "Error reading skill")

# Escape for JSON using pure bash (works on macOS and Linux)
escape_for_json() {
    local input="$1"
    local output=""
    local i char
    for (( i=0; i<${#input}; i++ )); do
        char="${input:$i:1}"
        case "$char" in
            $'\\') output+='\\' ;;
            '"') output+='\"' ;;
            $'\n') output+='\n' ;;
            $'\r') output+='\r' ;;
            $'\t') output+='\t' ;;
            *) output+="$char" ;;
        esac
    done
    printf '%s' "$output"
}

skill_escaped=$(escape_for_json "$skill_content")

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${skill_escaped}"
  }
}
EOF

exit 0
