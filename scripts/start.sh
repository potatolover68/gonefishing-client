#!/usr/bin/env bash
# Enter the venv and start the encoder in the background.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/logs"
PIDFILE="$ROOT/logs/server.pid"
PY="$ROOT/.venv/bin/python"
if [[ ! -x "$PY" ]]; then
    PY="$ROOT/.venv/Scripts/python.exe"
fi
if [[ ! -x "$PY" && ! -f "$PY" ]]; then
    echo "venv missing; run scripts/install.sh" >&2
    exit 1
fi

if [[ -f "$PIDFILE" ]]; then
    old="$(tr -d '[:space:]' < "$PIDFILE" || true)"
    if [[ "$old" =~ ^[0-9]+$ ]] && kill -0 "$old" 2>/dev/null; then
        alive=0
        if [[ -r "/proc/$old/cmdline" ]]; then
            if tr '\0' ' ' < "/proc/$old/cmdline" | grep -q "server.py"; then
                alive=1
            fi
        else
            alive=1
        fi
        if [[ "$alive" -eq 1 ]]; then
            echo "server already running (pid $old)"
            exit 0
        fi
    fi
fi

cd "$ROOT"
# The server appends to logs/server.log itself. Discard the inherited
# streams so nohup does not also create nohup.out.
nohup "$PY" -u "$ROOT/server.py" >/dev/null 2>&1 &
echo $! > "$PIDFILE"
disown >/dev/null 2>&1 || true
echo "started server pid $(tr -d '[:space:]' < "$PIDFILE")"
