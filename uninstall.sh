#!/usr/bin/env bash
# Eltávolító – minden fájlt és szolgáltatást töröl
set -euo pipefail
APP_DIR="/opt/calendar_display"
SERVICE_NAME="calendar_display"

if [[ $EUID -ne 0 ]]; then
  echo "Futtasd sudo-val!"
  exit 1
fi

systemctl disable --now ${SERVICE_NAME}.timer || true
systemctl disable --now ${SERVICE_NAME}.service || true
rm -f /etc/systemd/system/${SERVICE_NAME}.service
rm -f /etc/systemd/system/${SERVICE_NAME}.timer
systemctl daemon-reload

rm -rf "$APP_DIR"
echo "Eltávolítás kész."
