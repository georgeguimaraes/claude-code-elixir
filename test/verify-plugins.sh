#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ERRORS=0

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; ERRORS=$((ERRORS + 1)); }

echo "=== Plugin Structure ==="

# All expected plugins exist
for plugin in elixir elixir-lsp mix-format mix-compile mix-credo; do
  if [ -f "$REPO_ROOT/plugins/$plugin/.claude-plugin/plugin.json" ]; then
    pass "$plugin plugin.json exists"
  else
    fail "$plugin plugin.json missing"
  fi
done

echo ""
echo "=== JSON Validity ==="

# Validate all JSON files
while IFS= read -r f; do
  if python3 -m json.tool "$f" > /dev/null 2>&1; then
    pass "$(echo "$f" | sed "s|$REPO_ROOT/||") is valid JSON"
  else
    fail "$(echo "$f" | sed "s|$REPO_ROOT/||") is invalid JSON"
  fi
done < <(find "$REPO_ROOT" -name "*.json" -not -path "*/node_modules/*" -not -path "*/.git/*")

echo ""
echo "=== Plugin JSON Schema ==="

# Each plugin.json has required fields
for plugin in elixir elixir-lsp mix-format mix-compile mix-credo; do
  pjson="$REPO_ROOT/plugins/$plugin/.claude-plugin/plugin.json"
  for field in name version description; do
    if python3 -c "import json,sys; d=json.load(open('$pjson')); assert '$field' in d" 2>/dev/null; then
      pass "$plugin has '$field' field"
    else
      fail "$plugin missing '$field' field"
    fi
  done
done

echo ""
echo "=== elixir-lsp Configuration ==="

LSP_JSON="$REPO_ROOT/plugins/elixir-lsp/.claude-plugin/plugin.json"

if python3 -c "
import json, sys
d = json.load(open('$LSP_JSON'))
cmd = d['lspServers']['expert']['command']
assert 'expert-wrapper' in cmd, f'expected expert-wrapper, got {cmd}'
" 2>/dev/null; then
  pass "LSP command uses expert-wrapper"
else
  fail "LSP command should use expert-wrapper"
fi

WRAPPER="$REPO_ROOT/plugins/elixir-lsp/bin/expert-wrapper"
if [ -f "$WRAPPER" ]; then
  pass "expert-wrapper script exists"
else
  fail "expert-wrapper script missing"
fi

if [ -x "$WRAPPER" ]; then
  pass "expert-wrapper is executable"
else
  fail "expert-wrapper is not executable"
fi

if python3 -c "import ast; ast.parse(open('$WRAPPER').read())" 2>/dev/null; then
  pass "expert-wrapper has valid Python syntax"
else
  fail "expert-wrapper has invalid Python syntax"
fi

if python3 -c "
import json, sys
d = json.load(open('$LSP_JSON'))
exts = d['lspServers']['expert']['extensionToLanguage']
assert '.ex' in exts and '.exs' in exts and '.heex' in exts
" 2>/dev/null; then
  pass "LSP covers .ex, .exs, .heex extensions"
else
  fail "LSP missing expected file extensions"
fi

echo ""
echo "=== Hook Scripts ==="

# Hook scripts exist and are executable
for script in \
  "plugins/elixir/hooks/session-start.sh" \
  "plugins/mix-format/hooks/format-elixir.sh" \
  "plugins/mix-compile/hooks/compile-elixir.sh" \
  "plugins/mix-credo/hooks/credo-elixir.sh"; do

  full="$REPO_ROOT/$script"
  if [ -f "$full" ]; then
    pass "$script exists"
  else
    fail "$script missing"
    continue
  fi

  if bash -n "$full" 2>/dev/null; then
    pass "$script has valid bash syntax"
  else
    fail "$script has invalid bash syntax"
  fi
done

# hooks.json files reference existing scripts
for plugin in elixir mix-format mix-compile mix-credo; do
  hjson="$REPO_ROOT/plugins/$plugin/hooks/hooks.json"
  if [ ! -f "$hjson" ]; then
    fail "$plugin hooks.json missing"
    continue
  fi

  python3 -c "
import json, os, sys, re
data = json.load(open('$hjson'))
root = '$REPO_ROOT/plugins/$plugin'
errors = []
for event_type, matchers in data.get('hooks', {}).items():
    for matcher in matchers:
        for hook in matcher.get('hooks', []):
            cmd = hook.get('command', '')
            cmd = cmd.replace('\${CLAUDE_PLUGIN_ROOT}', root)
            # strip surrounding quotes and get referenced paths
            for token in cmd.split():
                token = token.strip('\"')
                if '/' in token and not os.path.isfile(token):
                    errors.append(token)
if errors:
    for e in errors:
        print(f'MISSING: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null && pass "$plugin hooks.json commands reference existing files" \
             || fail "$plugin hooks.json references missing file"
done

echo ""
echo "=== Skill Files ==="

SKILLS_DIR="$REPO_ROOT/plugins/elixir/skills"
for skill in using-elixir-skills elixir-thinking phoenix-thinking ecto-thinking otp-thinking oban-thinking; do
  skill_file="$SKILLS_DIR/$skill/SKILL.md"
  if [ -f "$skill_file" ]; then
    pass "$skill/SKILL.md exists"
  else
    fail "$skill/SKILL.md missing"
  fi
done

echo ""
echo "=== Marketplace Consistency ==="

MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"

# Every marketplace plugin entry has a matching plugin dir
python3 -c "
import json, os, sys
m = json.load(open('$MARKETPLACE'))
errors = []
for p in m['plugins']:
    source = p['source']
    pjson = os.path.join('$REPO_ROOT', source.lstrip('./'), '.claude-plugin', 'plugin.json')
    if not os.path.isfile(pjson):
        errors.append(f\"{p['name']}: {pjson} not found\")
    else:
        actual = json.load(open(pjson))
        if actual['name'] != p['name']:
            errors.append(f\"Name mismatch: marketplace={p['name']} plugin.json={actual['name']}\")
if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
" 2>/dev/null && pass "All marketplace entries match actual plugins" \
             || fail "Marketplace/plugin mismatch"

echo ""
echo "=== Results ==="
if [ "$ERRORS" -eq 0 ]; then
  echo "All checks passed!"
  exit 0
else
  echo "$ERRORS check(s) failed"
  exit 1
fi
