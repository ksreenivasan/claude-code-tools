#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES="$SCRIPT_DIR/default.rules"

if command -v codex >/dev/null 2>&1; then
  CODEX_BIN="$(command -v codex)"
elif [ -x "/Applications/ChatGPT.app/Contents/Resources/codex" ]; then
  CODEX_BIN="/Applications/ChatGPT.app/Contents/Resources/codex"
else
  echo "ERROR: Codex CLI not found." >&2
  exit 1
fi

PASS=0
FAIL=0

check_prompt() {
  local output
  output=$("$CODEX_BIN" execpolicy check --rules "$RULES" -- "$@")
  if [[ "$output" == *'"decision":"prompt"'* ]]; then
    printf 'PASS prompt:'
    printf ' %q' "$@"
    printf '\n'
    PASS=$((PASS + 1))
  else
    printf 'FAIL expected prompt: %q ' "$@" >&2
    printf '\n%s\n' "$output" >&2
    FAIL=$((FAIL + 1))
  fi
}

check_unmatched() {
  local output
  output=$("$CODEX_BIN" execpolicy check --rules "$RULES" -- "$@")
  if [[ "$output" != *'"decision"'* ]]; then
    printf 'PASS unmatched:'
    printf ' %q' "$@"
    printf '\n'
    PASS=$((PASS + 1))
  else
    printf 'FAIL expected unmatched: %q ' "$@" >&2
    printf '\n%s\n' "$output" >&2
    FAIL=$((FAIL + 1))
  fi
}

check_prompt rm -rf build
check_prompt rm --recursive generated
check_prompt git reset --hard HEAD~1
check_prompt git clean -fd
check_prompt git push --force-with-lease origin feature
check_prompt git push --delete origin old-branch
check_prompt gh repo delete owner/repo
check_prompt terraform destroy -auto-approve
check_prompt kubectl delete namespace staging

check_unmatched rm /tmp/one-file
check_unmatched git clean -n
check_unmatched git push origin main
check_unmatched terraform plan
check_unmatched kubectl get pods

printf '\n%d passed; %d failed\n' "$PASS" "$FAIL"
test "$FAIL" -eq 0
