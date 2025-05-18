#!/bin/bash

# E-Paper Calendar Display Installer (JAVÍTOTT)
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-paper HAT

echo "======================================================"
echo "E-Paper Calendar Display Installer (JAVÍTOTT)"
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

# Alapvető csomagok telepítése
echo "Alapvető függőségek telepítése..."
sudo apt-get update
sudo apt-get install -y python3-dev python3-pip python3-venv
sudo apt-get install -y python3-pillow python3-rpi.gpio python3-spidev
sudo apt-get install -y python3-feedparser python3-dateutil

# Virtuális környezet létrehozása
echo "Python virtuális környezet létrehozása..."
cd "$PROJECT_DIR"
python3 -m venv venv
source venv/bin/activate

# Python függőségek telepítése a virtuális környezetbe
echo "Python függőségek telepítése a virtuális környezetbe..."
pip install astral requests

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

# Systemd szolgáltatás létrehozása - most már a virtuális környezetet használja
echo "Systemd szolgáltatás létrehozása..."
sudo bash -c "cat > /etc/systemd/system/epaper-calendar.service" << EOL
[Unit]
Description=E-Paper Calendar Display Service
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 $PROJECT_DIR/calendar_display.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOL

sudo chmod 644 /etc/systemd/system/epaper-calendar.service

# Systemd szolgáltatás aktiválása
echo "Systemd szolgáltatás aktiválása..."
sudo systemctl daemon-reload
sudo systemctl enable epaper-calendar.service

# Összegzés és útmutatás
echo "========================================================================"
echo "Telepítés kész!"
echo ""
echo "Létrehoztunk egy dedikált Python virtuális környezetet a"
echo "függőségek kezeléséhez, így elkerülve az 'externally-managed-environment' hibát."
echo ""
echo "Ha most engedélyezted az SPI interfészt, újraindítás szükséges."
echo "Újraindítás után a szolgáltatás automatikusan elindul."
echo ""
echo "Kézi teszteléshez aktiváld a virtuális környezetet:"
echo "cd $PROJECT_DIR && source venv/bin/activate"
echo "majd futtasd: python calendar_display.py"
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
