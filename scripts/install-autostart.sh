#!/usr/bin/env bash
# Register the start script with systemd so it runs when this user logs in.
# A user service, rather than a system unit, keeps the server on this user's
# venv and GPU.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
START="$ROOT/scripts/start.sh"
chmod +x "$ROOT/scripts/install.sh" "$START" "$ROOT/scripts/install-autostart.sh"

if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemd is required to install the user service" >&2
    exit 1
fi

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$UNIT_DIR"
PIDFILE="$ROOT/logs/server.pid"
cat > "$UNIT_DIR/gonefishing-local.service" << EOF
[Unit]
Description=Gone Fishing local encoder
After=default.target

[Service]
Type=forking
ExecStart=$START
PIDFile=$PIDFILE
WorkingDirectory=$ROOT

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable gonefishing-local.service
echo "gonefishing-local.service will run at logon for this user"
