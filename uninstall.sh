#!/bin/bash

# e-Paper Calendar Uninstaller Script - Javított verzió
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-Paper HAT

# Színek a kimenethez
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
BOLD="\033[1m"
RESET="\033[0m"

echo -e "${BLUE}===========================================${RESET}"
echo -e "${BOLD}E-Paper Calendar Display - Eltávolító Script${RESET}"
echo -e "${BLUE}===========================================${RESET}"

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

echo -e "${BOLD}E-Paper naptár eltávolítása a következő felhasználó könyvtárából:${RESET} $CURRENT_USER"
echo -e "${BOLD}Alkalmazás könyvtár:${RESET} $APP_DIR"
echo ""

# Függvény a sikeres műveletek jelzésére
success() {
    echo -e "${GREEN}SIKER:${RESET} $1"
    echo ""
}

# Függvény figyelmeztetések megjelenítésére
warning() {
    echo -e "${YELLOW}FIGYELMEZTETÉS:${RESET} $1"
    echo ""
}

# Függvény hibák jelzésére
error() {
    echo -e "${RED}HIBA:${RESET} $1"
    echo ""
}

# Szolgáltatás kezelése
echo -e "${BOLD}Szolgáltatás kezelése...${RESET}"
if systemctl is-active --quiet e-paper-calendar.service; then
    echo "Szolgáltatás leállítása..."
    sudo systemctl stop e-paper-calendar.service
    success "Szolgáltatás leállítva"
else
    warning "A szolgáltatás már le van állítva vagy nem létezik"
fi

# Szolgáltatás letiltása
if systemctl is-enabled --quiet e-paper-calendar.service; then
    echo "Szolgáltatás letiltása..."
    sudo systemctl disable e-paper-calendar.service
    success "Szolgáltatás letiltva"
else
    warning "A szolgáltatás már le van tiltva vagy nem létezik"
fi

# Szolgáltatás definíció eltávolítása
if [ -f /etc/systemd/system/e-paper-calendar.service ]; then
    echo "Szolgáltatás definíció eltávolítása..."
    sudo rm -f /etc/systemd/system/e-paper-calendar.service
    sudo systemctl daemon-reload
    success "Szolgáltatás definíció eltávolítva"
else
    warning "Szolgáltatás definíciós fájl nem található"
fi

# Rendszer tisztítása
echo -e "${YELLOW}Kérdés: Szeretné eltávolítani az alkalmazás fájlokat és a telepített függőségeket is? (i/n)${RESET}"
read -r answer

if [ "$answer" = "i" ] || [ "$answer" = "I" ]; then
    # Alkalmazás fájlok törlése
    echo -e "${BOLD}Alkalmazás fájlok törlése...${RESET}"
    if [ -d "$APP_DIR" ]; then
        if sudo rm -rf "$APP_DIR"; then
            success "Alkalmazás fájlok törölve"
        else
            error "Nem sikerült törölni az alkalmazás fájlokat"
        fi
    else
        warning "Az alkalmazás könyvtár nem található: $APP_DIR"
    fi
    
    # Python csomagok eltávolítása
    echo -e "${YELLOW}Szeretné eltávolítani az összes telepített Python csomagot? (i/n)${RESET}"
    read -r remove_pip
    
    if [ "$remove_pip" = "i" ] || [ "$remove_pip" = "I" ]; then
        echo -e "${BOLD}Python csomagok eltávolítása...${RESET}"
        PIP_PACKAGES="RPi.GPIO spidev pytz requests ephem feedparser holidays python-dateutil pillow gpiozero"
        
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
            echo -e "${YELLOW}A rendszerszintű Python csomagok eltávolítása befolyásolhatja más alkalmazásokat.${RESET}"
            echo -e "${YELLOW}Biztosan el szeretné távolítani a rendszerszintű Python csomagokat? (i/n)${RESET}"
            read -r confirm_pip_removal
            
            if [ "$confirm_pip_removal" = "i" ] || [ "$confirm_pip_removal" = "I" ]; then
                for pkg in $PIP_PACKAGES; do
                    echo "Eltávolítás: $pkg"
                    sudo pip3 uninstall -y $pkg
                done
                success "Rendszerszintű Python csomagok eltávolítva"
            else
                echo "Rendszerszintű Python csomagok megtartva"
            fi
        fi
    fi
    
    # Waveshare könyvtár eltávolítása
    echo -e "${YELLOW}Szeretné eltávolítani a letöltött Waveshare e-Paper könyvtárat is? (i/n)${RESET}"
    read -r remove_waveshare
    
    if [ "$remove_waveshare" = "i" ] || [ "$remove_waveshare" = "I" ]; then
        echo -e "${BOLD}Waveshare e-Paper könyvtár keresése és törlése...${RESET}"
        # Keressük meg és töröljük a letöltött Waveshare könyvtárakat
        WAVESHARE_DIRS=$(find $HOME_DIR -name "e-Paper" -type d 2>/dev/null)
        
        if [ -n "$WAVESHARE_DIRS" ]; then
            echo "Talált Waveshare könyvtárak:"
            echo "$WAVESHARE_DIRS"
            echo -e "${YELLOW}Ezek a könyvtárak törlésre kerülnek. Folytatja? (i/n)${RESET}"
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
    echo -e "${YELLOW}Szeretné eltávolítani a telepítési és alkalmazás naplófájlokat is? (i/n)${RESET}"
    read -r remove_logs
    
    if [ "$remove_logs" = "i" ] || [ "$remove_logs" = "I" ]; then
        echo -e "${BOLD}Naplófájlok eltávolítása...${RESET}"
        sudo rm -f $HOME_DIR/install_log.txt
        if [ -f "$HOME_DIR/calendar.log" ]; then
            sudo rm -f $HOME_DIR/calendar.log
        fi
        success "Naplófájlok eltávolítva"
    fi
    
    # SPI interfész állapotának visszaállítása
    echo -e "${YELLOW}Szeretné visszaállítani az SPI interfészt az eredeti állapotba (kikapcsolni)? (i/n)${RESET}"
    read -r disable_spi
    
    if [ "$disable_spi" = "i" ] || [ "$disable_spi" = "I" ]; then
        echo -e "${BOLD}SPI interfész kikapcsolása...${RESET}"
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
    
    # Felhasználói csoportok visszaállítása
    echo -e "${YELLOW}Szeretné eltávolítani a felhasználót az SPI és GPIO csoportokból? (i/n)${RESET}"
    read -r remove_groups
    
    if [ "$remove_groups" = "i" ] || [ "$remove_groups" = "I" ]; then
        echo -e "${BOLD}Felhasználó eltávolítása a speciális csoportokból...${RESET}"
        
        # Figyelmeztetés, hogy ez más alkalmazásokat is érinthet
        echo -e "${YELLOW}Figyelmeztetés: Ez hatással lehet más alkalmazásokra is, amelyek az SPI vagy GPIO interfészt használják.${RESET}"
        echo -e "${YELLOW}Folytatja? (i/n)${RESET}"
        read -r confirm_group_removal
        
        if [ "$confirm_group_removal" = "i" ] || [ "$confirm_group_removal" = "I" ]; then
            # A gpasswd -d parancs használata a csoportok eltávolításához
            for group in spi gpio; do
                if id -nG $CURRENT_USER | grep -qw "$group"; then
                    sudo gpasswd -d $CURRENT_USER $group
                    success "Felhasználó eltávolítva a $group csoportból"
                    REBOOT_NEEDED=1
                else
                    warning "A felhasználó nem tagja a $group csoportnak"
                fi
            done
        else
            echo "Csoporttagságok megtartva"
        fi
    fi
else
    echo "Alkalmazás fájlok megtartása..."
    REBOOT_NEEDED=0
fi

echo ""
echo -e "${BLUE}===========================================${RESET}"
echo -e "${GREEN}Eltávolítás befejezve!${RESET}"
echo -e "${BLUE}===========================================${RESET}"
echo -e "Az e-Paper naptár alkalmazás eltávolítása befejeződött."
echo ""

# Figyelmeztetés az újraindításról, ha beállítások változtak
if [ "$REBOOT_NEEDED" = "1" ]; then
    echo -e "${YELLOW}FIGYELEM:${RESET} Az SPI interfész vagy a csoportbeállítások változtatásainak érvényesítéséhez újra kell indítani a Raspberry Pi-t!"
    echo -e "${YELLOW}Újraindítás most? (i/n)${RESET}"
    read -r answer
    if [ "$answer" = "i" ] || [ "$answer" = "I" ]; then
        echo "A Raspberry Pi újraindul..."
        sudo reboot
    else
        echo "Kérjük, indítsa újra a Raspberry Pi-t manuálisan a későbbiekben!"
    fi
fi
