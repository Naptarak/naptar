#!/bin/bash

# e-Paper Calendar Installer Script (Kibővített diagnosztikával)
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-Paper HAT

echo "==========================================="
echo "E-Paper Calendar Display - Telepítő Script"
echo "==========================================="
echo "Waveshare 4.01\" 7-színű e-Paper HAT (F) - 640x400 pixel"
echo "Raspberry Pi Zero 2W (512MB RAM)"
echo ""

# Aktuális könyvtár mentése
SCRIPT_DIR="$(pwd)"

# Log könyvtár létrehozása
INSTALL_LOG_DIR="$SCRIPT_DIR/install_logs"
mkdir -p "$INSTALL_LOG_DIR"
MAIN_LOG="$INSTALL_LOG_DIR/install_main.log"
DIAGNOSTIC_LOG="$INSTALL_LOG_DIR/install_diagnostic.log"

# Dátum és idő a naplóban
echo "Telepítés indítása: $(date)" | tee -a "$MAIN_LOG"
echo "Diagnosztikai napló létrehozva: $(date)" > "$DIAGNOSTIC_LOG"

# Rendszerinfo mentése
echo "=== Rendszerinformációk ===" | tee -a "$DIAGNOSTIC_LOG"
uname -a >> "$DIAGNOSTIC_LOG"
cat /etc/os-release >> "$DIAGNOSTIC_LOG"
echo "Python verzió:" >> "$DIAGNOSTIC_LOG"
python3 --version >> "$DIAGNOSTIC_LOG" 2>&1
echo "" >> "$DIAGNOSTIC_LOG"

# Felhasználónév meghatározása
# Ha sudo-val fut, a SUDO_USER változó tartalmazza az eredeti felhasználót
if [ -n "$SUDO_USER" ]; then
    CURRENT_USER=$SUDO_USER
    echo "Telepítés sudo felhasználóként, eredeti felhasználó: $CURRENT_USER" | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
else
    CURRENT_USER=$(logname 2>/dev/null || whoami)
    echo "Telepítés normál felhasználóként: $CURRENT_USER" | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
fi

# Ellenőrizzük, hogy van-e root jogosultság
if [ "$(id -u)" -ne 0 ]; then
    echo "FIGYELMEZTETÉS: A telepítés nem rendszergazdai (root) jogosultsággal fut. Bizonyos lépések sikertelenek lehetnek." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    echo "Javasolt a telepítést 'sudo ./install.sh' paranccsal futtatni." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    echo "Folytatja a telepítést root jogosultság nélkül? (i/n)"
    read -r answer
    if [ "$answer" != "i" ] && [ "$answer" != "I" ]; then
        echo "Telepítés megszakítva." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
        exit 1
    fi
fi

# Telepítési könyvtár meghatározása
HOME_DIR="/home/$CURRENT_USER"
APP_DIR="$HOME_DIR/e_paper_calendar"

echo "Telepítés a következő felhasználó könyvtárába: $CURRENT_USER" | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
echo "Alkalmazás könyvtár: $APP_DIR" | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
echo ""

# Ellenőrzés, hogy létezik-e a home könyvtár
if [ ! -d "$HOME_DIR" ]; then
    echo "HIBA: A felhasználói könyvtár nem létezik: $HOME_DIR" | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    echo "Kérem, ellenőrizze a felhasználónevet és próbálja újra." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    exit 1
fi

# Megerősítés kérése
echo "Biztosan ezt a könyvtárat szeretné használni a telepítéshez? (i/n)"
read -r confirm
if [ "$confirm" != "i" ] && [ "$confirm" != "I" ]; then
    echo "Telepítés megszakítva a felhasználó kérésére." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    exit 0
fi

# Függvény a hibák kezelésére
handle_error() {
    echo -e "\e[31mHIBA:\e[0m $1" | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    echo "Próbálja meg a következőt: $2" | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    echo ""
}

# Függvény a sikeres műveletek jelzésére
success() {
    echo -e "\e[32mSIKER:\e[0m $1" | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    echo ""
}

# Függvény a figyelmeztetések jelzésére
warning() {
    echo -e "\e[33mFIGYELMEZTETÉS:\e[0m $1" | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    echo ""
}

# Függvény a diagnosztikai információk kiírására
diagnostic() {
    echo "DIAGNOSZTIKA: $1" >> "$DIAGNOSTIC_LOG"
}

# SPI interfész ellenőrzése
echo "SPI interfész ellenőrzése..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
SPI_ENABLED=$(grep -c "dtparam=spi=on" /boot/config.txt || echo "0")
if [ "$SPI_ENABLED" -eq 0 ]; then
    if [ "$(id -u)" -eq 0 ]; then
        echo "SPI interfész nincs engedélyezve. Engedélyezés..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
        echo "dtparam=spi=on" >> /boot/config.txt
        REBOOT_NEEDED=1
        success "SPI interfész engedélyezve (újraindítás szükséges)"
    else
        handle_error "SPI interfész nincs engedélyezve, de nem rendszergazdaként fut a telepítő" "Futtassa a telepítőt 'sudo ./install.sh' paranccsal"
        exit 1
    fi
else
    success "SPI interfész már engedélyezve van"
    REBOOT_NEEDED=0
fi

# SPI eszközök ellenőrzése
SPI_DEVICES=$(ls -l /dev/spi* 2>/dev/null)
if [ -z "$SPI_DEVICES" ]; then
    warning "Nem találhatók SPI eszközök. Lehet, hogy újra kell indítani a rendszert az SPI engedélyezéséhez."
else
    success "SPI eszközök megtalálva: $SPI_DEVICES"
fi
echo "SPI eszközök: $SPI_DEVICES" >> "$DIAGNOSTIC_LOG"

# GPIO csoport ellenőrzése
echo "Felhasználói csoportok ellenőrzése..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
GROUPS=$(groups "$CURRENT_USER" 2>/dev/null)
echo "Jelenlegi csoportok: $GROUPS" >> "$DIAGNOSTIC_LOG"

if [[ ! "$GROUPS" == *"gpio"* ]] || [[ ! "$GROUPS" == *"spi"* ]]; then
    if [ "$(id -u)" -eq 0 ]; then
        echo "A felhasználó nincs a gpio és/vagy spi csoportokban. Hozzáadás..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
        usermod -a -G gpio,spi "$CURRENT_USER"
        REBOOT_NEEDED=1
        success "Felhasználó hozzáadva a gpio és spi csoportokhoz (újraindítás szükséges)"
    else
        warning "A felhasználó nincs a gpio és/vagy spi csoportokban, de nem rendszergazdaként fut a telepítő"
    fi
else
    success "A felhasználó már tagja a szükséges csoportoknak"
fi

# Rendszer frissítése
echo "Rendszer frissítése..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
if [ "$(id -u)" -eq 0 ]; then
    if ! apt-get update >> "$DIAGNOSTIC_LOG" 2>&1; then
        handle_error "A rendszer frissítése sikertelen" "Ellenőrizze az internetkapcsolatot és próbálja újra: sudo apt-get update"
        # Diagnosztika
        echo "APT problémák diagnosztikája:" >> "$DIAGNOSTIC_LOG"
        apt-get update -o Debug::pkgProblemResolver=yes >> "$DIAGNOSTIC_LOG" 2>&1
    else
        success "Rendszer frissítése sikeres"
    fi
else
    warning "Rendszer frissítése kihagyva (nem rendszergazda)"
fi

# Szükséges csomagok telepítése
echo "Szükséges csomagok telepítése..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
PACKAGES="python3 python3-pip python3-pil python3-numpy git libopenjp2-7 libatlas-base-dev python3-venv libxml2-dev libxslt1-dev"

if [ "$(id -u)" -eq 0 ]; then
    if ! apt-get install -y $PACKAGES >> "$DIAGNOSTIC_LOG" 2>&1; then
        handle_error "Nem sikerült telepíteni az összes szükséges csomagot" "Próbálja telepíteni egyesével a csomagokat, vagy ellenőrizze a $DIAGNOSTIC_LOG fájlt a részletekért"
        
        # Egyesével próbáljuk telepíteni a csomagokat
        echo "Próbálkozás a csomagok egyesével történő telepítésével..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
        for package in $PACKAGES; do
            echo "Telepítés: $package" | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
            apt-get install -y "$package" >> "$DIAGNOSTIC_LOG" 2>&1 || warning "Nem sikerült telepíteni: $package"
        done
    else
        success "Szükséges csomagok telepítése sikeres"
    fi
else
    warning "Csomagtelepítés kihagyva (nem rendszergazda)"
fi

# WiringPi alternatív telepítési kísérlet
echo "WiringPi könyvtár telepítése..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
if [ "$(id -u)" -eq 0 ]; then
    if ! apt-get install -y wiringpi >> "$DIAGNOSTIC_LOG" 2>&1; then
        warning "A WiringPi csomag nem telepíthető az alapértelmezett forrásból. Alternatív megoldás kipróbálása..."
        
        # Gordon Henderson WiringPi fork-ja
        if ! git clone https://github.com/WiringPi/WiringPi.git /tmp/WiringPi >> "$DIAGNOSTIC_LOG" 2>&1; then
            warning "A WiringPi könyvtár klónozása sikertelen. Folytatás WiringPi nélkül..."
        else
            cd /tmp/WiringPi || exit
            if ! ./build >> "$DIAGNOSTIC_LOG" 2>&1; then
                warning "A WiringPi könyvtár fordítása sikertelen. Folytatás WiringPi nélkül..."
            else
                success "WiringPi könyvtár telepítése sikeres az alternatív forrásból"
            fi
            cd "$SCRIPT_DIR" || exit
        fi
    else
        success "WiringPi könyvtár telepítése sikeres"
    fi
else
    warning "WiringPi telepítés kihagyva (nem rendszergazda)"
fi

# RPi.GPIO csomag ellenőrzése
echo "RPi.GPIO csomag ellenőrzése..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
if ! python3 -c "import RPi.GPIO" >> "$DIAGNOSTIC_LOG" 2>&1; then
    echo "RPi.GPIO nincs telepítve. Telepítés..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    if [ "$(id -u)" -eq 0 ]; then
        pip3 install RPi.GPIO >> "$DIAGNOSTIC_LOG" 2>&1 || warning "Nem sikerült telepíteni az RPi.GPIO csomagot"
    else
        warning "RPi.GPIO telepítés kihagyva (nem rendszergazda)"
    fi
else
    success "RPi.GPIO már telepítve van"
fi

# Létrehozunk egy mappát a projektnek
echo "Alkalmazás könyvtár létrehozása: $APP_DIR" | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
if [ -d "$APP_DIR" ]; then
    warning "Az alkalmazás könyvtár már létezik. Törlés..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    if ! rm -rf "${APP_DIR:?}"/* >> "$DIAGNOSTIC_LOG" 2>&1; then
        handle_error "Nem sikerült törölni a meglévő könyvtár tartalmát" "Ellenőrizze a jogosultságokat"
    else
        success "Meglévő könyvtár tartalma törölve"
    fi
else
    if ! mkdir -p "$APP_DIR" >> "$DIAGNOSTIC_LOG" 2>&1; then
        handle_error "Nem sikerült létrehozni az alkalmazás könyvtárat" "Ellenőrizze a jogosultságokat"
        exit 1
    else
        success "Alkalmazás könyvtár létrehozva"
    fi
fi

# Jogosultságok beállítása
echo "Könyvtárjogosultságok beállítása..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
if [ "$(id -u)" -eq 0 ]; then
    chown -R "$CURRENT_USER":"$CURRENT_USER" "$APP_DIR"
    success "Könyvtárjogosultságok beállítva"
else
    warning "Könyvtárjogosultságok beállítása kihagyva (nem rendszergazda)"
fi

# Virtuális környezet létrehozása
echo "Python virtuális környezet létrehozása..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
if ! su - "$CURRENT_USER" -c "cd \"$APP_DIR\" && python3 -m venv venv" >> "$DIAGNOSTIC_LOG" 2>&1; then
    handle_error "A virtuális környezet létrehozása sikertelen" "Telepítse újra a python3-venv csomagot: sudo apt-get install python3-venv"
    
    # Alternatív megoldás: használjuk a virtuális környezet nélküli telepítést
    echo "Alternatív telepítés virtuális környezet nélkül..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    USE_VENV=0
else
    success "Virtuális környezet létrehozása sikeres"
    USE_VENV=1
fi

# Python csomagok telepítése
echo "Python függőségek telepítése..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"

# Szükséges Python csomagok listája
PIP_PACKAGES="RPi.GPIO spidev pytz requests ephem feedparser holidays python-dateutil pillow"

if [ $USE_VENV -eq 1 ]; then
    echo "Virtuális környezet használata a Python csomagok telepítéséhez..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    if ! su - "$CURRENT_USER" -c "cd \"$APP_DIR\" && source venv/bin/activate && pip3 install $PIP_PACKAGES" >> "$DIAGNOSTIC_LOG" 2>&1; then
        handle_error "Python csomagok telepítése sikertelen a virtuális környezetben" "Próbálja telepíteni a csomagokat egyesével, vagy ellenőrizze a $DIAGNOSTIC_LOG fájlt a részletekért"
        
        # Egyesével próbáljuk telepíteni a csomagokat
        echo "Próbálkozás a csomagok egyesével történő telepítésével..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
        for package in $PIP_PACKAGES; do
            echo "Telepítés: $package" | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
            su - "$CURRENT_USER" -c "cd \"$APP_DIR\" && source venv/bin/activate && pip3 install $package" >> "$DIAGNOSTIC_LOG" 2>&1 || warning "Nem sikerült telepíteni: $package"
        done
    else
        success "Python függőségek telepítése sikeres a virtuális környezetben"
    fi
else
    echo "Rendszerszintű telepítés a Python csomagokhoz..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    if [ "$(id -u)" -eq 0 ]; then
        if ! pip3 install $PIP_PACKAGES >> "$DIAGNOSTIC_LOG" 2>&1; then
            handle_error "Python csomagok telepítése sikertelen" "Próbálja telepíteni a csomagokat egyesével, vagy ellenőrizze a $DIAGNOSTIC_LOG fájlt a részletekért"
            
            # Egyesével próbáljuk telepíteni a csomagokat
            echo "Próbálkozás a csomagok egyesével történő telepítésével..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
            for package in $PIP_PACKAGES; do
                echo "Telepítés: $package" | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
                pip3 install "$package" >> "$DIAGNOSTIC_LOG" 2>&1 || warning "Nem sikerült telepíteni: $package"
            done
        else
            success "Python függőségek telepítése sikeres"
        fi
    else
        warning "Python függőségek telepítése kihagyva (nem rendszergazda)"
    fi
fi

# Waveshare e-Paper könyvtár telepítése
echo "Waveshare e-Paper könyvtár telepítése..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"

# Először próbáljuk a hivatalos GitHub repóból
if ! su - "$CURRENT_USER" -c "cd \"$APP_DIR\" && git clone https://github.com/waveshare/e-Paper.git" >> "$DIAGNOSTIC_LOG" 2>&1; then
    handle_error "A Waveshare e-Paper könyvtár klónozása sikertelen" "Ellenőrizze az internetkapcsolatot vagy próbálja meg letölteni a forrást közvetlenül a Waveshare oldaláról"
    
    # Alternatív útvonal: letöltés a Waveshare oldaláról
    echo "Alternatív telepítés próbálása a Waveshare oldaláról..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    if ! su - "$CURRENT_USER" -c "cd \"$APP_DIR\" && wget -O e-Paper.zip https://www.waveshare.com/w/upload/1/18/E-Paper_code.zip" >> "$DIAGNOSTIC_LOG" 2>&1; then
        handle_error "A Waveshare e-Paper könyvtár letöltése alternatív úton is sikertelen" "Ellenőrizze a webhely elérhetőségét vagy töltse le manuálisan"
    else
        su - "$CURRENT_USER" -c "cd \"$APP_DIR\" && unzip e-Paper.zip -d e-Paper" >> "$DIAGNOSTIC_LOG" 2>&1
        su - "$CURRENT_USER" -c "cd \"$APP_DIR\" && rm e-Paper.zip" >> "$DIAGNOSTIC_LOG" 2>&1
        success "Waveshare e-Paper könyvtár letöltése sikeres az alternatív úton"
    fi
else
    success "Waveshare e-Paper könyvtár klónozása sikeres"
fi

# Telepítsük a Waveshare Python példákat
if [ -d "$APP_DIR/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd" ]; then
    echo "Waveshare e-Paper Python könyvtár másolása..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    su - "$CURRENT_USER" -c "mkdir -p \"$APP_DIR/lib\"" >> "$DIAGNOSTIC_LOG" 2>&1
    su - "$CURRENT_USER" -c "cp -r \"$APP_DIR/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd\" \"$APP_DIR/lib/\"" >> "$DIAGNOSTIC_LOG" 2>&1
    success "Waveshare e-Paper Python könyvtár telepítése sikeres"
else
    handle_error "Nem található a Waveshare e-Paper Python könyvtár" "Ellenőrizze a letöltött e-Paper könyvtár struktúráját, a mappák elnevezése változhatott"
    
    # Keressük meg a könyvtárat az e-Paper mappában
    echo "A waveshare_epd könyvtár keresése..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
    FOUND_DIR=$(su - "$CURRENT_USER" -c "find \"$APP_DIR/e-Paper\" -name \"waveshare_epd\" -type d" | head -n 1)
    
    if [ -n "$FOUND_DIR" ]; then
        echo "waveshare_epd könyvtár megtalálva: $FOUND_DIR" | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
        su - "$CURRENT_USER" -c "mkdir -p \"$APP_DIR/lib\"" >> "$DIAGNOSTIC_LOG" 2>&1
        su - "$CURRENT_USER" -c "cp -r \"$FOUND_DIR\" \"$APP_DIR/lib/\"" >> "$DIAGNOSTIC_LOG" 2>&1
        success "Waveshare e-Paper Python könyvtár telepítése sikeres alternatív helyről"
    else
        handle_error "A waveshare_epd könyvtár nem található a letöltött archívumban" "Töltse le manuálisan a könyvtárat, vagy ellenőrizze a megfelelő API elérhetőségét"
    fi
fi

# Waveshare példaprogram tesztelése
echo "Waveshare példaprogram tesztelése..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"

# Teszt script létrehozása
cat > "$APP_DIR/epaper_test.py" << 'EOF'
#!/usr/bin/env python3
import os
import sys
import time
import logging
import traceback

# Részletes naplózás beállítása
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("epaper_test.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger()

# Elérési út beállítása
lib_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'lib')
if os.path.exists(lib_dir):
    sys.path.append(lib_dir)
    logger.debug(f"Lib könyvtár hozzáadva: {lib_dir}")
else:
    logger.error(f"A lib könyvtár nem található: {lib_dir}")
    sys.exit(1)

try:
    logger.debug("SPI eszközök ellenőrzése:")
    os.system("ls -l /dev/spi* >> epaper_test.log 2>&1")
    
    logger.debug("Python elérési utak:")
    logger.debug(str(sys.path))
    
    logger.debug("Lib könyvtár tartalma:")
    os.system(f"ls -la {lib_dir} >> epaper_test.log 2>&1")
    
    if os.path.exists(os.path.join(lib_dir, 'waveshare_epd')):
        logger.debug("waveshare_epd könyvtár tartalma:")
        os.system(f"ls -la {lib_dir}/waveshare_epd >> epaper_test.log 2>&1")
    
    logger.debug("Waveshare modul importálása...")
    from waveshare_epd import epd4in01f
    logger.debug("Waveshare modul sikeresen importálva")
    
    logger.debug("E-Paper objektum létrehozása...")
    epd = epd4in01f.EPD()
    logger.debug("E-Paper objektum létrehozva")
    
    logger.debug("Inicializálás...")
    epd.init()
    logger.debug("Inicializálás sikeres!")
    
    logger.debug("Kijelző törlése...")
    epd.Clear(0xFF)  # Fehér
    logger.debug("Kijelző törölve")
    
    logger.debug("Alvó állapot...")
    epd.sleep()
    logger.debug("Teszt sikeresen befejezve")
    
except Exception as e:
    logger.error(f"Hiba: {e}")
    logger.error(traceback.format_exc())

logger.debug("Teszt futás befejezve")
EOF

# Jogosultság beállítása a tesztprogramhoz
chmod +x "$APP_DIR/epaper_test.py"
chown "$CURRENT_USER":"$CURRENT_USER" "$APP_DIR/epaper_test.py"

# Futtatási próba a tesztprogrammal
echo "Tesztprogram futtatása..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
if ! timeout 30 python3 "$APP_DIR/epaper_test.py" >> "$DIAGNOSTIC_LOG" 2>&1; then
    warning "A tesztprogram futtatása sikertelen vagy időtúllépés történt. A naplófájlok segíthetnek a hiba azonosításában."
else
    success "Tesztprogram sikeresen lefutott"
fi

# Diagnosztikai információk mentése
echo "Diagnosztikai információk gyűjtése..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"
if [ -f "$APP_DIR/epaper_test.log" ]; then
    echo "=== E-Paper teszt napló ===" >> "$DIAGNOSTIC_LOG"
    cat "$APP_DIR/epaper_test.log" >> "$DIAGNOSTIC_LOG"
else
    warning "E-Paper teszt napló nem jött létre"
fi

# Naptár alkalmazás létrehozása
echo "Naptár alkalmazás létrehozása..." | tee -a "$MAIN_LOG" "$DIAGNOSTIC_LOG"

# Alkalmazás forráskód
cat > "$APP_DIR/calendar_display.py" << 'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import time
import datetime
import pytz
import requests
import ephem
import feedparser
import holidays
from dateutil import rrule
from PIL import Image, ImageDraw, ImageFont
import traceback
import logging

# Naplózás beállítása - Részletes DEBUG szintű naplózás
logging.basicConfig(
    level=logging.DEBUG,  # Részletesebb naplózás
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("calendar.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("CalendarDisplay")

# Rendszerinformációk kiírása
logger.info("Program indítása...")
logger.debug(f"Python verzió: {sys.version}")
logger.debug(f"Aktuális könyvtár: {os.getcwd()}")
logger.debug(f"Python elérési utak: {sys.path}")

# SPI eszközök ellenőrzése
logger.debug("SPI eszközök ellenőrzése:")
os.system("ls -l /dev/spi* >> calendar_spi.log 2>&1")

# Elérési út beállítása a waveshare modulokhoz
current_dir = os.path.dirname(os.path.abspath(__file__))
lib_dir = os.path.join(current_dir, 'lib')
if os.path.exists(lib_dir):
    sys.path.append(lib_dir)
    logger.debug(f"Lib könyvtár hozzáadva: {lib_dir}")
    
    # Könyvtár tartalom listázása
    logger.debug("Lib könyvtár tartalma:")
    os.system(f"ls -la {lib_dir} >> calendar.log 2>&1")
    
    if os.path.exists(os.path.join(lib_dir, 'waveshare_epd')):
        logger.debug("waveshare_epd könyvtár tartalma:")
        os.system(f"ls -la {lib_dir}/waveshare_epd >> calendar.log 2>&1")
else:
    logger.error(f"A lib mappa nem található: {lib_dir}")
    sys.exit(1)

try:
    logger.debug("Waveshare e-Paper modul importálása...")
    from waveshare_epd import epd4in01f
    logger.debug("Waveshare e-Paper modul sikeresen importálva")
except ImportError as e:
    logger.error("Nem sikerült importálni a waveshare_epd modult")
    logger.error(f"ImportError: {e}")
    logger.error(f"Traceback: {traceback.format_exc()}")
    sys.exit(1)

# Konstansok
WIDTH = 640
HEIGHT = 400
TIMEZONE = pytz.timezone('Europe/Budapest')
RSS_URL = "https://telex.hu/rss"
UPDATE_INTERVAL = 600  # 10 perc másodpercben
MAX_RSS_ITEMS = 3

# Színdefiníciók a 7-színű epd kijelzőhöz
WHITE = 0
BLACK = 1
GREEN = 2
BLUE = 3
RED = 4
YELLOW = 5
ORANGE = 6

# Betűtípus elérési utak
try:
    # Betűtípusok definiálása különböző méretekben
    logger.debug("Betűtípusok betöltése...")
    font18 = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 18)
    font24 = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 24)
    font36 = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 36)
    font48 = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 48)
    logger.debug("Betűtípusok betöltése sikeres")
except OSError as e:
    logger.warning(f"Nem sikerült betölteni a DejaVu betűtípust: {e}")
    logger.warning("Alapértelmezett betűtípus használata")
    font18 = ImageFont.load_default()
    font24 = ImageFont.load_default()
    font36 = ImageFont.load_default()
    font48 = ImageFont.load_default()

# Névnapok szótára
NAMEDAYS = {
    "01-01": ["Fruzsina"],
    "01-02": ["Ábel", "Gergely"],
    "01-03": ["Genovéva", "Benjámin"],
    "01-04": ["Titusz", "Leona"],
    "01-05": ["Simon"],
    "01-06": ["Boldizsár"],
    "01-07": ["Attila", "Ramóna"],
    "01-08": ["Gyöngyvér"],
    "01-09": ["Marcell"],
    "01-10": ["Melánia"],
    "01-11": ["Ágota"],
    "01-12": ["Ernő"],
    "01-13": ["Veronika"],
    "01-14": ["Bódog"],
    "01-15": ["Lóránt", "Loránd"],
    "01-16": ["Gusztáv"],
    "01-17": ["Antal", "Antónia"],
    "01-18": ["Piroska"],
    "01-19": ["Sára", "Márió"],
    "01-20": ["Fábián", "Sebestyén"],
    "01-21": ["Ágnes"],
    "01-22": ["Vince", "Artúr"],
    "01-23": ["Zelma", "Rajmund"],
    "01-24": ["Timót"],
    "01-25": ["Pál"],
    "01-26": ["Vanda", "Paula"],
    "01-27": ["Angelika"],
    "01-28": ["Károly", "Karola"],
    "01-29": ["Adél"],
    "01-30": ["Martina", "Gerda"],
    "01-31": ["Marcella"],
    "02-01": ["Ignác"],
    "02-02": ["Karolina", "Aida"],
    "02-03": ["Balázs"],
    "02-04": ["Ráhel", "Csenge"],
    "02-05": ["Ágota", "Ingrid"],
    "02-06": ["Dóra", "Dorottya"],
    "02-07": ["Tódor", "Rómeó"],
    "02-08": ["Aranka"],
    "02-09": ["Abigél", "Alex"],
    "02-10": ["Elvira"],
    "02-11": ["Bertold", "Marietta"],
    "02-12": ["Lívia", "Lídia"],
    "02-13": ["Ella", "Linda"],
    "02-14": ["Bálint", "Valentin"],
    "02-15": ["Kolos", "Georgina"],
    "02-16": ["Julianna", "Lilla"],
    "02-17": ["Donát"],
    "02-18": ["Bernadett"],
    "02-19": ["Zsuzsanna"],
    "02-20": ["Aladár", "Álmos"],
    "02-21": ["Eleonóra"],
    "02-22": ["Gerzson"],
    "02-23": ["Alfréd"],
    "02-24": ["Mátyás"],
    "02-25": ["Géza"],
    "02-26": ["Edina"],
    "02-27": ["Ákos", "Bátor"],
    "02-28": ["Elemér"],
    "02-29": ["Antónia"],
    "03-01": ["Albin"],
    "03-02": ["Lujza"],
    "03-03": ["Kornélia"],
    "03-04": ["Kázmér"],
    "03-05": ["Adorján", "Adrián"],
    "03-06": ["Leonóra", "Inez"],
    "03-07": ["Tamás"],
    "03-08": ["Zoltán"],
    "03-09": ["Franciska", "Fanni"],
    "03-10": ["Ildikó"],
    "03-11": ["Szilárd"],
    "03-12": ["Gergely"],
    "03-13": ["Krisztián", "Ajtony"],
    "03-14": ["Matild"],
    "03-15": ["Kristóf"],
    "03-16": ["Henrietta"],
    "03-17": ["Gertrúd", "Patrik"],
    "03-18": ["Sándor", "Ede"],
    "03-19": ["József", "Bánk"],
    "03-20": ["Klaudia"],
    "03-21": ["Benedek"],
    "03-22": ["Beáta", "Izolda"],
    "03-23": ["Emőke"],
    "03-24": ["Gábor", "Karina"],
    "03-25": ["Irén", "Írisz"],
    "03-26": ["Emánuel"],
    "03-27": ["Hajnalka"],
    "03-28": ["Gedeon", "Johanna"],
    "03-29": ["Auguszta"],
    "03-30": ["Zalán"],
    "03-31": ["Árpád"],
    "04-01": ["Hugó"],
    "04-02": ["Áron"],
    "04-03": ["Buda", "Richárd"],
    "04-04": ["Izidor"],
    "04-05": ["Vince"],
    "04-06": ["Vilmos", "Bíborka"],
    "04-07": ["Herman"],
    "04-08": ["Dénes"],
    "04-09": ["Erhard"],
    "04-10": ["Zsolt"],
    "04-11": ["Leó", "Szaniszló"],
    "04-12": ["Gyula"],
    "04-13": ["Ida"],
    "04-14": ["Tibor"],
    "04-15": ["Anasztázia", "Tas"],
    "04-16": ["Csongor"],
    "04-17": ["Rudolf"],
    "04-18": ["Andrea", "Ilma"],
    "04-19": ["Emma"],
    "04-20": ["Tivadar"],
    "04-21": ["Konrád"],
    "04-22": ["Csilla", "Noémi"],
    "04-23": ["Béla"],
    "04-24": ["György"],
    "04-25": ["Márk"],
    "04-26": ["Ervin"],
    "04-27": ["Zita"],
    "04-28": ["Valéria"],
    "04-29": ["Péter"],
    "04-30": ["Katalin", "Kitti"],
    "05-01": ["Fülöp", "Jakab"],
    "05-02": ["Zsigmond"],
    "05-03": ["Tímea", "Irma"],
    "05-04": ["Mónika", "Flórián"],
    "05-05": ["Györgyi"],
    "05-06": ["Ivett", "Frida"],
    "05-07": ["Gizella"],
    "05-08": ["Mihály"],
    "05-09": ["Gergely"],
    "05-10": ["Ármin", "Pálma"],
    "05-11": ["Ferenc"],
    "05-12": ["Pongrác"],
    "05-13": ["Szervác", "Imola"],
    "05-14": ["Bonifác"],
    "05-15": ["Zsófia", "Szonja"],
    "05-16": ["Mózes", "Botond"],
    "05-17": ["Paszkál"],
    "05-18": ["Erik", "Alexandra"],
    "05-19": ["Ivó", "Milán"],
    "05-20": ["Bernát", "Felícia"],
    "05-21": ["Konstantin"],
    "05-22": ["Júlia", "Rita"],
    "05-23": ["Dezső"],
    "05-24": ["Eszter", "Eliza"],
    "05-25": ["Orbán"],
    "05-26": ["Fülöp", "Evelin"],
    "05-27": ["Hella"],
    "05-28": ["Emil", "Csanád"],
    "05-29": ["Magdolna"],
    "05-30": ["Janka", "Zsanett"],
    "05-31": ["Angéla", "Petronella"],
    "06-01": ["Tünde"],
    "06-02": ["Kármen", "Anita"],
    "06-03": ["Klotild"],
    "06-04": ["Bulcsú"],
    "06-05": ["Fatime"],
    "06-06": ["Norbert", "Cintia"],
    "06-07": ["Róbert"],
    "06-08": ["Medárd"],
    "06-09": ["Félix"],
    "06-10": ["Margit", "Gréta"],
    "06-11": ["Barnabás"],
    "06-12": ["Villő"],
    "06-13": ["Antal", "Anett"],
    "06-14": ["Vazul"],
    "06-15": ["Jolán", "Vid"],
    "06-16": ["Jusztin"],
    "06-17": ["Laura", "Alida"],
    "06-18": ["Arnold", "Levente"],
    "06-19": ["Gyárfás"],
    "06-20": ["Rafael"],
    "06-21": ["Alajos", "Leila"],
    "06-22": ["Paulina"],
    "06-23": ["Zoltán"],
    "06-24": ["Iván"],
    "06-25": ["Vilmos"],
    "06-26": ["János", "Pál"],
    "06-27": ["László"],
    "06-28": ["Levente", "Irén"],
    "06-29": ["Péter", "Pál"],
    "06-30": ["Pál"],
    "07-01": ["Tihamér", "Annamária"],
    "07-02": ["Ottó"],
    "07-03": ["Kornél", "Soma"],
    "07-04": ["Ulrik"],
    "07-05": ["Emese", "Sarolta"],
    "07-06": ["Csaba"],
    "07-07": ["Apollónia"],
    "07-08": ["Ellák"],
    "07-09": ["Lukrécia"],
    "07-10": ["Amália"],
    "07-11": ["Nóra", "Lili"],
    "07-12": ["Izabella", "Dalma"],
    "07-13": ["Jenő"],
    "07-14": ["Örs", "Stella"],
    "07-15": ["Henrik", "Roland"],
    "07-16": ["Valter"],
    "07-17": ["Endre", "Elek"],
    "07-18": ["Frigyes"],
    "07-19": ["Emília"],
    "07-20": ["Illés"],
    "07-21": ["Dániel", "Daniella"],
    "07-22": ["Magdolna"],
    "07-23": ["Lenke"],
    "07-24": ["Kinga", "Kincső"],
    "07-25": ["Kristóf", "Jakab"],
    "07-26": ["Anna", "Anikó"],
    "07-27": ["Olga", "Liliána"],
    "07-28": ["Szabolcs"],
    "07-29": ["Márta", "Flóra"],
    "07-30": ["Judit", "Xénia"],
    "07-31": ["Oszkár"],
    "08-01": ["Boglárka"],
    "08-02": ["Lehel"],
    "08-03": ["Hermina"],
    "08-04": ["Domonkos", "Dominika"],
    "08-05": ["Krisztina"],
    "08-06": ["Berta", "Bettina"],
    "08-07": ["Ibolya"],
    "08-08": ["László"],
    "08-09": ["Emőd"],
    "08-10": ["Lőrinc"],
    "08-11": ["Zsuzsanna", "Tiborc"],
    "08-12": ["Klára"],
    "08-13": ["Ipoly"],
    "08-14": ["Marcell"],
    "08-15": ["Mária"],
    "08-16": ["Ábrahám"],
    "08-17": ["Jácint"],
    "08-18": ["Ilona"],
    "08-19": ["Huba"],
    "08-20": ["István"],
    "08-21": ["Sámuel", "Hajna"],
    "08-22": ["Menyhért", "Mirjam"],
    "08-23": ["Bence"],
    "08-24": ["Bertalan"],
    "08-25": ["Lajos", "Patrícia"],
    "08-26": ["Izsó"],
    "08-27": ["Gáspár"],
    "08-28": ["Ágoston"],
    "08-29": ["Beatrix", "Erna"],
    "08-30": ["Rózsa"],
    "08-31": ["Erika", "Bella"],
    "09-01": ["Egyed", "Egon"],
    "09-02": ["Rebeka", "Dorina"],
    "09-03": ["Hilda"],
    "09-04": ["Rozália"],
    "09-05": ["Viktor", "Lőrinc"],
    "09-06": ["Zakariás"],
    "09-07": ["Regina"],
    "09-08": ["Mária", "Adrienn"],
    "09-09": ["Ádám"],
    "09-10": ["Nikolett", "Hunor"],
    "09-11": ["Teodóra"],
    "09-12": ["Mária"],
    "09-13": ["Kornél"],
    "09-14": ["Szeréna", "Roxána"],
    "09-15": ["Enikő", "Melitta"],
    "09-16": ["Edit"],
    "09-17": ["Zsófia"],
    "09-18": ["Diána"],
    "09-19": ["Vilhelmina"],
    "09-20": ["Friderika"],
    "09-21": ["Máté", "Mirella"],
    "09-22": ["Móric"],
    "09-23": ["Tekla"],
    "09-24": ["Gellért", "Mercédesz"],
    "09-25": ["Eufrozina", "Kende"],
    "09-26": ["Jusztina", "Pál"],
    "09-27": ["Adalbert"],
    "09-28": ["Vencel"],
    "09-29": ["Mihály"],
    "09-30": ["Jeromos"],
    "10-01": ["Malvin"],
    "10-02": ["Petra"],
    "10-03": ["Helga"],
    "10-04": ["Ferenc"],
    "10-05": ["Aurél"],
    "10-06": ["Brúnó", "Renáta"],
    "10-07": ["Amália"],
    "10-08": ["Koppány"],
    "10-09": ["Dénes"],
    "10-10": ["Gedeon"],
    "10-11": ["Brigitta"],
    "10-12": ["Miksa"],
    "10-13": ["Kálmán", "Ede"],
    "10-14": ["Helén"],
    "10-15": ["Teréz"],
    "10-16": ["Gál"],
    "10-17": ["Hedvig"],
    "10-18": ["Lukács"],
    "10-19": ["Nándor"],
    "10-20": ["Vendel"],
    "10-21": ["Orsolya"],
    "10-22": ["Előd"],
    "10-23": ["Gyöngyi"],
    "10-24": ["Salamon"],
    "10-25": ["Blanka", "Bianka"],
    "10-26": ["Dömötör"],
    "10-27": ["Szabina"],
    "10-28": ["Simon", "Szimonetta"],
    "10-29": ["Nárcisz"],
    "10-30": ["Alfonz"],
    "10-31": ["Farkas"],
    "11-01": ["Marianna"],
    "11-02": ["Achilles"],
    "11-03": ["Győző"],
    "11-04": ["Károly"],
    "11-05": ["Imre"],
    "11-06": ["Lénárd"],
    "11-07": ["Rezső"],
    "11-08": ["Zsombor"],
    "11-09": ["Tivadar"],
    "11-10": ["Réka"],
    "11-11": ["Márton"],
    "11-12": ["Jónás", "Renátó"],
    "11-13": ["Szilvia"],
    "11-14": ["Aliz"],
    "11-15": ["Albert", "Lipót"],
    "11-16": ["Ödön"],
    "11-17": ["Hortenzia", "Gergő"],
    "11-18": ["Jenő"],
    "11-19": ["Erzsébet"],
    "11-20": ["Jolán"],
    "11-21": ["Olivér"],
    "11-22": ["Cecília"],
    "11-23": ["Kelemen", "Klementina"],
    "11-24": ["Emma"],
    "11-25": ["Katalin"],
    "11-26": ["Virág"],
    "11-27": ["Virgil"],
    "11-28": ["Stefánia"],
    "11-29": ["Taksony"],
    "11-30": ["András", "Andor"],
    "12-01": ["Elza"],
    "12-02": ["Melinda", "Vivien"],
    "12-03": ["Ferenc", "Olívia"],
    "12-04": ["Borbála", "Barbara"],
    "12-05": ["Vilma"],
    "12-06": ["Miklós"],
    "12-07": ["Ambrus"],
    "12-08": ["Mária"],
    "12-09": ["Natália"],
    "12-10": ["Judit"],
    "12-11": ["Árpád"],
    "12-12": ["Gabriella"],
    "12-13": ["Luca", "Otília"],
    "12-14": ["Szilárda"],
    "12-15": ["Valér"],
    "12-16": ["Etelka", "Aletta"],
    "12-17": ["Lázár", "Olimpia"],
    "12-18": ["Auguszta"],
    "12-19": ["Viola"],
    "12-20": ["Teofil"],
    "12-21": ["Tamás"],
    "12-22": ["Zénó"],
    "12-23": ["Viktória"],
    "12-24": ["Ádám", "Éva"],
    "12-25": ["Eugénia"],
    "12-26": ["István"],
    "12-27": ["János"],
    "12-28": ["Kamilla"],
    "12-29": ["Tamás", "Tamara"],
    "12-30": ["Dávid"],
    "12-31": ["Szilveszter"]
}

# Meteorrajok
METEOR_SHOWERS = {
    "01-01": {"név": "Quadrantid", "csúcs": "Január 3-4.", "ZHR": 120},
    "04-16": {"név": "Lyrid", "csúcs": "Április 22.", "ZHR": 18},
    "05-01": {"név": "Eta Aquariid", "csúcs": "Május 5-6.", "ZHR": 50},
    "07-17": {"név": "Delta Aquariid", "csúcs": "Július 30.", "ZHR": 20},
    "08-10": {"név": "Perseid", "csúcs": "Augusztus 12-13.", "ZHR": 100},
    "10-02": {"név": "Draconid", "csúcs": "Október 8-9.", "ZHR": 10},
    "10-15": {"név": "Orionid", "csúcs": "Október 21-22.", "ZHR": 20},
    "11-04": {"név": "Taurid", "csúcs": "November 12.", "ZHR": 10},
    "11-14": {"név": "Leonid", "csúcs": "November 17-18.", "ZHR": 15},
    "12-07": {"név": "Geminid", "csúcs": "December 13-14.", "ZHR": 120},
    "12-17": {"név": "Ursid", "csúcs": "December 22-23.", "ZHR": 10}
}

# Jeles napok és hagyományok
NOTABLE_DAYS = {
    "01-01": "Újév - Az új év kezdete",
    "01-06": "Vízkereszt - A karácsonyi ünnepkör vége, a farsangi időszak kezdete",
    "01-22": "A magyar kultúra napja - A Himnusz születésnapja",
    "02-02": "Gyertyaszentelő Boldogasszony - Ha ezen a napon jó idő van, akkor hosszú lesz még a tél",
    "02-14": "Bálint nap (Valentin-nap) - A szerelmesek ünnepe",
    "03-08": "Nemzetközi nőnap",
    "03-15": "Az 1848-as forradalom ünnepe - Nemzeti ünnep",
    "03-21": "Tavaszi napéjegyenlőség - A csillagászati tavasz kezdete",
    "04-01": "Bolondok napja",
    "05-01": "A munka ünnepe",
    "05-31": "Dohányzásmentes világnap",
    "06-05": "Környezetvédelmi világnap",
    "06-21": "Nyári napforduló - A csillagászati nyár kezdete",
    "07-01": "Semmelweis-nap - A magyar egészségügy napja",
    "08-20": "Szent István ünnepe - Az államalapítás ünnepe",
    "09-22": "Őszi napéjegyenlőség - A csillagászati ősz kezdete",
    "10-01": "Zene világnapja",
    "10-06": "Az aradi vértanúk emléknapja",
    "10-23": "Az 1956-os forradalom ünnepe - Nemzeti ünnep",
    "10-31": "Halloween - Mindenszentek előestéje",
    "11-01": "Mindenszentek",
    "11-02": "Halottak napja",
    "11-03": "A magyar tudomány napja",
    "11-27": "Advent első vasárnapja (változó dátum)",
    "12-06": "Mikulás",
    "12-21": "Téli napforduló - A csillagászati tél kezdete",
    "12-24": "Szenteste",
    "12-25": "Karácsony",
    "12-26": "Karácsony másnapja",
    "12-31": "Szilveszter - Az óév búcsúztatása"
}

def get_active_meteor_shower():
    """Aktuális meteorraj ellenőrzése"""
    now = datetime.datetime.now(TIMEZONE)
    today = now.strftime("%m-%d")
    
    # Pontos dátumegyezés
    if today in METEOR_SHOWERS:
        logger.debug(f"Pontos egyezés a mai dátumra: {today}, meteorraj: {METEOR_SHOWERS[today]['név']}")
        return METEOR_SHOWERS[today]
    
    # Aktív meteorrajok (+/- 5 napon belül)
    for date, shower in METEOR_SHOWERS.items():
        month, day = map(int, date.split('-'))
        try:
            shower_date = datetime.datetime(now.year, month, day, tzinfo=TIMEZONE)
            delta = abs((now - shower_date).days)
            if delta <= 5:
                logger.debug(f"Közelgő meteorraj: {shower['név']}, {delta} nap múlva/előtt")
                return shower
        except ValueError as e:
            logger.error(f"Dátum hiba a meteorraj ellenőrzésénél: {e}")
    
    logger.debug("Nincs aktív meteorraj")
    return None

def get_nameday():
    """Az aktuális névnap lekérdezése"""
    now = datetime.datetime.now(TIMEZONE)
    date_key = now.strftime("%m-%d")
    
    if date_key in NAMEDAYS:
        names = ", ".join(NAMEDAYS[date_key])
        logger.debug(f"Mai névnapok: {names}")
        return names
    else:
        logger.debug("Nincs ismert névnap a mai napra")
        return "Nincs ismert névnap"

def get_notable_day():
    """Az aktuális jeles nap lekérdezése"""
    now = datetime.datetime.now(TIMEZONE)
    date_key = now.strftime("%m-%d")
    
    if date_key in NOTABLE_DAYS:
        logger.debug(f"Mai jeles nap: {NOTABLE_DAYS[date_key]}")
        return NOTABLE_DAYS[date_key]
    else:
        logger.debug("Nincs jeles nap a mai dátumra")
        return None

def get_moon_phase():
    """Holdfázis számítása százalékban és szövegesen"""
    try:
        now = datetime.datetime.now(TIMEZONE)
        
        # Holdfázis kiszámítása
        moon = ephem.Moon()
        moon.compute(now)
        
        # Holdfázis százalékban (0-100%)
        phase_percent = round(moon.phase)
        
        # Holdfázis szövegesen
        if phase_percent < 3:
            phase_text = "Újhold"
        elif phase_percent < 47:
            phase_text = "Növekvő hold"
        elif phase_percent < 53:
            phase_text = "Telihold"
        elif phase_percent < 97:
            phase_text = "Fogyó hold"
        else:
            phase_text = "Újhold"
        
        logger.debug(f"Holdfázis: {phase_text} ({phase_percent}%)")
        return phase_percent, phase_text
    except Exception as e:
        logger.error(f"Hiba a holdfázis számításánál: {e}")
        return 0, "Ismeretlen"

def get_sun_moon_times():
    """Napkelte, napnyugta, holdkelte, holdnyugta idejének kiszámítása"""
    try:
        # Készítsünk Observer objektumot (Budapest koordinátái)
        observer = ephem.Observer()
        observer.lat = '47.4979'   # Budapest szélesség
        observer.lon = '19.0402'   # Budapest hosszúság
        observer.elevation = 140   # Budapest átlagos tengerszint feletti magassága
        
        # Aktuális dátum
        now = datetime.datetime.now(TIMEZONE)
        observer.date = now
        
        # Nap
        sun = ephem.Sun()
        sun.compute(observer)
        
        # Napkelte/napnyugta
        sunrise = ephem.localtime(observer.next_rising(sun)).strftime('%H:%M')
        sunset = ephem.localtime(observer.next_setting(sun)).strftime('%H:%M')
        
        # Hold
        moon = ephem.Moon()
        moon.compute(observer)
        
        # Holdkelte/holdnyugta (kezelje az esetleges kivételeket)
        try:
            moonrise = ephem.localtime(observer.next_rising(moon)).strftime('%H:%M')
        except (ephem.AlwaysUpError, ephem.NeverUpError) as e:
            logger.warning(f"Holdkelte számítási hiba: {e}")
            moonrise = "Nem látható"
        
        try:
            moonset = ephem.localtime(observer.next_setting(moon)).strftime('%H:%M')
        except (ephem.AlwaysUpError, ephem.NeverUpError) as e:
            logger.warning(f"Holdnyugta számítási hiba: {e}")
            moonset = "Nem látható"
        
        result = {
            'napkelte': sunrise,
            'napnyugta': sunset,
            'holdkelte': moonrise,
            'holdnyugta': moonset
        }
        
        logger.debug(f"Nap/Hold idők: {result}")
        return result
    except Exception as e:
        logger.error(f"Hiba a Nap/Hold idők számításánál: {e}")
        return {
            'napkelte': "00:00",
            'napnyugta': "00:00",
            'holdkelte': "Nem elérhető",
            'holdnyugta': "Nem elérhető"
        }

def get_holidays():
    """Magyar ünnepnapok lekérdezése"""
    try:
        now = datetime.datetime.now(TIMEZONE)
        hu_holidays = holidays.Hungary(years=now.year)
        
        # Mai nap ellenőrzése
        today = now.strftime("%Y-%m-%d")
        if today in hu_holidays:
            logger.debug(f"Mai ünnepnap: {hu_holidays[today]}")
            return hu_holidays[today]
        
        logger.debug("Ma nem ünnepnap")
        return None
    except Exception as e:
        logger.error(f"Hiba az ünnepnapok lekérdezésénél: {e}")
        return None

def get_rss_news():
    """RSS hírek lekérdezése"""
    try:
        logger.debug(f"RSS hírek letöltése: {RSS_URL}")
        feed = feedparser.parse(RSS_URL)
        news_items = []
        
        for i, entry in enumerate(feed.entries):
            if i >= MAX_RSS_ITEMS:
                break
                
            # Szöveg kinyerése a bejegyzésből
            title = entry.title
            # Az első 80 karakter megtartása, ha hosszabb
            title = title if len(title) <= 80 else title[:77] + "..."
            news_items.append(title)
            
        logger.debug(f"Letöltött hírek száma: {len(news_items)}")
        return news_items
    except Exception as e:
        logger.error(f"RSS hiba: {e}")
        logger.error(traceback.format_exc())
        return ["RSS hírek betöltése sikertelen"]

def update_display():
    """A képernyő frissítése az aktuális adatokkal"""
    try:
        # E-Paper kijelző inicializálása
        logger.info("E-Paper kijelző inicializálása...")
        try:
            epd = epd4in01f.EPD()
            logger.debug("EPD objektum létrehozva")
            
            epd.init()
            logger.debug("EPD inicializálás sikeres")
        except Exception as e:
            logger.error(f"Hiba az E-Paper inicializálásakor: {e}")
            logger.error(traceback.format_exc())
            raise
        
        # Kép létrehozása
        logger.debug("Kép létrehozása...")
        image = Image.new('L', (WIDTH, HEIGHT), WHITE)
        draw = ImageDraw.Draw(image)
        
        # Aktuális dátum és idő
        now = datetime.datetime.now(TIMEZONE)
        date_str = now.strftime("%Y. %B %d. %A")  # pl. "2024. Május 17. Péntek"
        time_str = now.strftime("%H:%M")
        logger.debug(f"Aktuális dátum: {date_str}, idő: {time_str}")
        
        # Ünnepnap ellenőrzése
        logger.debug("Ünnepnap ellenőrzése...")
        holiday = get_holidays()
        is_holiday = holiday is not None
        
        # Alapvető adatok lekérdezése
        logger.debug("Alapadatok lekérdezése...")
        nameday = get_nameday()
        notable_day = get_notable_day()
        meteor_shower = get_active_meteor_shower()
        moon_phase_percent, moon_phase_text = get_moon_phase()
        sun_moon_times = get_sun_moon_times()
        
        # RSS hírek lekérdezése
        logger.debug("RSS hírek lekérdezése...")
        news_items = get_rss_news()
        
        # 7 színű megjelenítés
        # Háttér felosztása
        logger.debug("Háttér rajzolása...")
        draw.rectangle((0, 0, WIDTH, 70), fill=BLUE)  # Felső sáv
        draw.rectangle((0, 70, WIDTH, HEIGHT-80), fill=WHITE)  # Középső sáv
        draw.rectangle((0, HEIGHT-80, WIDTH, HEIGHT), fill=GREEN)  # Alsó sáv (hírek)
        
        # Dátum és idő kiírása
        if is_holiday:
            date_color = RED  # Piros, ha ünnepnap
        else:
            date_color = YELLOW  # Egyébként sárga
        
        # Dátum kiírása
        logger.debug("Szövegek kiírása...")
        draw.text((20, 15), date_str, font=font36, fill=date_color)
        draw.text((WIDTH-150, 15), time_str, font=font36, fill=WHITE)
        
        # Ha ünnepnap vagy jeles nap, kiírás
        y_pos = 80
        if is_holiday:
            draw.text((20, y_pos), f"Ünnepnap: {holiday}", font=font24, fill=RED)
            y_pos += 30
        
        if notable_day:
            draw.text((20, y_pos), f"Jeles nap: {notable_day}", font=font24, fill=ORANGE)
            y_pos += 30
        
        # Névnap kiírása
        draw.text((20, y_pos), f"Névnap: {nameday}", font=font24, fill=BLACK)
        y_pos += 30
        
        # Nap és Hold idők
        draw.text((20, y_pos), f"Napkelte: {sun_moon_times['napkelte']} - Napnyugta: {sun_moon_times['napnyugta']}", 
                 font=font24, fill=ORANGE)
        y_pos += 30
        
        draw.text((20, y_pos), f"Holdkelte: {sun_moon_times['holdkelte']} - Holdnyugta: {sun_moon_times['holdnyugta']}", 
                 font=font24, fill=BLUE)
        y_pos += 30
        
        # Holdfázis
        draw.text((20, y_pos), f"Holdfázis: {moon_phase_text} ({moon_phase_percent}%)", 
                 font=font24, fill=BLACK)
        y_pos += 40
        
        # Meteorraj
        if meteor_shower:
            draw.text((20, y_pos), f"Meteorraj: {meteor_shower['név']} - Csúcs: {meteor_shower['csúcs']} - ZHR: {meteor_shower['ZHR']}", 
                     font=font24, fill=BLUE)
            y_pos += 40
        
        # Elválasztó vonal a hírek előtt
        draw.line((0, HEIGHT-80, WIDTH, HEIGHT-80), fill=BLACK, width=2)
        
        # RSS hírek
        draw.text((20, HEIGHT-75), "Hírek (Telex):", font=font24, fill=BLUE)
        
        for i, news in enumerate(news_items):
            y = HEIGHT - 50 + (i * 25)
            draw.text((20, y), f"• {news}", font=font18, fill=BLACK)
        
        # Kép konvertálása 7 színűre
        logger.info("Kép megjelenítése a kijelzőn...")
        try:
            colored_image = epd.display(epd.getbuffer(image))
            logger.debug("Kép sikeresen megjelenítve")
        except Exception as e:
            logger.error(f"Hiba a kép megjelenítésekor: {e}")
            logger.error(traceback.format_exc())
            raise
        
        # Frissítés időpontjának rögzítése
        logger.info(f"Kijelző frissítve: {now.strftime('%Y-%m-%d %H:%M:%S')}")
        
        # E-ink kijelzők hosszú élettartamához: mélyalvó állapotba helyezés
        try:
            epd.sleep()
            logger.debug("E-Paper kijelző alvó állapotba helyezve")
        except Exception as e:
            logger.error(f"Hiba az alvó módba helyezéskor: {e}")
            logger.error(traceback.format_exc())
        
    except Exception as e:
        logger.error(f"Hiba a kijelző frissítésekor: {e}")
        logger.error(traceback.format_exc())

def main():
    """Fő program ciklus a rendszeres frissítéshez"""
    logger.info("E-Paper Naptár Program indítása...")
    
    try:
        retry_count = 0
        max_retries = 3
        
        while True:
            try:
                logger.info("Kijelző frissítése...")
                update_display()
                retry_count = 0  # Sikeres frissítés után nullázzuk a számlálót
                
                # Várjunk a következő frissítésig
                logger.info(f"Várakozás a következő frissítésig ({UPDATE_INTERVAL} másodperc)...")
                time.sleep(UPDATE_INTERVAL)
            except Exception as e:
                retry_count += 1
                logger.error(f"Hiba a kijelző frissítésekor (próbálkozás {retry_count}/{max_retries}): {e}")
                
                if retry_count >= max_retries:
                    logger.error("Maximális újrapróbálkozási szám elérve. Program leállítása.")
                    raise
                
                # Várjunk 60 másodpercet mielőtt újrapróbálkoznánk
                logger.info(f"Várakozás 60 másodpercet az újrapróbálkozás előtt...")
                time.sleep(60)
            
    except KeyboardInterrupt:
        logger.info("Program leállítása felhasználói megszakítással")
        sys.exit(0)
    
    except Exception as e:
        logger.error(f"Kritikus hiba a program futása során: {e}")
        logger.error(traceback.format_exc())
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

# Naplófájl előre létrehozása megfelelő jogosultságokkal
touch "$APP_DIR/calendar.log"
chmod 666 "$APP_DIR/calendar.log"
chown "$CURRENT_USER":"$CURRENT_USER" "$APP_DIR/calendar.log"
success "Naptár alkalmazás létrehozva megfelelő jogosultságokkal"

# Jogosultságok beállítása a futtatható alkalmazáshoz
chmod +x "$APP_DIR/calendar_display.py"
chown "$CURRENT_USER":"$CURRENT_USER" "$APP_DIR/calendar_display.py"

# Indítóscript létrehozása
cat > "$APP_DIR/start_calendar.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -d "venv" ]; then
    source venv/bin/activate
fi
echo "E-Paper Naptár indítása: $(date)" > start.log
python3 calendar_display.py >> start.log 2>&1
EOF

chmod +x "$APP_DIR/start_calendar.sh"
chown "$CURRENT_USER":"$CURRENT_USER" "$APP_DIR/start_calendar.sh"
success "Indítóscript létrehozva"

# Létrehozzuk a szolgáltatást az automatikus indításhoz
cat > /tmp/e-paper-calendar.service << EOF
[Unit]
Description=E-Paper Calendar Display Service
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/start_calendar.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

if [ "$(id -u)" -eq 0 ]; then
    mv /tmp/e-paper-calendar.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable e-paper-calendar.service
    success "Rendszerszolgáltatás létrehozva és engedélyezve"
else
    warning "Rendszerszolgáltatás létrehozása kihagyva (nem rendszergazda)"
    echo "A szolgáltatás fájl itt található: /tmp/e-paper-calendar.service"
    echo "Telepítse manuálisan rendszergazda jogosultsággal:"
    echo "sudo mv /tmp/e-paper-calendar.service /etc/systemd/system/"
    echo "sudo systemctl daemon-reload"
    echo "sudo systemctl enable e-paper-calendar.service"
fi

# Jogosultságok beállítása a teljes alkalmazás könyvtárhoz
if [ "$(id -u)" -eq 0 ]; then
    chown -R "$CURRENT_USER":"$CURRENT_USER" "$APP_DIR"
    chmod -R 755 "$APP_DIR"
    success "Alkalmazás könyvtár jogosultságok beállítva"
else
    warning "Könyvtárjogosultságok beállítása kihagyva (nem rendszergazda)"
fi

# Összefoglaló
echo ""
echo "==========================================="
echo "Telepítés befejezve!"
echo "==========================================="
echo "A naptár alkalmazás telepítése befejeződött."
echo ""
echo "A naptár alkalmazás helye: $APP_DIR"
echo "Napló fájl: $APP_DIR/calendar.log"
echo "Telepítési naplók: $INSTALL_LOG_DIR"
echo ""
echo "A naptár alkalmazást a következő parancsokkal kezelheti:"
echo "  Indítás: sudo systemctl start e-paper-calendar"
echo "  Leállítás: sudo systemctl stop e-paper-calendar"
echo "  Újraindítás: sudo systemctl restart e-paper-calendar"
echo "  Állapot ellenőrzése: sudo systemctl status e-paper-calendar"
echo ""
echo "Az alkalmazás manuálisan is indítható:"
echo "  cd $APP_DIR && ./start_calendar.sh"
echo ""

# Figyelmeztetés az újraindításról
if [ $REBOOT_NEEDED -eq 1 ]; then
    echo -e "\e[33mFIGYELEM:\e[0m Az SPI interfész és/vagy felhasználói csoportok módosítása miatt újra kell indítani a Raspberry Pi-t!"
    echo "Újraindítás most? (i/n)"
    read -r answer
    if [ "$answer" = "i" ] || [ "$answer" = "I" ]; then
        echo "A Raspberry Pi újraindul..."
        reboot
    else
        echo "Kérjük, indítsa újra a Raspberry Pi-t manuálisan a későbbiekben!"
    fi
else
    # Ellenőrzés, hogy kell-e indítani a szolgáltatást
    if [ "$(id -u)" -eq 0 ]; then
        echo "A szolgáltatás indítása..."
        systemctl start e-paper-calendar
        echo "A naptár rövidesen megjelenik a kijelzőn..."
    else
        echo "Indítsa el a szolgáltatást manuálisan:"
        echo "sudo systemctl start e-paper-calendar"
    fi
fi
