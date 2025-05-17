#!/bin/bash

# e-Paper Calendar Uninstaller Script
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-Paper HAT

echo "==========================================="
echo "E-Paper Calendar Display - Eltávolító Script"
echo "==========================================="

# Aktuális felhasználó és könyvtár meghatározása
CURRENT_USER=$(whoami)
HOME_DIR="/home/$CURRENT_USER"
APP_DIR="$HOME_DIR/e_paper_calendar"

echo "Alkalmazás eltávolítása a következő könyvtárból: $APP_DIR"
echo ""

# Függvény a sikeres műveletek jelzésére
success() {
    echo -e "\e[32mSIKER:\e[0m $1"
    echo ""
}

# Szolgáltatás leállítása és eltávolítása
echo "Szolgáltatás leállítása és eltávolítása..."
sudo systemctl stop e-paper-calendar.service
sudo systemctl disable e-paper-calendar.service
sudo rm -f /etc/systemd/system/e-paper-calendar.service
sudo systemctl daemon-reload
success "Szolgáltatás eltávolítva"

# Rendszer tisztítása
echo "Kérdés: Szeretné eltávolítani az alkalmazás fájlokat és a telepített függőségeket is? (i/n)"
read -r answer

if [ "$answer" = "i" ] || [ "$answer" = "I" ]; then
    # Alkalmazás fájlok törlése
    echo "Alkalmazás fájlok törlése..."
    if [ -d "$APP_DIR" ]; then
        rm -rf "$APP_DIR"
        success "Alkalmazás fájlok törölve"
    else
        echo "Az alkalmazás könyvtár nem található: $APP_DIR"
    fi
    
    # Python csomagok eltávolítása
    echo "Szeretné eltávolítani az összes telepített Python csomagot? (i/n)"
    read -r remove_pip
    
    if [ "$remove_pip" = "i" ] || [ "$remove_pip" = "I" ]; then
        echo "Python csomagok eltávolítása..."
        PIP_PACKAGES="RPi.GPIO spidev pytz requests ephem feedparser holidays python-dateutil pillow"
        
        # Ellenőrizzük, hogy a virtuális környezet létezik-e
        if [ -d "$APP_DIR/venv" ]; then
            source $APP_DIR/venv/bin/activate
            pip uninstall -y $PIP_PACKAGES
            deactivate
        else
            sudo pip3 uninstall -y $PIP_PACKAGES
        fi
        success "Python csomagok eltávolítva"
    fi
    
    # Waveshare könyvtár eltávolítása
    echo "Szeretné eltávolítani a Waveshare e-Paper könyvtárat is? (i/n)"
    read -r remove_waveshare
    
    if [ "$remove_waveshare" = "i" ] || [ "$remove_waveshare" = "I" ]; then
        echo "Waveshare e-Paper könyvtár keresése és törlése..."
        # Keressük meg és töröljük a letöltött Waveshare könyvtárakat
        find $HOME_DIR -name "e-Paper" -type d -exec rm -rf {} \; 2>/dev/null
        success "Waveshare e-Paper könyvtárak törölve"
    fi
else
    echo "Alkalmazás fájlok megtartása..."
fi

echo ""
echo "==========================================="
echo "Eltávolítás befejezve!"
echo "==========================================="
echo "Az e-Paper naptár alkalmazás sikeresen eltávolítva."
echo ""
