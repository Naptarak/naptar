#!/bin/bash

# E-Paper Calendar Display Uninstaller

echo "======================================================"
echo "E-Paper Calendar Display Uninstaller"
echo "======================================================"

# Aktuális felhasználó és könyvtár
CURRENT_USER=$(whoami)
PROJECT_DIR="/home/$CURRENT_USER/epaper_calendar"

# Szolgáltatás leállítása és eltávolítása
echo "Szolgáltatás leállítása és eltávolítása..."
sudo systemctl stop epaper-calendar.service
sudo systemctl disable epaper-calendar.service
sudo rm -f /etc/systemd/system/epaper-calendar.service
sudo systemctl daemon-reload

# Kijelző törlése
echo "Kijelző törlése..."
if [ -f "$PROJECT_DIR/epd_driver.py" ]; then
    python3 "$PROJECT_DIR/epd_driver.py" clear
fi

# Könyvtárak eltávolítása
echo "Könyvtár eltávolítása: $PROJECT_DIR"
rm -rf "$PROJECT_DIR"

echo "Eltávolítás kész!"
