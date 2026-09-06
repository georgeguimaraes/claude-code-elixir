#!/bin/bash
set -eo pipefail

hook_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$hook_dir/json-string.sh"
action=${1:-}
case $action in
  format) budget=45 ;;
  compile|credo) budget=105 ;;
  *) echo "Unknown Mix hook: $action" >&2; exit 1 ;;
esac

work=$(mktemp -d "${TMPDIR:-/tmp}/mix-hook.XXXXXX")
child=
watchdog=
cleanup() {
  [[ -z $child ]] || kill -KILL -- "-$child" 2>/dev/null || :
  [[ -z $watchdog ]] || kill -KILL -- "-$watchdog" 2>/dev/null || :
  wait 2>/dev/null || :
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

messages=
report() { messages+="${messages:+$'\n\n'}$1"; }
feedback() {
  if [[ -n $messages ]]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":'
    json_quote "$messages"
    printf '}}\n'
  fi
}

if ! LC_ALL=C bash "$hook_dir/vendor/JSON.sh" -l >"$work/fields" 2>"$work/parse-error"; then
  report "mix $action could not parse the edit event."
  feedback
  exit 0
fi

cwd='' tool='' file='' command=''
while IFS=$'\t' read -r key value; do
  case $key in
    '["cwd"]'|'["tool_name"]'|'["tool_input","file_path"]'|'["tool_input","filePath"]'|'["tool_input","command"]')
      if ! json_decode_string "$value"; then
        report "mix $action received an invalid JSON string in $key."
        feedback
        exit 0
      fi
      case $key in
        '["cwd"]') cwd=$decoded ;;
        '["tool_name"]') tool=$decoded ;;
        '["tool_input","command"]') command=$decoded ;;
        *) file=$decoded ;;
      esac
      ;;
  esac
done <"$work/fields"

paths=()
case $tool in
  apply_patch)
    while IFS= read -r line || [[ -n $line ]]; do
      line=${line%$'\r'}
      case $line in
        "*** Add File: "*) paths+=("${line#'*** Add File: '}") ;;
        "*** Update File: "*) paths+=("${line#'*** Update File: '}") ;;
        "*** Delete File: "*) paths+=("${line#'*** Delete File: '}") ;;
        "*** Move to: "*) paths+=("${line#'*** Move to: '}") ;;
      esac
    done <<<"$command"
    ;;
  Edit|MultiEdit|Write) [[ -z $file ]] || paths+=("$file") ;;
  *) exit 0 ;;
esac
[[ ${#paths[@]} -gt 0 ]] || exit 0
if [[ $cwd != /* || ! -d $cwd ]]; then
  report "mix $action needs an absolute, existing cwd in the edit event."
  feedback
  exit 0
fi

projects=() file_projects=() files=()
for path in "${paths[@]}"; do
  case $path in
    *.ex) ;;
    *.exs) [[ $action != compile ]] || continue ;;
    *) continue ;;
  esac
  [[ $path == /* ]] || path="$cwd/$path"
  [[ $action == compile || -f $path ]] || continue
  dir=${path%/*}
  dir=${dir:-/}
  while [[ $dir != / && ! -f "$dir/mix.exs" ]]; do
    dir=${dir%/*}
    dir=${dir:-/}
  done
  [[ -f "$dir/mix.exs" ]] || continue
  project=$(cd -P "$dir" && printf '%s.' "$PWD")
  project=${project%.}
  found=false
  for existing in "${projects[@]}"; do
    [[ $existing != "$project" ]] || found=true
  done
  $found || projects+=("$project")
  file_projects+=("$project")
  files+=("$path")
done

# Each job has its own process group so cancellation also stops its children.
run_command() {
  local seconds=$((budget - SECONDS))
  if (( seconds <= 0 )); then output="Mix hook timed out."; return 124; fi
  rm -f "$work/timed-out"
  set -m
  "$@" >"$work/output" 2>&1 &
  child=$!
  (
    sleep "$seconds"
    : >"$work/timed-out"
    kill -TERM -- "-$child" 2>/dev/null || :
    sleep 1
    kill -KILL -- "-$child" 2>/dev/null || :
  ) &
  watchdog=$!
  set +m
  status=0
  wait "$child" 2>/dev/null || status=$?
  kill -KILL -- "-$child" 2>/dev/null || :
  child=
  kill -KILL -- "-$watchdog" 2>/dev/null || :
  wait "$watchdog" 2>/dev/null || :
  watchdog=
  output=$(cat "$work/output")
  if [[ -f "$work/timed-out" ]]; then output+=$'\nMix hook timed out.'; return 124; fi
  return "$status"
}

for project in "${projects[@]}"; do
  cd "$project"
  project_files=()
  for ((i=0; i<${#files[@]}; i++)); do
    [[ ${file_projects[i]} != "$project" ]] || project_files+=("${files[i]}")
  done
  # Persistent lock files avoid inode races between independently installed hooks.
  lock_root="${TMPDIR:-/tmp}/elixir-agent-tools-$(id -u)"
  [[ -d $lock_root ]] || mkdir -m 700 "$lock_root" 2>/dev/null || [[ -d $lock_root ]]
  read -r lock_key _ < <(printf '%s' "$project" | cksum)
  exec 9>"$lock_root/$lock_key.lock"
  seconds=$((budget - SECONDS))
  if (( seconds <= 0 )); then
    report "mix $action timed out before checking $project."
    exec 9>&-
    continue
  fi
  if [[ $(uname -s) == Darwin ]]; then
    lock_command=(lockf -s -t "$seconds" 9)
  else
    lock_command=(flock -w "$seconds" 9)
  fi
  if ! run_command "${lock_command[@]}"; then
    report "mix $action could not lock $project: $output"
    exec 9>&-
    continue
  fi
  if [[ $action == compile ]] && command -v lsof >/dev/null; then
    if run_command lsof -a -c beam.smp -d cwd -Fn; then
      if [[ $'\n'$output$'\n' == *$'\n'"n$project"$'\n'* ]]; then
        report "Skipped compilation in $project because a BEAM process is running here."
        exec 9>&-
        continue
      fi
    fi
  fi
  case $action in
    compile)
      if ! run_command mix compile --warnings-as-errors; then
        report "mix compile failed in $project: $output"
      fi
      ;;
    format)
      if ! run_command mix format "${project_files[@]}"; then
        report "mix format failed in $project: $output"
      fi
      ;;
    credo)
      for path in "${project_files[@]}"; do
        if ! run_command mix credo "$path"; then
          if [[ $output == '** (Mix) The task "credo" could not be found' ]]; then
            report "Skipped Credo in $project because it is not installed."
            break
          fi
          report "mix credo failed for $path: $output"
        fi
      done
      ;;
  esac
  exec 9>&-
done
feedback
