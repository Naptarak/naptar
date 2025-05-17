#!/bin/bash

# e-Paper Calendar Uninstaller Script
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-Paper HAT

echo "==========================================="
echo "E-Paper Calendar Display - Eltávolító Script"
echo "==========================================="

# Aktuális felhasználó és könyvtár meghatározása
# Ha sudo-val fut, a SUDO_USER változó tartalmazza az eredeti felhasználót
if [ -n "$SUDO_USER" ]; then
    CURRENT_USER=$SUDO_USER
else
    CURRENT_USER=$(logname || whoami)
fi

# Alkalmazás könyvtárának meghatározása
HOME_DIR="/home/$CURRENT_USER"
APP_DIR="$HOME_DIR/e_paper_calendar"

echo "E-Paper naptár eltávolítása a következő felhasználó könyvtárából: $CURRENT_USER"
echo "Alkalmazás könyvtár: $APP_DIR"
echo ""

# Függvény a sikeres műveletek jelzésére
success() {
    echo -e "\e[32mSIKER:\e[0m $1"
    echo ""
}

# Függvény figyelmeztetések megjelenítésére
warning() {
    echo -e "\e[33mFIGYELMEZTETÉS:\e[0m $1"
    echo ""
}

# Szolgáltatás leállítása és eltávolítása
echo "Szolgáltatás leállítása és eltávolítása..."
if sudo systemctl status e-paper-calendar.service &>/dev/null; then
    sudo systemctl stop e-paper-calendar.service
    sudo systemctl disable e-paper-calendar.service
    success "Szolgáltatás leállítva és letiltva"
else
    warning "A szolgáltatás nem fut vagy nem található"
fi

# Szolgáltatás definíció eltávolítása
if [ -f /etc/systemd/system/e-paper-calendar.service ]; then
    sudo rm -f /etc/systemd/system/e-paper-calendar.service
    sudo systemctl daemon-reload
    success "Szolgáltatás definíció eltávolítva"
else
    warning "Szolgáltatás definíciós fájl nem található"
fi

# Rendszer tisztítása
echo "Kérdés: Szeretné eltávolítani az alkalmazás fájlokat és a telepített függőségeket is? (i/n)"
read -r answer

if [ "$answer" = "i" ] || [ "$answer" = "I" ]; then
    # Alkalmazás fájlok törlése
    echo "Alkalmazás fájlok törlése..."
    if [ -d "$APP_DIR" ]; then
        sudo rm -rf "$APP_DIR"
        success "Alkalmazás fájlok törölve"
    else
        warning "Az alkalmazás könyvtár nem található: $APP_DIR"
    fi
    
    # Python csomagok eltávolítása
    echo "Szeretné eltávolítani az összes telepített Python csomagot? (i/n)"
    read -r remove_pip
    
    if [ "$remove_pip" = "i" ] || [ "$remove_pip" = "I" ]; then
        echo "Python csomagok eltávolítása..."
        PIP_PACKAGES="RPi.GPIO spidev pytz requests ephem feedparser holidays python-dateutil pillow"
        
        # Ellenőrizzük, hogy a virtuális környezet létezik-e
        if [ -d "$APP_DIR/venv" ]; then
            # Ha még nem töröltük a könyvtárat
            echo "A virtuális környezet eltávolítása..."
            source $APP_DIR/venv/bin/activate
            pip uninstall -y $PIP_PACKAGES
            deactivate
            success "Virtuális környezet csomagok eltávolítva"
        else
            # Rendszerszintű csomagok eltávolításának megerősítése
            echo "A rendszerszintű Python csomagok eltávolítása befolyásolhatja más alkalmazásokat."
            echo "Biztosan el szeretné távolítani a rendszerszintű Python csomagokat? (i/n)"
            read -r confirm_pip_removal
            
            if [ "$confirm_pip_removal" = "i" ] || [ "$confirm_pip_removal" = "I" ]; then
                sudo pip3 uninstall -y $PIP_PACKAGES
                success "Rendszerszintű Python csomagok eltávolítva"
            else
                echo "Rendszerszintű Python csomagok megtartva"
            fi
        fi
    fi
    
    # Waveshare könyvtár eltávolítása
    echo "Szeretné eltávolítani a letöltött Waveshare e-Paper könyvtárat is? (i/n)"
    read -r remove_waveshare
    
    if [ "$remove_waveshare" = "i" ] || [ "$remove_waveshare" = "I" ]; then
        echo "Waveshare e-Paper könyvtár keresése és törlése..."
        # Keressük meg és töröljük a letöltött Waveshare könyvtárakat
        WAVESHARE_DIRS=$(find $HOME_DIR -name "e-Paper" -type d 2>/dev/null)
        
        if [ -n "$WAVESHARE_DIRS" ]; then
            echo "Talált Waveshare könyvtárak:"
            echo "$WAVESHARE_DIRS"
            echo "Ezek a könyvtárak törlésre kerülnek. Folytatja? (i/n)"
            read -r confirm_waveshare_removal
            
            if [ "$confirm_waveshare_removal" = "i" ] || [ "$confirm_waveshare_removal" = "I" ]; then
                echo "$WAVESHARE_DIRS" | xargs sudo rm -rf
                success "Waveshare e-Paper könyvtárak törölve"
            else
                echo "Waveshare könyvtárak megtartva"
            fi
        else
            warning "Nem található Waveshare e-Paper könyvtár"
        fi
    fi
    
    # Naplófájlok eltávolítása
    echo "Szeretné eltávolítani a telepítési és alkalmazás naplófájlokat is? (i/n)"
    read -r remove_logs
    
    if [ "$remove_logs" = "i" ] || [ "$remove_logs" = "I" ]; then
        echo "Naplófájlok eltávolítása..."
        sudo rm -f $HOME_DIR/install_log.txt
        if [ -f "$HOME_DIR/calendar.log" ]; then
            sudo rm -f $HOME_DIR/calendar.log
        fi
        success "Naplófájlok eltávolítva"
    fi
    
    # SPI interfész állapotának visszaállítása
    echo "Szeretné visszaállítani az SPI interfészt az eredeti állapotba (kikapcsolni)? (i/n)"
    read -r disable_spi
    
    if [ "$disable_spi" = "i" ] || [ "$disable_spi" = "I" ]; then
        echo "SPI interfész kikapcsolása..."
        if grep -q "dtparam=spi=on" /boot/config.txt; then
            sudo sed -i '/dtparam=spi=on/d' /boot/config.txt
            REBOOT_NEEDED=1
            success "SPI interfész kikapcsolva (újraindítás szükséges)"
        else
            warning "Az SPI interfész már ki van kapcsolva"
            REBOOT_NEEDED=0
        fi
    else
        echo "SPI interfész beállítások megtartva"
        REBOOT_NEEDED=0
    fi
else
    echo "Alkalmazás fájlok megtartása..."
    REBOOT_NEEDED=0
fi

echo ""
echo "==========================================="
echo "Eltávolítás befejezve!"
echo "==========================================="
echo "Az e-Paper naptár alkalmazás eltávolítása befejeződött."
echo ""

# Figyelmeztetés az újraindításról, ha SPI beállítások változtak
if [ "$REBOOT_NEEDED" = "1" ]; then
    echo -e "\e[33mFIGYELEM:\e[0m Az SPI interfész beállításainak érvényesítéséhez újra kell indítani a Raspberry Pi-t!"
    echo "Újraindítás most? (i/n)"
    read -r answer
    if [ "$answer" = "i" ] || [ "$answer" = "I" ]; then
        echo "A Raspberry Pi újraindul..."
        sudo reboot
    else
        echo "Kérjük, indítsa újra a Raspberry Pi-t manuálisan a későbbiekben!"
    fi
fi
