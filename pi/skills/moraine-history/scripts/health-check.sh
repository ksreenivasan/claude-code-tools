#!/bin/bash
set -euo pipefail

MORAINE_BIN="${MORAINE_BIN:-$(command -v moraine 2>/dev/null || true)}"
if [ -z "$MORAINE_BIN" ] && command -v uv >/dev/null 2>&1; then
  MORAINE_BIN="$(uv tool dir --bin)/moraine"
fi
if [ -z "$MORAINE_BIN" ] || [ ! -x "$MORAINE_BIN" ]; then
  echo "Moraine is not installed at $MORAINE_BIN." >&2
  exit 1
fi

MORAINE_BIN="$(cd "$(dirname "$MORAINE_BIN")" && pwd -P)/$(basename "$MORAINE_BIN")"

healthy() {
  "$MORAINE_BIN" status --output json 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin)
services = {item["service"]: item["state"] for item in data.get("services", [])}
ok = data.get("doctor", {}).get("clickhouse_healthy") is True
ok = ok and all(services.get(name) == "running" for name in ("ingest", "backend"))
raise SystemExit(0 if ok else 1)
'
}

if healthy; then
  echo "Moraine is healthy."
  exit 0
fi

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Moraine is down; start it from a host-level service, not a session process." >&2
  exit 1
fi

domain="gui/$(id -u)"
launch_running() {
  launchctl print "$domain/dev.moraine.$1" 2>/dev/null | grep -q 'state = running'
}

if launch_running clickhouse && launch_running ingest && launch_running backend; then
  echo "Moraine launch agents are running, but the stack is not healthy." >&2
  exit 2
fi

for service in clickhouse ingest backend; do
  if ! launch_running "$service"; then
    launchctl kickstart -k "$domain/dev.moraine.$service"
  fi
done

for _ in $(seq 1 30); do
  if healthy; then
    echo "Moraine is healthy."
    exit 0
  fi
  sleep 1
done

echo "Moraine launch agents were started, but the stack is still unhealthy." >&2
"$MORAINE_BIN" status >&2 || true
exit 1
