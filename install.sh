#!/bin/bash

# E-Paper Calendar Display Installer (DEPEND-FIX)
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-paper HAT

echo "======================================================"
echo "E-Paper Calendar Display Installer (DEPEND-FIX)"
echo "Raspberry Pi Zero 2W + Waveshare 4.01 inch 7-color HAT"
echo "======================================================"

# Aktuális felhasználó és könyvtárak
CURRENT_USER=$(whoami)
echo "Telepítés a következő felhasználóhoz: $CURRENT_USER"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="/home/$CURRENT_USER/epaper_calendar"

# Könyvtár létrehozása, ha nem létezik
mkdir -p "$PROJECT_DIR"

# Fájlok másolása a telepítési könyvtárba
echo "Fájlok másolása a telepítési könyvtárba..."
cp -r "$SCRIPT_DIR"/* "$PROJECT_DIR"
chmod +x "$PROJECT_DIR"/*.py "$PROJECT_DIR"/*.sh

# Alapvető csomagok telepítése rendszerszinten
echo "Alapvető rendszerfüggőségek telepítése..."
sudo apt-get update
sudo apt-get install -y python3-dev python3-pip python3-venv
sudo apt-get install -y python3-pillow python3-rpi.gpio python3-spidev
sudo apt-get install -y python3-feedparser python3-dateutil python3-requests

# Virtuális környezet létrehozása
echo "Python virtuális környezet létrehozása..."
cd "$PROJECT_DIR"
python3 -m venv venv
# A venv activate szkript elérési útja
ACTIVATE="$PROJECT_DIR/venv/bin/activate"

# Python függőségek telepítése a virtuális környezetbe
echo "Python függőségek telepítése a virtuális környezetbe..."
# A source helyett a . parancsot használjuk, mert kompatibilisebb
. "$ACTIVATE"
# Frissítsük a pip-et a virtuális környezetben
pip install --upgrade pip
# Telepítsük a függőségeket
pip install requests astral
# Ellenőrizzük, hogy a requests telepítve van-e
python -c "import requests; print('Requests verzió:', requests.__version__)" || { 
    echo "A requests csomag nem telepíthető a virtuális környezetbe. Rendszerszintű használatra váltás..."; 
    VENV_FAILED=true; 
}
deactivate

# SPI engedélyezése
echo "SPI interfész ellenőrzése..."
if ! grep -q "^dtparam=spi=on" /boot/config.txt; then
    echo "SPI interfész engedélyezése..."
    echo "dtparam=spi=on" | sudo tee -a /boot/config.txt
    echo "SPI engedélyezve, újraindítás szükséges lesz"
    REBOOT_NEEDED=true
fi

# Felhasználó hozzáadása csoportokhoz
echo "Felhasználói jogosultságok beállítása..."
sudo usermod -a -G spi,gpio,dialout "$CURRENT_USER"
echo "Felhasználó hozzáadva a szükséges csoportokhoz"

# Systemd szolgáltatás létrehozása
echo "Systemd szolgáltatás létrehozása..."
# Ha a virtuális környezet sikertelen volt, használjuk a rendszer Pythont
if [ "$VENV_FAILED" = true ]; then
    sudo bash -c "cat > /etc/systemd/system/epaper-calendar.service" << EOL
[Unit]
Description=E-Paper Calendar Display Service
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/python3 $PROJECT_DIR/calendar_display.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOL
    echo "Figyelem: Rendszerszintű Python módot használunk a virtuális környezet helyett"
else
    sudo bash -c "cat > /etc/systemd/system/epaper-calendar.service" << EOL
[Unit]
Description=E-Paper Calendar Display Service
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python $PROJECT_DIR/calendar_display.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOL
    echo "Virtuális környezet módot használunk"
fi

sudo chmod 644 /etc/systemd/system/epaper-calendar.service

# Systemd szolgáltatás aktiválása
echo "Systemd szolgáltatás aktiválása..."
sudo systemctl daemon-reload
sudo systemctl enable epaper-calendar.service

# A Python program módosítása, hogy kezelje a hiányzó modulokat
echo "Python program módosítása a hiányzó modulok kezelésére..."
cat > "$PROJECT_DIR/dependencies_check.py" << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import subprocess
import importlib.util

def check_module(module_name):
    """Ellenőrzi, hogy egy Python modul elérhető-e, és telepíti, ha hiányzik"""
    if importlib.util.find_spec(module_name) is None:
        print(f"A(z) {module_name} modul hiányzik. Telepítési kísérlet...")
        try:
            # Próbáljuk rendszerszinten telepíteni
            subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", module_name])
            print(f"A(z) {module_name} modul sikeresen telepítve!")
            # Újra kell importálni a modult
            __import__(module_name)
            return True
        except Exception as e:
            print(f"Nem sikerült telepíteni a(z) {module_name} modult: {e}")
            return False
    return True

# Főprogram indításakor ellenőrizzük a függőségeket
if __name__ == "__main__":
    modules_to_check = ["requests", "astral", "feedparser", "dateutil", "PIL"]
    
    all_modules_available = True
    for module in modules_to_check:
        if not check_module(module):
            all_modules_available = False
    
    if not all_modules_available:
        print("Nem minden szükséges modul érhető el. A program nem fut.")
        sys.exit(1)
    
    print("Minden szükséges modul elérhető.")
EOL

# Módosítsuk a fő programot, hogy először ellenőrizze a függőségeket
sed -i '1s/^/from dependencies_check import check_module\n/' "$PROJECT_DIR/calendar_display.py"
sed -i '/^import os/i # Függőségek ellenőrzése\nfor module in ["requests", "astral", "feedparser", "dateutil", "PIL"]:\n    check_module(module)\n' "$PROJECT_DIR/calendar_display.py"

# Összegzés és útmutatás
echo "========================================================================"
echo "Telepítés kész!"
echo ""
echo "A függőségi problémák megoldásához:"
echo "1. Rendszerszinten telepítettük a szükséges csomagokat"
echo "2. Létrehoztunk egy virtuális környezetet alternatívaként"
echo "3. Módosítottuk a programot, hogy kezelje a hiányzó modulokat"
echo ""
echo "Ha most engedélyezted az SPI interfészt, újraindítás szükséges."
echo "Újraindítás után a szolgáltatás automatikusan elindul."
echo ""
echo "Kézi teszteléshez futtasd:"
echo "cd $PROJECT_DIR && python3 calendar_display.py"
echo ""
echo "Ha hibát látsz, próbáld meg rendszerszinten telepíteni a modult:"
echo "sudo apt-get install python3-requests python3-astral"
echo ""
echo "Szolgáltatás kezelése:"
echo "sudo systemctl start epaper-calendar.service"
echo "sudo systemctl stop epaper-calendar.service"
echo "sudo systemctl restart epaper-calendar.service"
echo ""
echo "Eltávolításhoz futtasd:"
echo "$PROJECT_DIR/uninstall.sh"
echo "========================================================================"

# Újraindítás, ha szükséges
if [ "$REBOOT_NEEDED" = true ]; then
    echo "Az SPI interfész most lett engedélyezve, újraindítás szükséges."
    read -p "Szeretnéd most újraindítani a rendszert? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Rendszer újraindítása..."
        sudo reboot
    else
        echo "Kérlek, indítsd újra a rendszert, amikor alkalmas."
    fi
else
    # Indítsuk el a szolgáltatást
    echo "Szolgáltatás indítása..."
    sudo systemctl start epaper-calendar.service
    echo "Szolgáltatás elindítva"
fi
