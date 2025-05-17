#!/bin/bash

# e-Paper Calendar Uninstaller Script (Kibővített diagnosztikával)
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-Paper HAT

echo "==========================================="
echo "E-Paper Calendar Display - Eltávolító Script"
echo "==========================================="

# Aktuális könyvtár mentése
SCRIPT_DIR="$(pwd)"

# Log könyvtár létrehozása
UNINSTALL_LOG_DIR="$SCRIPT_DIR/uninstall_logs"
mkdir -p "$UNINSTALL_LOG_DIR"
MAIN_LOG="$UNINSTALL_LOG_DIR/uninstall_main.log"

# Dátum és idő a naplóban
echo "Eltávolítás indítása: $(date)" > "$MAIN_LOG"

# Aktuális felhasználó és könyvtár meghatározása
# Ha sudo-val fut, a SUDO_USER változó tartalmazza az eredeti felhasználót
if [ -n "$SUDO_USER" ]; then
    CURRENT_USER=$SUDO_USER
    echo "Eltávolítás sudo felhasználóként, eredeti felhasználó: $CURRENT_USER" | tee -a "$MAIN_LOG"
else
    CURRENT_USER=$(logname 2>/dev/null || whoami)
    echo "Eltávolítás normál felhasználóként: $CURRENT_USER" | tee -a "$MAIN_LOG"
fi

# Ellenőrizzük, hogy van-e root jogosultság
if [ "$(id -u)" -ne 0 ]; then
    echo "FIGYELMEZTETÉS: Az eltávolítás nem rendszergazdai (root) jogosultsággal fut. Bizonyos lépések sikertelenek lehetnek." | tee -a "$MAIN_LOG"
    echo "Javasolt az eltávolítást 'sudo ./uninstall.sh' paranccsal futtatni." | tee -a "$MAIN_LOG"
    echo "Folytatja az eltávolítást root jogosultság nélkül? (i/n)"
    read -r answer
    if [ "$answer" != "i" ] && [ "$answer" != "I" ]; then
        echo "Eltávolítás megszakítva." | tee -a "$MAIN_LOG"
        exit 1
    fi
fi

# Alkalmazás könyvtárának meghatározása
HOME_DIR="/home/$CURRENT_USER"
APP_DIR="$HOME_DIR/e_paper_calendar"

echo "E-Paper naptár eltávolítása a következő felhasználó könyvtárából: $CURRENT_USER" | tee -a "$MAIN_LOG"
echo "Alkalmazás könyvtár: $APP_DIR" | tee -a "$MAIN_LOG"
echo ""

# Függvény a sikeres műveletek jelzésére
success() {
    echo -e "\e[32mSIKER:\e[0m $1" | tee -a "$MAIN_LOG"
    echo ""
}

# Függvény figyelmeztetések megjelenítésére
warning() {
    echo -e "\e[33mFIGYELMEZTETÉS:\e[0m $1" | tee -a "$MAIN_LOG"
    echo ""
}

# Függvény a hibák kezelésére
handle_error() {
    echo -e "\e[31mHIBA:\e[0m $1" | tee -a "$MAIN_LOG"
    echo ""
}

# Szolgáltatás leállítása és eltávolítása
echo "Szolgáltatás leállítása és eltávolítása..." | tee -a "$MAIN_LOG"
if [ "$(id -u)" -eq 0 ]; then
    if systemctl status e-paper-calendar.service &>/dev/null; then
        systemctl stop e-paper-calendar.service | tee -a "$MAIN_LOG"
        systemctl disable e-paper-calendar.service | tee -a "$MAIN_LOG"
        success "Szolgáltatás leállítva és letiltva"
    else
        warning "A szolgáltatás nem fut vagy nem található"
    fi

    # Szolgáltatás definíció eltávolítása
    if [ -f /etc/systemd/system/e-paper-calendar.service ]; then
        rm -f /etc/systemd/system/e-paper-calendar.service | tee -a "$MAIN_LOG"
        systemctl daemon-reload | tee -a "$MAIN_LOG"
        success "Szolgáltatás definíció eltávolítva"
    else
        warning "Szolgáltatás definíciós fájl nem található"
    fi
else
    warning "Szolgáltatás eltávolítása kihagyva (nem rendszergazda)"
    echo "Futtassa a következő parancsokat manuálisan rendszergazdaként:" | tee -a "$MAIN_LOG"
    echo "sudo systemctl stop e-paper-calendar.service" | tee -a "$MAIN_LOG"
    echo "sudo systemctl disable e-paper-calendar.service" | tee -a "$MAIN_LOG"
    echo "sudo rm -f /etc/systemd/system/e-paper-calendar.service" | tee -a "$MAIN_LOG"
    echo "sudo systemctl daemon-reload" | tee -a "$MAIN_LOG"
fi

# Rendszer tisztítása
echo "Kérdés: Szeretné eltávolítani az alkalmazás fájlokat és a telepített függőségeket is? (i/n)"
read -r answer

if [ "$answer" = "i" ] || [ "$answer" = "I" ]; then
    # Alkalmazás fájlok törlése
    echo "Alkalmazás fájlok törlése..." | tee -a "$MAIN_LOG"
    if [ -d "$APP_DIR" ]; then
        # Naplófájlok mentése előbb
        if [ -f "$APP_DIR/calendar.log" ]; then
            cp "$APP_DIR/calendar.log" "$UNINSTALL_LOG_DIR/calendar.log" | tee -a "$MAIN_LOG"
            success "Naplófájl másolata mentve: $UNINSTALL_LOG_DIR/calendar.log"
        fi
        
        if [ -f "$APP_DIR/epaper_test.log" ]; then
            cp "$APP_DIR/epaper_test.log" "$UNINSTALL_LOG_DIR/epaper_test.log" | tee -a "$MAIN_LOG"
            success "Teszt naplófájl másolata mentve: $UNINSTALL_LOG_DIR/epaper_test.log"
        fi
        
        # Alkalmazás könyvtár törlése
        if ! rm -rf "${APP_DIR:?}" >> "$MAIN_LOG" 2>&1; then
            handle_error "Nem sikerült törölni az alkalmazás könyvtárat. Próbálja manuálisan: rm -rf $APP_DIR"
        else
            success "Alkalmazás fájlok törölve"
        fi
    else
        warning "Az alkalmazás könyvtár nem található: $APP_DIR"
    fi
    
    # Python csomagok eltávolítása
    echo "Szeretné eltávolítani az összes telepített Python csomagot? (i/n)"
    read -r remove_pip
    
    if [ "$remove_pip" = "i" ] || [ "$remove_pip" = "I" ]; then
        echo "Python csomagok eltávolítása..." | tee -a "$MAIN_LOG"
        PIP_PACKAGES="RPi.GPIO spidev pytz requests ephem feedparser holidays python-dateutil pillow"
        
        # A virtuális környezet már lehet, hogy törölve lett az alkalmazás könyvtárral együtt
        if [ -d "$APP_DIR/venv" ]; then
            echo "Virtuális környezet megtalálva, csomagok eltávolítása onnan..." | tee -a "$MAIN_LOG"
            source "$APP_DIR/venv/bin/activate"
            pip uninstall -y $PIP_PACKAGES >> "$MAIN_LOG" 2>&1
            deactivate
            success "Virtuális környezet csomagok eltávolítva"
        else
            # Rendszerszintű csomagok eltávolításának megerősítése
            echo "A rendszerszintű Python csomagok eltávolítása befolyásolhatja más alkalmazásokat." | tee -a "$MAIN_LOG"
            echo "Biztosan el szeretné távolítani a rendszerszintű Python csomagokat? (i/n)"
            read -r confirm_pip_removal
            
            if [ "$confirm_pip_removal" = "i" ] || [ "$confirm_pip_removal" = "I" ]; then
                if [ "$(id -u)" -eq 0 ]; then
                    pip3 uninstall -y $PIP_PACKAGES >> "$MAIN_LOG" 2>&1
                    success "Rendszerszintű Python csomagok eltávolítva"
                else
                    warning "Rendszerszintű Python csomagok eltávolítása kihagyva (nem rendszergazda)"
                    echo "Futtassa a következő parancsot manuálisan rendszergazdaként:" | tee -a "$MAIN_LOG"
                    echo "sudo pip3 uninstall -y $PIP_PACKAGES" | tee -a "$MAIN_LOG"
                fi
            else
                echo "Rendszerszintű Python csomagok megtartva" | tee -a "$MAIN_LOG"
            fi
        fi
    fi
    
    # Waveshare könyvtár eltávolítása
    echo "Szeretné eltávolítani a letöltött Waveshare e-Paper könyvtárat is? (i/n)"
    read -r remove_waveshare
    
    if [ "$remove_waveshare" = "i" ] || [ "$remove_waveshare" = "I" ]; then
        echo "Waveshare e-Paper könyvtár keresése és törlése..." | tee -a "$MAIN_LOG"
        # Keressük meg és töröljük a letöltött Waveshare könyvtárakat
        WAVESHARE_DIRS=$(find "$HOME_DIR" -name "e-Paper" -type d 2>/dev/null)
        
        if [ -n "$WAVESHARE_DIRS" ]; then
            echo "Talált Waveshare könyvtárak:" | tee -a "$MAIN_LOG"
            echo "$WAVESHARE_DIRS" | tee -a "$MAIN_LOG"
            echo "Ezek a könyvtárak törlésre kerülnek. Folytatja? (i/n)"
            read -r confirm_waveshare_removal
            
            if [ "$confirm_waveshare_removal" = "i" ] || [ "$confirm_waveshare_removal" = "I" ]; then
                while read -r dir; do
                    if ! rm -rf "$dir" >> "$MAIN_LOG" 2>&1; then
                        handle_error "Nem sikerült törölni a könyvtárat: $dir"
                    else
                        success "Könyvtár törölve: $dir"
                    fi
                done <<< "$WAVESHARE_DIRS"
                success "Waveshare e-Paper könyvtárak törölve"
            else
                echo "Waveshare könyvtárak megtartva" | tee -a "$MAIN_LOG"
            fi
        else
            warning "Nem található Waveshare e-Paper könyvtár"
        fi
    fi
    
    # SPI interfész állapotának visszaállítása
    echo "Szeretné visszaállítani az SPI interfészt az eredeti állapotba (kikapcsolni)? (i/n)"
    read -r disable_spi
    
    if [ "$disable_spi" = "i" ] || [ "$disable_spi" = "I" ]; then
        echo "SPI interfész kikapcsolása..." | tee -a "$MAIN_LOG"
        if [ "$(id -u)" -eq 0 ]; then
            if grep -q "dtparam=spi=on" /boot/config.txt; then
                sed -i '/dtparam=spi=on/d' /boot/config.txt
                REBOOT_NEEDED=1
                success "SPI interfész kikapcsolva (újraindítás szükséges)"
            else
                warning "Az SPI interfész már ki van kapcsolva"
                REBOOT_NEEDED=0
            fi
        else
            warning "SPI interfész kikapcsolása kihagyva (nem rendszergazda)"
            echo "Futtassa a következő parancsot manuálisan rendszergazdaként:" | tee -a "$MAIN_LOG"
echo "sudo sed -i '/dtparam=spi=on/d' /boot/config.txt" | tee -a "$MAIN_LOG"
            REBOOT_NEEDED=1
        fi
    else
        echo "SPI interfész beállítások megtartva" | tee -a "$MAIN_LOG"
        REBOOT_NEEDED=0
    fi

    # Telepítési naplók eltávolítása
    echo "Szeretné eltávolítani a telepítési naplófájlokat is? (i/n)"
    read -r remove_logs
    
    if [ "$remove_logs" = "i" ] || [ "$remove_logs" = "I" ]; then
        echo "Telepítési naplók keresése és eltávolítása..." | tee -a "$MAIN_LOG"
        INSTALL_LOGS=$(find "$HOME_DIR" -name "install_log*.txt" -o -name "install_logs" -type d 2>/dev/null)
        
        if [ -n "$INSTALL_LOGS" ]; then
            echo "Talált telepítési naplók:" | tee -a "$MAIN_LOG"
            echo "$INSTALL_LOGS" | tee -a "$MAIN_LOG"
            while read -r log; do
                if ! rm -rf "$log" >> "$MAIN_LOG" 2>&1; then
                    handle_error "Nem sikerült törölni a naplót: $log"
                else
                    success "Napló törölve: $log"
                fi
            done <<< "$INSTALL_LOGS"
        else
            warning "Nem találhatók telepítési naplófájlok"
        fi
    fi
else
    echo "Alkalmazás fájlok megtartása..." | tee -a "$MAIN_LOG"
    REBOOT_NEEDED=0
fi

echo ""
echo "==========================================="
echo "Eltávolítás befejezve!"
echo "==========================================="
echo "Az e-Paper naptár alkalmazás eltávolítása befejeződött."
echo "Napló: $MAIN_LOG"
echo ""

# Figyelmeztetés az újraindításról, ha SPI beállítások változtak
if [ "$REBOOT_NEEDED" = "1" ]; then
    echo -e "\e[33mFIGYELEM:\e[0m Az SPI interfész beállításainak érvényesítéséhez újra kell indítani a Raspberry Pi-t!"
    echo "Újraindítás most? (i/n)"
    read -r answer
    if [ "$answer" = "i" ] || [ "$answer" = "I" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            echo "A Raspberry Pi újraindul..."
            reboot
        else
            warning "Újraindítás kihagyva (nem rendszergazda)"
            echo "Futtassa a következő parancsot manuálisan rendszergazdaként:"
            echo "sudo reboot"
        fi
    else
        echo "Kérjük, indítsa újra a Raspberry Pi-t manuálisan a későbbiekben!"
    fi
fi
