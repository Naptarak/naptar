#!/bin/bash

# E-Paper Calendar Display Uninstaller

echo "======================================================"
echo "E-Paper Calendar Display Uninstaller"
echo "======================================================"

# Aktuális felhasználó és könyvtár
CURRENT_USER=$(whoami)
PROJECT_DIR="/home/$CURRENT_USER/epaper_calendar"

# Megerősítés kérése
echo "Ez a script eltávolítja az E-Paper Calendar Display-t és minden kapcsolódó fájlt."
read -p "Biztosan folytatni szeretnéd? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Eltávolítás megszakítva."
    exit 0
fi

# Szolgáltatás leállítása és eltávolítása
echo "Szolgáltatás leállítása és eltávolítása..."
sudo systemctl stop epaper-calendar.service
sudo systemctl disable epaper-calendar.service
sudo rm -f /etc/systemd/system/epaper-calendar.service
sudo systemctl daemon-reload

# Kísérlet a kijelző tisztítására mielőtt eltávolítjuk
echo "Kijelző tisztítása..."
if [ -f "$PROJECT_DIR/initialize_display.py" ]; then
    cd "$PROJECT_DIR"
    python3 "$PROJECT_DIR/initialize_display.py" || true
fi

# Könyvtár eltávolítása
echo "Könyvtár eltávolítása: $PROJECT_DIR"
cd
if [ -d "$PROJECT_DIR" ]; then
    rm -rf "$PROJECT_DIR"
    echo "Könyvtár sikeresen törölve."
else
    echo "A könyvtár már nem létezik."
fi

# Naplófájlok törlése
echo "Naplófájlok törlése..."
rm -f ~/epaper_init.log ~/epaper_calendar.log ~/epaper_calendar_latest.png
echo "Naplófájlok törölve."

# Python csomagok eltávolítása
echo "Python csomagok eltávolítása..."
pip3 uninstall -y astral

echo "======================================================"
echo "Eltávolítás sikeresen befejezve!"
echo "A rendszert érdemes újraindítani a változtatások teljes érvényesítéséhez."
read -p "Szeretnéd most újraindítani a rendszert? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Rendszer újraindítása..."
    sudo reboot
else
    echo "Ne felejtsd el később újraindítani a rendszert."
fi
