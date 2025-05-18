#!/bin/bash

# E-Paper Calendar Display Installer (TOVÁBBFEJLESZTETT VERZIÓ)
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-paper HAT

echo "======================================================"
echo "E-Paper Calendar Display Installer (TOVÁBBFEJLESZTETT VERZIÓ)"
echo "Raspberry Pi Zero 2W + Waveshare 4.01 inch 7-color HAT"
echo "======================================================"

# Aktuális felhasználó és könyvtárak
CURRENT_USER=$(whoami)
echo "Telepítés a következő felhasználóhoz: $CURRENT_USER"
PROJECT_DIR="/home/$CURRENT_USER/epaper_calendar"

# Könyvtár létrehozása
mkdir -p "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/icons"
cd "$PROJECT_DIR"

# Naplózás beállítása
LOGFILE="$PROJECT_DIR/install.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "$(date) - Telepítés kezdése"

# Függőségek telepítése
echo "Függőségek telepítése..."
sudo apt-get update
sudo apt-get install -y python3-pip python3-dev git
sudo apt-get install -y python3-pil python3-numpy libopenjp2-7-dev
sudo apt-get install -y python3-rpi.gpio python3-spidev
sudo apt-get install -y python3-requests python3-feedparser python3-dateutil

# Astral és más Python könyvtárak telepítése
echo "Python könyvtárak telepítése..."
pip3 install --break-system-packages astral python-dateutil requests

# SPI engedélyezése
echo "SPI interfész ellenőrzése..."
if ! grep -q "^dtparam=spi=on" /boot/config.txt; then
    echo "SPI interfész engedélyezése..."
    echo "dtparam=spi=on" | sudo tee -a /boot/config.txt
    REBOOT_NEEDED=true
fi

# Felhasználói jogosultságok
echo "Felhasználói jogosultságok beállítása..."
sudo usermod -a -G spi,gpio,dialout "$CURRENT_USER"

# Hivatalos Waveshare könyvtár letöltése
echo "Waveshare e-Paper könyvtár telepítése..."
git clone https://github.com/waveshare/e-Paper.git
if [ $? -ne 0 ]; then
    echo "HIBA: Nem sikerült letölteni a Waveshare könyvtárat a GitHub-ról"
    exit 1
fi

# Időjárási ikonok letöltése
echo "Időjárási ikonok letöltése..."
# Clear/sunny
curl -s -o "$PROJECT_DIR/icons/01d.png" "https://openweathermap.org/img/wn/01d@2x.png"
curl -s -o "$PROJECT_DIR/icons/01n.png" "https://openweathermap.org/img/wn/01n@2x.png"
# Few clouds
curl -s -o "$PROJECT_DIR/icons/02d.png" "https://openweathermap.org/img/wn/02d@2x.png"
curl -s -o "$PROJECT_DIR/icons/02n.png" "https://openweathermap.org/img/wn/02n@2x.png"
# Scattered clouds
curl -s -o "$PROJECT_DIR/icons/03d.png" "https://openweathermap.org/img/wn/03d@2x.png"
curl -s -o "$PROJECT_DIR/icons/03n.png" "https://openweathermap.org/img/wn/03n@2x.png"
# Broken clouds
curl -s -o "$PROJECT_DIR/icons/04d.png" "https://openweathermap.org/img/wn/04d@2x.png"
curl -s -o "$PROJECT_DIR/icons/04n.png" "https://openweathermap.org/img/wn/04n@2x.png"
# Rain
curl -s -o "$PROJECT_DIR/icons/10d.png" "https://openweathermap.org/img/wn/10d@2x.png"
curl -s -o "$PROJECT_DIR/icons/10n.png" "https://openweathermap.org/img/wn/10n@2x.png"
# Thunderstorm
curl -s -o "$PROJECT_DIR/icons/11d.png" "https://openweathermap.org/img/wn/11d@2x.png"
# Snow
curl -s -o "$PROJECT_DIR/icons/13d.png" "https://openweathermap.org/img/wn/13d@2x.png"
# Mist
curl -s -o "$PROJECT_DIR/icons/50d.png" "https://openweathermap.org/img/wn/50d@2x.png"

# Kijelző inicializáló program létrehozása
echo "Kijelző inicializáló program létrehozása..."
cat > "$PROJECT_DIR/initialize_display.py" << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

# Waveshare e-Paper kijelző inicializáló program

import os
import sys
import time
import logging
import traceback
from PIL import Image, ImageDraw, ImageFont

# Naplózás beállítása
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.expanduser("~/epaper_init.log")),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

def initialize_display():
    try:
        # Waveshare könyvtár elérési útvonala
        current_dir = os.path.dirname(os.path.realpath(__file__))
        sys.path.append(os.path.join(current_dir, 'e-Paper/RaspberryPi_JetsonNano/python/lib'))
        
        # Waveshare modult importáljuk
        logger.info("Waveshare modul importálása...")
        
        # Próbáljuk az eredeti 4.01inch 7-color modult
        try:
            from waveshare_epd import epd4in01f
            logger.info("epd4in01f modul importálva!")
            epd = epd4in01f.EPD()
        except ImportError:
            logger.warning("epd4in01f modul nem található, alternatív modulok keresése...")
            
            # Keressünk más lehetséges modult
            waveshare_dir = os.path.join(current_dir, 'e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd')
            if os.path.exists(waveshare_dir):
                for file in os.listdir(waveshare_dir):
                    if file.startswith('epd') and file.endswith('.py') and 'f' in file:
                        module_name = file[:-3]  # .py nélkül
                        logger.info(f"Alternatív modul próbálása: {module_name}")
                        try:
                            # Dinamikus import
                            import importlib
                            waveshare_epd = importlib.import_module('waveshare_epd')
                            epd_module = getattr(waveshare_epd, module_name)
                            epd = epd_module.EPD()
                            logger.info(f"Sikeresen importálva: {module_name}")
                            break
                        except Exception as e:
                            logger.error(f"Hiba az alternatív modul importálásakor: {e}")
                else:
                    raise ImportError("Nem található kompatibilis e-Paper modul")
            else:
                raise ImportError("Waveshare könyvtár nem található")
        
        # Kijelző inicializálása
        logger.info("Kijelző inicializálása...")
        epd.init()
        
        # Képernyőméret lekérése
        width = epd.width
        height = epd.height
        logger.info(f"Kijelző mérete: {width}x{height}")
        
        # Tesztüzenet megjelenítése
        logger.info("Tesztüzenet megjelenítése...")
        font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
        
        if os.path.exists(font_path):
            font = ImageFont.truetype(font_path, 36)
        else:
            font = ImageFont.load_default()
        
        # Teszt kép létrehozása
        image = Image.new('RGB', (width, height), (255, 255, 255))
        draw = ImageDraw.Draw(image)
        
        # Szép háttér készítése
        # Háttér kitöltése világoskék színnel
        draw.rectangle([(0, 0), (width, height)], fill=(235, 245, 255))
        
        # Felső sáv
        draw.rectangle([(0, 0), (width, 60)], fill=(70, 130, 180))
        
        # Címsor
        draw.text((width//2 - 180, 12), "E-Paper Naptár Inicializálva", font=font, fill=(255, 255, 255))
        
        # Verzió és dátum
        now = time.strftime("%Y-%m-%d %H:%M:%S")
        draw.text((20, 100), f"Inicializálva: {now}", font=font, fill=(0, 0, 0))
        
        # Ellenőrző minta a 7 színhez
        colors = [
            (0, 0, 0),       # Fekete
            (255, 255, 255), # Fehér
            (0, 255, 0),     # Zöld
            (0, 0, 255),     # Kék
            (255, 0, 0),     # Piros
            (255, 255, 0),   # Sárga
            (255, 165, 0)    # Narancs
        ]
        
        # Színek panel háttere
        draw.rectangle([(10, 160), (width-10, 360)], fill=(255, 255, 255), outline=(70, 130, 180), width=2)
        draw.text((20, 170), "Támogatott színek:", font=font, fill=(70, 130, 180))
        
        for i, color in enumerate(colors):
            y_pos = 220 + i*30
            draw.rectangle([(40, y_pos), (120, y_pos+20)], fill=color, outline=(0, 0, 0))
            
            # Színnév
            color_names = ["Fekete", "Fehér", "Zöld", "Kék", "Piros", "Sárga", "Narancs"]
            draw.text((140, y_pos-5), color_names[i], font=font, fill=(0, 0, 0))
        
        # A naptár program indulási ütemezése
        draw.rectangle([(0, height-50), (width, height)], fill=(70, 130, 180))
        draw.text((width//2 - 200, height-40), "A naptár program hamarosan elindul...", font=font, fill=(255, 255, 255))
        
        # Kép küldése a kijelzőre
        logger.info("Kép küldése a kijelzőre...")
        epd.display(epd.getbuffer(image))
        
        # Képernyőkép mentése
        image_path = os.path.expanduser("~/epaper_init.png")
        image.save(image_path)
        logger.info(f"Képernyőkép elmentve: {image_path}")
        
        # Kis késleltetés, hogy a felhasználó láthassa a tesztképet
        logger.info("Várakozás 5 másodpercet...")
        time.sleep(5)
        
        # Alvó módba helyezzük a kijelzőt
        logger.info("Kijelző alvó módba helyezése...")
        epd.sleep()
        
        logger.info("Kijelző inicializálása sikeres!")
        return True
        
    except Exception as e:
        logger.error(f"Hiba a kijelző inicializálása közben: {e}")
        logger.error(traceback.format_exc())
        return False

if __name__ == "__main__":
    # Ha közvetlenül futtatják, inicializáljuk a kijelzőt
    success = initialize_display()
    if success:
        print("A kijelző sikeresen inicializálva!")
    else:
        print("HIBA: A kijelző inicializálása sikertelen!")
        sys.exit(1)
EOL

chmod +x "$PROJECT_DIR/initialize_display.py"

# Konfiguráció létrehozása
echo "Konfiguráció létrehozása..."
cat > "$PROJECT_DIR/config.py" << EOL
# E-Paper Calendar Display konfigurációs fájl

# OpenWeatherMap API kulcs
OPENWEATHERMAP_API_KEY = "1e39a49c6785626b3aca124f4d4ce591"

# Város, ahol laksz
CITY = "Pécs"
COUNTRY = "Hungary"
LATITUDE = 46.0727
LONGITUDE = 18.2323
TIMEZONE = "Europe/Budapest"

# RSS hírforrás URL-je
RSS_URL = "https://telex.hu/rss"

# Kijelző frissítési gyakorisága (percben)
REFRESH_INTERVAL = 10

# Megjelenítési beállítások
SHOW_WEATHER = True        # Időjárás megjelenítése
SHOW_RSS_NEWS = True       # RSS hírek megjelenítése
SHOW_METEORS = True        # Meteorrajok megjelenítése
SHOW_MOON_PHASE = True     # Holdfázis megjelenítése

# Színek
HEADER_COLOR = (70, 130, 180)   # Fejléc kék
ACCENT_COLOR = (0, 120, 215)    # Kiemelő szín
LIGHT_BG = (235, 245, 255)      # Világos háttér
DARK_BG = (25, 55, 90)          # Sötét háttér
PANEL_BG = (255, 255, 255)      # Panel háttér
EOL

# Önálló naptár program létrehozása - Szebb designnal és időjárás információkkal
# MATH MODUL IMPORTÁLVA A HIBA ELKERÜLÉSE VÉGETT
echo "Önálló naptár program létrehozása..."
cat > "$PROJECT_DIR/calendar_display.py" << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

# Továbbfejlesztett Naptár Megjelenítő Program
# Szebb design és időjárás információk

import os
import sys
import time
import math  # MATH MODUL IMPORTÁLVA
import datetime
import traceback
import logging
import feedparser
import requests
import json
import RPi.GPIO as GPIO
from dateutil.easter import easter
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# Konfigurációs fájl importálása
try:
    sys.path.append(os.path.dirname(os.path.realpath(__file__)))
    from config import *
except ImportError:
    # Alapértelmezett beállítások, ha nem sikerült betölteni a konfigurációt
    OPENWEATHERMAP_API_KEY = "1e39a49c6785626b3aca124f4d4ce591"
    CITY = "Pécs"
    COUNTRY = "Hungary"
    LATITUDE = 46.0727
    LONGITUDE = 18.2323
    TIMEZONE = "Europe/Budapest"
    RSS_URL = "https://telex.hu/rss"
    REFRESH_INTERVAL = 10
    SHOW_WEATHER = True
    SHOW_RSS_NEWS = True
    SHOW_METEORS = True
    SHOW_MOON_PHASE = True
    HEADER_COLOR = (70, 130, 180)
    ACCENT_COLOR = (0, 120, 215)
    LIGHT_BG = (235, 245, 255)
    DARK_BG = (25, 55, 90)
    PANEL_BG = (255, 255, 255)

# Naplózás beállítása
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.expanduser("~/epaper_calendar.log")),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Importok ellenőrzése
try:
    from astral import LocationInfo
    
    # Astral importok kezelése különböző verziókhoz
    try:
        # Először próbáljuk az Astral 2.2+ verziót
        from astral.sun import sun
        try:
            # Astral 2.2 moon API
            from astral.moon import phase as moon_phase_func
            def moon_phase(date):
                return moon_phase_func(date)
                
            from astral.moon import moonrise, moonset
            logger.info("Astral 2.2+ importálva")
        except ImportError:
            # Régebbi Astral 2.x
            from astral import moon
            def moon_phase(date):
                return moon.phase(date)
                
            def moonrise(observer, date):
                return moon.moonrise(observer, date)
                
            def moonset(observer, date):
                return moon.moonset(observer, date)
            logger.info("Astral 2.x importálva")
    except ImportError:
        # Régi Astral 1.x
        try:
            from astral import Astral
            a = Astral()
            def sun(observer, date=None):
                city = a['London']  # Ideiglenes város
                city.observer = observer
                return city.sun(date=date)
                
            def moon_phase(date):
                return a.moon_phase(date)
                
            def moonrise(observer, date):
                city = a['London']
                city.observer = observer
                return a.moon_rise(city.observer, date)
                
            def moonset(observer, date):
                city = a['London']
                city.observer = observer
                return a.moon_set(city.observer, date)
            logger.info("Astral 1.x importálva")
        except Exception as e:
            # Fallback dummy függvények
            logger.error(f"Nem sikerült importálni az Astral függvényeket: {e}")
            def sun(observer, date=None):
                now = datetime.datetime.now()
                sunrise = datetime.datetime(now.year, now.month, now.day, 6, 0, 0)
                sunset = datetime.datetime(now.year, now.month, now.day, 18, 0, 0)
                return {"sunrise": sunrise, "sunset": sunset}
                
            def moon_phase(date):
                return 0
                
            def moonrise(observer, date):
                return None
                
            def moonset(observer, date):
                return None
except ImportError as e:
    logger.error(f"Hiányzó modul: {e}")
    logger.error("Próbáld meg telepíteni: pip3 install --break-system-packages astral requests")
    sys.exit(1)

# Segédfüggvény a holdfázisok leírásához
def get_moon_phase_description(percent):
    if percent < 2:
        return "Újhold"
    elif percent < 23:
        return "Növekvő sarló"
    elif percent < 27:
        return "Első negyed"
    elif percent < 48:
        return "Növekvő hold"
    elif percent < 52:
        return "Telihold"
    elif percent < 73:
        return "Fogyó hold"
    elif percent < 77:
        return "Utolsó negyed"
    elif percent < 98:
        return "Fogyó sarló"
    else:
        return "Újhold"

# Konstansok
WIDTH = 640
HEIGHT = 400

# Színkódok
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
GREEN = (0, 170, 0)
BLUE = (0, 100, 200)
RED = (200, 0, 0)
YELLOW = (255, 180, 0)
ORANGE = (255, 120, 0)
GRAY = (100, 100, 100)
LIGHT_GRAY = (200, 200, 200)

# Magyar ünnepnapok és jeles napok (fix dátumok)
FIXED_HOLIDAYS = {
    (1, 1): ("Újév", RED),
    (3, 15): ("Nemzeti ünnep", RED),
    (5, 1): ("A munka ünnepe", RED),
    (8, 20): ("Államalapítás ünnepe", RED),
    (10, 23): ("Nemzeti ünnep", RED),
    (11, 1): ("Mindenszentek", RED),
    (12, 24): ("Szenteste", RED),
    (12, 25): ("Karácsony 1. napja", RED),
    (12, 26): ("Karácsony 2. napja", RED)
}

# Jeles napok (nem ünnepnapok)
NOTABLE_DAYS = {
    (1, 22): ("A magyar kultúra napja", BLUE),
    (2, 2): ("Gyertyaszentelő Boldogasszony", BLUE),
    (2, 14): ("Valentin-nap", RED),
    (3, 8): ("Nemzetközi nőnap", ORANGE),
    (4, 11): ("A magyar költészet napja", BLUE),
    (4, 22): ("A Föld napja", GREEN),
    (5, 8): ("A vöröskereszt világnapja", RED),
    (5, 10): ("Madarak és fák napja", GREEN),
    (5, 31): ("Nemdohányzó világnap", BLUE),
    (6, 5): ("Környezetvédelmi világnap", GREEN),
    (7, 1): ("Köztisztviselők napja", BLUE),
    (8, 1): ("A forint születésnapja", BLUE),
    (9, 30): ("A magyar népmese napja", ORANGE),
    (10, 1): ("Zenei világnap", BLUE),
    (10, 6): ("Az aradi vértanúk napja", RED),
    (11, 3): ("A magyar tudomány napja", BLUE),
    (11, 27): ("Véradók napja", RED),
    (12, 6): ("Mikulás", RED)
}

# Magyar névnapok
def get_hungarian_namedays():
    namedays = {
        (1, 1): "Fruzsina",
        (1, 2): "Ábel",
        (1, 3): "Genovéva, Benjámin",
        (1, 4): "Titusz, Leona",
        (1, 5): "Simon",
        (1, 6): "Boldizsár",
        (1, 7): "Attila, Ramóna",
        (1, 8): "Gyöngyvér",
        (1, 9): "Marcell",
        (1, 10): "Melánia",
        (1, 11): "Ágota",
        (1, 12): "Ernő",
        (1, 13): "Veronika",
        (1, 14): "Bódog",
        (1, 15): "Lóránt, Loránd",
        (1, 16): "Gusztáv",
        (1, 17): "Antal, Antónia",
        (1, 18): "Piroska",
        (1, 19): "Sára, Márió",
        (1, 20): "Fábián, Sebestyén",
        (1, 21): "Ágnes",
        (1, 22): "Vince, Artúr",
        (1, 23): "Zelma, Rajmund",
        (1, 24): "Timót",
        (1, 25): "Pál",
        (1, 26): "Vanda, Paula",
        (1, 27): "Angelika",
        (1, 28): "Károly, Karola",
        (1, 29): "Adél",
        (1, 30): "Martina, Gerda",
        (1, 31): "Marcella",
        (2, 1): "Ignác",
        (2, 2): "Karolina, Aida",
        (2, 3): "Balázs",
        (2, 4): "Ráhel, Csenge",
        (2, 5): "Ágota, Ingrid",
        (2, 6): "Dorottya, Dóra",
        (2, 7): "Tódor, Rómeó",
        (2, 8): "Aranka",
        (2, 9): "Abigél, Alex",
        (2, 10): "Elvira",
        (2, 11): "Bertold, Marietta",
        (2, 12): "Lívia, Lídia",
        (2, 13): "Ella, Linda",
        (2, 14): "Bálint, Valentin",
        (2, 15): "Kolos, Georgina",
        (2, 16): "Julianna, Lilla",
        (2, 17): "Donát",
        (2, 18): "Bernadett",
        (2, 19): "Zsuzsanna",
        (2, 20): "Aladár, Álmos",
        (2, 21): "Eleonóra",
        (2, 22): "Gerzson",
        (2, 23): "Alfréd",
        (2, 24): "Mátyás",
        (2, 25): "Géza",
        (2, 26): "Edina",
        (2, 27): "Ákos, Bátor",
        (2, 28): "Elemér",
        (2, 29): "Antónia, Román",
        (3, 1): "Albin",
        (3, 2): "Lujza",
        (3, 3): "Kornélia",
        (3, 4): "Kázmér",
        (3, 5): "Adorján, Adrián",
        (3, 6): "Leonóra, Inez",
        (3, 7): "Tamás",
        (3, 8): "Zoltán",
        (3, 9): "Franciska, Fanni",
        (3, 10): "Ildikó",
        (3, 11): "Szilárd",
        (3, 12): "Gergely",
        (3, 13): "Krisztián, Ajtony",
        (3, 14): "Matild",
        (3, 15): "Kristóf",
        (3, 16): "Henrietta",
        (3, 17): "Gertrúd, Patrik",
        (3, 18): "Sándor, Ede",
        (3, 19): "József, Bánk",
        (3, 20): "Klaudia",
        (3, 21): "Benedek",
        (3, 22): "Beáta, Izolda",
        (3, 23): "Emőke",
        (3, 24): "Gábor, Karina",
        (3, 25): "Irén, Írisz",
        (3, 26): "Emánuel",
        (3, 27): "Hajnalka",
        (3, 28): "Gedeon, Johanna",
        (3, 29): "Auguszta",
        (3, 30): "Zalán",
        (3, 31): "Árpád",
        (4, 1): "Hugó",
        (4, 2): "Áron",
        (4, 3): "Buda, Richárd",
        (4, 4): "Izidor",
        (4, 5): "Vince",
        (4, 6): "Vilmos, Bíborka",
        (4, 7): "Herman",
        (4, 8): "Dénes",
        (4, 9): "Erhard",
        (4, 10): "Zsolt",
        (4, 11): "Leó, Szaniszló",
        (4, 12): "Gyula",
        (4, 13): "Ida",
        (4, 14): "Tibor",
        (4, 15): "Anasztázia, Tas",
        (4, 16): "Csongor",
        (4, 17): "Rudolf",
        (4, 18): "Andrea, Ilma",
        (4, 19): "Emma",
        (4, 20): "Tivadar",
        (4, 21): "Konrád",
        (4, 22): "Csilla, Noémi",
        (4, 23): "Béla",
        (4, 24): "György",
        (4, 25): "Márk",
        (4, 26): "Ervin",
        (4, 27): "Zita",
        (4, 28): "Valéria",
        (4, 29): "Péter",
        (4, 30): "Katalin, Kitti",
        (5, 1): "Fülöp, Jakab",
        (5, 2): "Zsigmond",
        (5, 3): "Tímea, Irma",
        (5, 4): "Mónika, Flórián",
        (5, 5): "Györgyi",
        (5, 6): "Ivett, Frida",
        (5, 7): "Gizella",
        (5, 8): "Mihály",
        (5, 9): "Gergely",
        (5, 10): "Ármin, Pálma",
        (5, 11): "Ferenc",
        (5, 12): "Pongrác",
        (5, 13): "Szervác, Imola",
        (5, 14): "Bonifác",
        (5, 15): "Zsófia, Szonja",
        (5, 16): "Mózes, Botond",
        (5, 17): "Paszkál",
        (5, 18): "Erik, Alexandra",
        (5, 19): "Ivó, Milán",
        (5, 20): "Bernát, Felícia",
        (5, 21): "Konstantin",
        (5, 22): "Júlia, Rita",
        (5, 23): "Dezső",
        (5, 24): "Eszter, Eliza",
        (5, 25): "Orbán",
        (5, 26): "Fülöp, Evelin",
        (5, 27): "Hella",
        (5, 28): "Emil, Csanád",
        (5, 29): "Magdolna",
        (5, 30): "Janka, Zsanett",
        (5, 31): "Angéla, Petronella",
        (6, 1): "Tünde",
        (6, 2): "Kármen, Anita",
        (6, 3): "Klotild",
        (6, 4): "Bulcsú",
        (6, 5): "Fatime",
        (6, 6): "Norbert, Cintia",
        (6, 7): "Róbert",
        (6, 8): "Medárd",
        (6, 9): "Félix",
        (6, 10): "Margit, Gréta",
        (6, 11): "Barnabás",
        (6, 12): "Villő",
        (6, 13): "Antal, Anett",
        (6, 14): "Vazul",
        (6, 15): "Jolán, Vid",
        (6, 16): "Jusztin",
        (6, 17): "Laura, Alida",
        (6, 18): "Arnold, Levente",
        (6, 19): "Gyárfás",
        (6, 20): "Rafael",
        (6, 21): "Alajos, Leila",
        (6, 22): "Paulina",
        (6, 23): "Zoltán",
        (6, 24): "Iván",
        (6, 25): "Vilmos",
        (6, 26): "János, Pál",
        (6, 27): "László",
        (6, 28): "Levente, Irén",
        (6, 29): "Péter, Pál",
        (6, 30): "Pál",
        (7, 1): "Tihamér, Annamária",
        (7, 2): "Ottó",
        (7, 3): "Kornél, Soma",
        (7, 4): "Ulrik",
        (7, 5): "Emese, Sarolta",
        (7, 6): "Csaba",
        (7, 7): "Apollónia",
        (7, 8): "Ellák",
        (7, 9): "Lukrécia",
        (7, 10): "Amália",
        (7, 11): "Nóra, Lili",
        (7, 12): "Izabella, Dalma",
        (7, 13): "Jenő",
        (7, 14): "Örs, Stella",
        (7, 15): "Henrik, Roland",
        (7, 16): "Valter",
        (7, 17): "Endre, Elek",
        (7, 18): "Frigyes",
        (7, 19): "Emília",
        (7, 20): "Illés",
        (7, 21): "Dániel, Daniella",
        (7, 22): "Magdolna",
        (7, 23): "Lenke",
        (7, 24): "Kinga, Kincső",
        (7, 25): "Kristóf, Jakab",
        (7, 26): "Anna, Anikó",
        (7, 27): "Olga, Liliána",
        (7, 28): "Szabolcs",
        (7, 29): "Márta, Flóra",
        (7, 30): "Judit, Xénia",
        (7, 31): "Oszkár",
        (8, 1): "Boglárka",
        (8, 2): "Lehel",
        (8, 3): "Hermina",
        (8, 4): "Domonkos, Dominika",
        (8, 5): "Krisztina",
        (8, 6): "Berta, Bettina",
        (8, 7): "Ibolya",
        (8, 8): "László",
        (8, 9): "Emőd",
        (8, 10): "Lőrinc",
        (8, 11): "Zsuzsanna, Tiborc",
        (8, 12): "Klára",
        (8, 13): "Ipoly",
        (8, 14): "Marcell",
        (8, 15): "Mária",
        (8, 16): "Ábrahám",
        (8, 17): "Jácint",
        (8, 18): "Ilona",
        (8, 19): "Huba",
        (8, 20): "István",
        (8, 21): "Sámuel, Hajna",
        (8, 22): "Menyhért, Mirjam",
        (8, 23): "Bence",
        (8, 24): "Bertalan",
        (8, 25): "Lajos, Patrícia",
        (8, 26): "Izsó",
        (8, 27): "Gáspár",
        (8, 28): "Ágoston",
        (8, 29): "Beatrix, Erna",
        (8, 30): "Rózsa",
        (8, 31): "Erika, Bella",
        (9, 1): "Egyed, Egon",
        (9, 2): "Rebeka, Dorina",
        (9, 3): "Hilda",
        (9, 4): "Rozália",
        (9, 5): "Viktor, Lőrinc",
        (9, 6): "Zakariás",
        (9, 7): "Regina",
        (9, 8): "Mária, Adrienn",
        (9, 9): "Ádám",
        (9, 10): "Nikolett, Hunor",
        (9, 11): "Teodóra",
        (9, 12): "Mária",
        (9, 13): "Kornél",
        (9, 14): "Szeréna, Roxána",
        (9, 15): "Enikő, Melitta",
        (9, 16): "Edit",
        (9, 17): "Zsófia",
        (9, 18): "Diána",
        (9, 19): "Vilhelmina",
        (9, 20): "Friderika",
        (9, 21): "Máté, Mirella",
        (9, 22): "Móric",
        (9, 23): "Tekla",
        (9, 24): "Gellért, Mercédesz",
        (9, 25): "Eufrozina, Kende",
        (9, 26): "Jusztina, Pál",
        (9, 27): "Adalbert",
        (9, 28): "Vencel",
        (9, 29): "Mihály",
        (9, 30): "Jeromos",
        (10, 1): "Malvin",
        (10, 2): "Petra",
        (10, 3): "Helga",
        (10, 4): "Ferenc",
        (10, 5): "Aurél",
        (10, 6): "Brúnó, Renáta",
        (10, 7): "Amália",
        (10, 8): "Koppány",
        (10, 9): "Dénes",
        (10, 10): "Gedeon",
        (10, 11): "Brigitta",
        (10, 12): "Miksa",
        (10, 13): "Kálmán, Ede",
        (10, 14): "Helén",
        (10, 15): "Teréz",
        (10, 16): "Gál",
        (10, 17): "Hedvig",
        (10, 18): "Lukács",
        (10, 19): "Nándor",
        (10, 20): "Vendel",
        (10, 21): "Orsolya",
        (10, 22): "Előd",
        (10, 23): "Gyöngyi",
        (10, 24): "Salamon",
        (10, 25): "Blanka, Bianka",
        (10, 26): "Dömötör",
        (10, 27): "Szabina",
        (10, 28): "Simon, Szimonetta",
        (10, 29): "Nárcisz",
        (10, 30): "Alfonz",
        (10, 31): "Farkas",
        (11, 1): "Marianna",
        (11, 2): "Achilles",
        (11, 3): "Győző",
        (11, 4): "Károly",
        (11, 5): "Imre",
        (11, 6): "Lénárd",
        (11, 7): "Rezső",
        (11, 8): "Zsombor",
        (11, 9): "Tivadar",
        (11, 10): "Réka",
        (11, 11): "Márton",
        (11, 12): "Jónás, Renátó",
        (11, 13): "Szilvia",
        (11, 14): "Aliz",
        (11, 15): "Albert, Lipót",
        (11, 16): "Ödön",
        (11, 17): "Hortenzia, Gergő",
        (11, 18): "Jenő",
        (11, 19): "Erzsébet",
        (11, 20): "Jolán",
        (11, 21): "Olivér",
        (11, 22): "Cecília",
        (11, 23): "Kelemen, Klementina",
        (11, 24): "Emma",
        (11, 25): "Katalin",
        (11, 26): "Virág",
        (11, 27): "Virgil",
        (11, 28): "Stefánia",
        (11, 29): "Taksony",
        (11, 30): "András, Andor",
        (12, 1): "Elza",
        (12, 2): "Melinda, Vivien",
        (12, 3): "Ferenc, Olívia",
        (12, 4): "Borbála, Barbara",
        (12, 5): "Vilma",
        (12, 6): "Miklós",
        (12, 7): "Ambrus",
        (12, 8): "Mária",
        (12, 9): "Natália",
        (12, 10): "Judit",
        (12, 11): "Árpád",
        (12, 12): "Gabriella",
        (12, 13): "Luca, Otília",
        (12, 14): "Szilárda",
        (12, 15): "Valér",
        (12, 16): "Etelka, Aletta",
        (12, 17): "Lázár, Olimpia",
        (12, 18): "Auguszta",
        (12, 19): "Viola",
        (12, 20): "Teofil",
        (12, 21): "Tamás",
        (12, 22): "Zénó",
        (12, 23): "Viktória",
        (12, 24): "Ádám, Éva",
        (12, 25): "Eugénia",
        (12, 26): "István",
        (12, 27): "János",
        (12, 28): "Kamilla",
        (12, 29): "Tamás, Tamara",
        (12, 30): "Dávid",
        (12, 31): "Szilveszter"
    }
    return namedays

# Meteorrajok adatai
def get_meteor_showers():
    meteor_showers = [
        {"name": "Quadrantidák", "start": (1, 1), "peak": (1, 3), "end": (1, 6)},
        {"name": "Lyridák", "start": (4, 16), "peak": (4, 22), "end": (4, 25)},
        {"name": "Eta Aquaridák", "start": (4, 19), "peak": (5, 6), "end": (5, 28)},
        {"name": "Delta Aquaridák", "start": (7, 12), "peak": (7, 30), "end": (8, 23)},
        {"name": "Perseidák", "start": (7, 17), "peak": (8, 12), "end": (8, 24)},
        {"name": "Orionidák", "start": (10, 2), "peak": (10, 21), "end": (11, 7)},
        {"name": "Leonidák", "start": (11, 6), "peak": (11, 17), "end": (11, 30)},
        {"name": "Geminidák", "start": (12, 4), "peak": (12, 14), "end": (12, 17)}
    ]
    return meteor_showers

# Mozgó ünnepek meghatározása adott évre
def get_moving_holidays(year):
    # Húsvét vasárnap
    easter_date = easter(year)
    
    # Nagypéntek (Húsvét vasárnap - 2 nap)
    good_friday = easter_date - datetime.timedelta(days=2)
    
    # Húsvét hétfő (Húsvét vasárnap + 1 nap)
    easter_monday = easter_date + datetime.timedelta(days=1)
    
    # Pünkösd vasárnap (Húsvét vasárnap + 49 nap)
    pentecost = easter_date + datetime.timedelta(days=49)
    
    # Pünkösd hétfő (Húsvét vasárnap + 50 nap)
    pentecost_monday = easter_date + datetime.timedelta(days=50)
    
    return {
        (good_friday.month, good_friday.day): ("Nagypéntek", RED),
        (easter_date.month, easter_date.day): ("Húsvét vasárnap", RED),
        (easter_monday.month, easter_monday.day): ("Húsvét hétfő", RED),
        (pentecost.month, pentecost.day): ("Pünkösd vasárnap", RED),
        (pentecost_monday.month, pentecost_monday.day): ("Pünkösd hétfő", RED)
    }

# Az aktuális dátum ellenőrzése, hogy ünnepnap vagy jeles nap-e
def check_special_day(date):
    year = date.year
    month = date.month
    day = date.day
    
    # Mozgó ünnepek lekérése az adott évre
    moving_holidays = get_moving_holidays(year)
    
    # Rögzített ünnepek ellenőrzése
    if (month, day) in FIXED_HOLIDAYS:
        return FIXED_HOLIDAYS[(month, day)]
    
    # Mozgó ünnepek ellenőrzése
    if (month, day) in moving_holidays:
        return moving_holidays[(month, day)]
    
    # Jeles napok ellenőrzése
    if (month, day) in NOTABLE_DAYS:
        return NOTABLE_DAYS[(month, day)]
    
    return None

# Az aktuális névnap lekérése
def get_nameday(date):
    month = date.month
    day = date.day
    
    namedays = get_hungarian_namedays()
    
    if (month, day) in namedays:
        return namedays[(month, day)]
    
    return "Ismeretlen"

# Aktív meteorrajok ellenőrzése
def check_meteor_showers(date):
    month = date.month
    day = date.day
    
    meteor_showers = get_meteor_showers()
    active_showers = []
    
    for shower in meteor_showers:
        start_month, start_day = shower["start"]
        peak_month, peak_day = shower["peak"]
        end_month, end_day = shower["end"]
        
        # Ellenőrizzük, hogy a dátum a meteorraj időszakban van-e
        if (month > start_month or (month == start_month and day >= start_day)) and \
           (month < end_month or (month == end_month and day <= end_day)):
            
            # Ellenőrizzük, hogy a csúcs napon vagyunk-e
            is_peak = (month == peak_month and day == peak_day)
            
            active_showers.append({
                "name": shower["name"],
                "is_peak": is_peak
            })
    
    return active_showers

# Időformázás
def format_time(dt):
    if dt is None:
        return "Nem kel/nyugszik"
    return dt.strftime("%H:%M")

# RSS feed lekérése
def get_rss_feed():
    try:
        logger.info("RSS hírcsatorna lekérése a Telex.hu-ról...")
        feed = feedparser.parse(RSS_URL)
        
        # Az első 3 bejegyzés lekérése
        entries = []
        for i, entry in enumerate(feed.entries[:3]):
            title = entry.title
            entries.append(title)
            logger.info(f"RSS bejegyzés {i+1}: {title[:50]}...")
        
        return entries
    except Exception as e:
        logger.error(f"HIBA az RSS lekérésénél: {e}")
        logger.error(traceback.format_exc())
        return ["RSS hiba: Nem sikerült betölteni a híreket."]

# Időjárás adatok lekérése az OpenWeatherMap API-tól
def get_weather_data():
    if not OPENWEATHERMAP_API_KEY:
        logger.warning("OpenWeatherMap API kulcs nincs beállítva, az időjárás adatok nem lesznek elérhetőek.")
        return None
    
    try:
        logger.info(f"Időjárási adatok lekérése {CITY} városra...")
        url = f"https://api.openweathermap.org/data/2.5/weather?q={CITY}&appid={OPENWEATHERMAP_API_KEY}&units=metric&lang=hu"
        response = requests.get(url)
        
        if response.status_code == 200:
            weather_data = response.json()
            
            # Adatok kivonatolása
            temperature = weather_data["main"]["temp"]
            feels_like = weather_data["main"]["feels_like"]
            humidity = weather_data["main"]["humidity"]
            pressure = weather_data["main"]["pressure"]
            weather_desc = weather_data["weather"][0]["description"]
            weather_icon = weather_data["weather"][0]["icon"]
            wind_speed = weather_data["wind"]["speed"] * 3.6  # m/s to km/h
            
            # További adatok kinyerése, ha rendelkezésre állnak
            sunrise = datetime.datetime.fromtimestamp(weather_data["sys"]["sunrise"]) if "sunrise" in weather_data["sys"] else None
            sunset = datetime.datetime.fromtimestamp(weather_data["sys"]["sunset"]) if "sunset" in weather_data["sys"] else None
            
            # Környező órák előrejelzése
            weather_by_hour = None
            
            # Adatok visszaadása
            return {
                "temperature": temperature,
                "feels_like": feels_like,
                "humidity": humidity,
                "pressure": pressure,
                "description": weather_desc,
                "icon": weather_icon,
                "wind_speed": wind_speed,
                "sunrise": sunrise,
                "sunset": sunset,
                "hourly": weather_by_hour
            }
        else:
            logger.error(f"Hiba az időjárási adatok lekérésekor: {response.status_code} - {response.text}")
            return None
    except Exception as e:
        logger.error(f"Kivétel az időjárási adatok lekérésekor: {e}")
        logger.error(traceback.format_exc())
        return None

# Lekerekített sarkú téglalap rajzolása
def draw_rounded_rectangle(draw, xy, corner_radius, fill=None, outline=None, width=1):
    # Koordináták kibontása
    x1, y1, x2, y2 = xy
    
    # Sarok pozíciók
    r = corner_radius
    
    # A téglalap 4 sarkát rajzoljuk meg
    draw.ellipse((x1, y1, x1 + 2*r, y1 + 2*r), fill=fill, outline=outline, width=width)  # bal felső
    draw.ellipse((x2 - 2*r, y1, x2, y1 + 2*r), fill=fill, outline=outline, width=width)  # jobb felső
    draw.ellipse((x1, y2 - 2*r, x1 + 2*r, y2), fill=fill, outline=outline, width=width)  # bal alsó
    draw.ellipse((x2 - 2*r, y2 - 2*r, x2, y2), fill=fill, outline=outline, width=width)  # jobb alsó
    
    # A téglalap négy részét rajzoljuk meg a sarkok között
    draw.rectangle((x1 + r, y1, x2 - r, y1 + r), fill=fill, outline=None)  # felső
    draw.rectangle((x1 + r, y2 - r, x2 - r, y2), fill=fill, outline=None)  # alsó
    draw.rectangle((x1, y1 + r, x1 + r, y2 - r), fill=fill, outline=None)  # bal
    draw.rectangle((x2 - r, y1 + r, x2, y2 - r), fill=fill, outline=None)  # jobb
    
    # Középső rész
    draw.rectangle((x1 + r, y1 + r, x2 - r, y2 - r), fill=fill, outline=None)
    
    # Keret (ha van)
    if outline and width > 0:
        # Vonalak rajzolása a négy oldalon
        draw.line([(x1 + r, y1), (x2 - r, y1)], fill=outline, width=width)  # felső
        draw.line([(x1 + r, y2), (x2 - r, y2)], fill=outline, width=width)  # alsó
        draw.line([(x1, y1 + r), (x1, y2 - r)], fill=outline, width=width)  # bal
        draw.line([(x2, y1 + r), (x2, y2 - r)], fill=outline, width=width)  # jobb

# Szöveg elhelyezése adott területen belül, szükség esetén sortöréssel
def draw_text_in_area(draw, text, area, font, fill, align="left", valign="top", max_lines=None):
    x1, y1, x2, y2 = area
    width = x2 - x1
    height = y2 - y1
    line_height = font.getbbox("Ag")[3] + 2  # Sormagasság
    
    # Szöveg tördelése
    lines = []
    words = text.split(' ')
    current_line = words[0]
    
    for word in words[1:]:
        test_line = current_line + ' ' + word
        # Ellenőrizzük, hogy belefér-e a szöveg a szélességbe
        text_width = font.getbbox(test_line)[2]
        if text_width <= width:
            current_line = test_line
        else:
            lines.append(current_line)
            current_line = word
    
    lines.append(current_line)
    
    # Ellenőrizzük, hogy nem túl sok sor van-e
    if max_lines is not None and len(lines) > max_lines:
        lines = lines[:max_lines]
        # Utolsó sor végére három pontot teszünk, ha csonkoltuk a szöveget
        if len(lines) == max_lines:
            lines[-1] = lines[-1][:len(lines[-1])-3] + "..."
    
    # Szöveg függőleges pozíciójának számítása
    total_text_height = len(lines) * line_height
    if valign == "top":
        y = y1
    elif valign == "middle":
        y = y1 + (height - total_text_height) // 2
    else:  # "bottom"
        y = y2 - total_text_height
    
    # Sorok kirajzolása
    for line in lines:
        text_width = font.getbbox(line)[2]
        if align == "left":
            x = x1
        elif align == "center":
            x = x1 + (width - text_width) // 2
        else:  # "right"
            x = x2 - text_width
        
        draw.text((x, y), line, font=font, fill=fill)
        y += line_height
    
    return y  # Visszaadjuk az utolsó sor utáni y koordinátát

# Waveshare e-Paper kijelző kezelése
def initialize_epaper():
    try:
        logger.info("Waveshare e-Paper modul inicializálása...")
        # A Waveshare könyvtár elérési útja
        current_dir = os.path.dirname(os.path.realpath(__file__))
        lib_path = os.path.join(current_dir, 'e-Paper/RaspberryPi_JetsonNano/python/lib')
        sys.path.append(lib_path)
        
        # Importálás megkísérlése
        try:
            from waveshare_epd import epd4in01f
            logger.info("epd4in01f modul importálva")
            epd = epd4in01f.EPD()
            return epd
        except ImportError:
            logger.warning("epd4in01f modul nem található, alternatív modulok keresése...")
            
            # Alternatív modulok keresése
            waveshare_dir = os.path.join(lib_path, 'waveshare_epd')
            if os.path.exists(waveshare_dir):
                for file in os.listdir(waveshare_dir):
                    if file.startswith('epd') and file.endswith('.py') and ('4' in file or 'f' in file):
                        module_name = file[:-3]  # .py nélkül
                        logger.info(f"Alternatív modul próbálása: {module_name}")
                        try:
                            # Dinamikus import
                            import importlib
                            waveshare_epd = importlib.import_module('waveshare_epd')
                            epd_module = getattr(waveshare_epd, module_name)
                            epd = epd_module.EPD()
                            logger.info(f"Sikeresen importálva: {module_name}")
                            return epd
                        except Exception as e:
                            logger.error(f"Hiba az alternatív modul importálásakor: {e}")
                
                logger.error("Nem sikerült importálni egyetlen e-Paper modult sem")
                return None
            else:
                logger.error("Waveshare könyvtár nem található")
                return None
    except Exception as e:
        logger.error(f"Hiba az e-Paper kijelző inicializálása közben: {e}")
        logger.error(traceback.format_exc())
        return None

# Időjárás ikon betöltése
def load_weather_icon(icon_code):
    try:
        current_dir = os.path.dirname(os.path.realpath(__file__))
        icon_path = os.path.join(current_dir, f"icons/{icon_code}.png")
        
        if os.path.exists(icon_path):
            return Image.open(icon_path)
        else:
            # Fallback az alapértelmezett ikonra
            fallback_path = os.path.join(current_dir, "icons/01d.png")
            if os.path.exists(fallback_path):
                return Image.open(fallback_path)
            else:
                logger.error(f"Nincs elérhető időjárás ikon: {icon_code}.png")
                return None
    except Exception as e:
        logger.error(f"Hiba az időjárás ikon betöltésekor: {e}")
        return None

# Naptár információk megjelenítése
def update_display():
    epd = None
    try:
        logger.info("Naptár megjelenítése kezdődik...")
        
        # E-Paper kijelző inicializálása a Waveshare könyvtárral
        epd = initialize_epaper()
        if epd is None:
            logger.error("Nem sikerült inicializálni a kijelzőt")
            return False
        
        logger.info("Kijelző inicializálása...")
        epd.init()
        logger.info("Kijelző inicializálva")
        
        width = epd.width
        height = epd.height
        logger.info(f"Kijelző méretei: {width}x{height}")
        
        # Aktuális dátum és idő lekérése
        now = datetime.datetime.now()
        date_str = now.strftime("%Y. %m. %d.")
        day_str = now.strftime("%A")
        time_str = now.strftime("%H:%M")
        
        # Magyar hónapnevek és napok
        hungarian_days = ["Hétfő", "Kedd", "Szerda", "Csütörtök", "Péntek", "Szombat", "Vasárnap"]
        hungarian_months = ["január", "február", "március", "április", "május", "június", 
                            "július", "augusztus", "szeptember", "október", "november", "december"]
        
        day_of_week = now.weekday()
        month = now.month - 1  # 0-tól indexelve
        
        hu_day = hungarian_days[day_of_week]
        hu_month = hungarian_months[month]
        hu_date = f"{now.year}. {hu_month} {now.day}."
        
        # Betűtípus beállítása
        font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
        regular_font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
        
        if not os.path.exists(font_path):
            font_path = "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf"
            regular_font_path = "/usr/share/fonts/truetype/freefont/FreeSans.ttf"
        
        if os.path.exists(font_path) and os.path.exists(regular_font_path):
            header_font = ImageFont.truetype(font_path, 24)
            title_font = ImageFont.truetype(font_path, 22)
            large_font = ImageFont.truetype(font_path, 32)
            date_font = ImageFont.truetype(font_path, 20)
            main_font = ImageFont.truetype(regular_font_path, 18)
            small_font = ImageFont.truetype(regular_font_path, 14)
        else:
            logger.warning("Nem találhatók a betűtípusok, alapértelmezett használata")
            header_font = ImageFont.load_default()
            title_font = header_font
            large_font = header_font
            date_font = header_font
            main_font = header_font
            small_font = header_font
        
        # Üres kép létrehozása
        image = Image.new('RGB', (width, height), LIGHT_BG)
        draw = ImageDraw.Draw(image)
        
        # Ellenőrizzük, hogy a mai nap speciális nap-e
        special_day = check_special_day(now)
        is_holiday = False
        special_day_color = BLACK
        
        if special_day:
            special_day_name, color_code = special_day
            is_holiday = (color_code == RED)
            
            # Színkód konvertálása RGB-re
            if color_code == RED:
                special_day_color = RED
            elif color_code == BLUE:
                special_day_color = BLUE
            elif color_code == GREEN:
                special_day_color = GREEN
            elif color_code == ORANGE:
                special_day_color = ORANGE
            elif color_code == YELLOW:
                special_day_color = YELLOW
        
        # Névnap lekérése
        nameday = get_nameday(now)
        
        # Nap és hold információk
        city = LocationInfo(CITY, COUNTRY, TIMEZONE, LATITUDE, LONGITUDE)
        
        s = sun(city.observer, date=now.date())
        sunrise = s["sunrise"].astimezone(datetime.timezone.utc).astimezone()
        sunset = s["sunset"].astimezone(datetime.timezone.utc).astimezone()
        
        # Hold információk
        try:
            moon_phase_value = moon_phase(now)
            moon_phase_percent = round(moon_phase_value * 100 / 29.53)
        except:
            # Fallback
            moon_phase_percent = 0
        
        moon_phase_text = get_moon_phase_description(moon_phase_percent)
        
        try:
            moonrise_val = moonrise(city.observer, now.date())
            moonset_val = moonset(city.observer, now.date())
            
            if moonrise_val:
                moonrise_val = moonrise_val.astimezone(datetime.timezone.utc).astimezone()
            
            if moonset_val:
                moonset_val = moonset_val.astimezone(datetime.timezone.utc).astimezone()
        except Exception as e:
            logger.error(f"Hiba a holdkelte/holdnyugta számításánál: {e}")
            moonrise_val = None
            moonset_val = None
        
        # Meteorrajok ellenőrzése
        meteor_showers = check_meteor_showers(now)
        
        # RSS hírfolyam lekérése
        rss_entries = get_rss_feed() if SHOW_RSS_NEWS else []
        
        # Időjárás adatok lekérése
        weather_data = get_weather_data() if SHOW_WEATHER else None
        
        # Képernyő elemek rajzolása
        # ------- FEJLÉC --------
        # Fejléc háttér
        draw.rectangle([(0, 0), (width, 55)], fill=HEADER_COLOR)
        
        # Dátum kiírása
        if is_holiday:
            date_color = RED
        else:
            date_color = WHITE
        
        # Nap neve és dátum
        draw.text((20, 5), hu_day, font=date_font, fill=WHITE)
        draw.text((20, 28), hu_date, font=date_font, fill=date_color)
        
        # Idő kiírása nagy méretben
        draw.text((width - 120, 10), time_str, font=large_font, fill=WHITE)
        
        # ------- PANELEK --------
        # Panel méretei
        panel_padding = 10
        panel_spacing = 15
        col_width = (width - 3*panel_padding) // 2
        
        # Bal oldali oszlop y pozíciója
        left_y = 65
        
        # IDŐJÁRÁS PANEL (ha elérhető)
        if weather_data is not None:
            weather_panel_height = 150
            
            # Panel keret
            draw_rounded_rectangle(draw, 
                                  (panel_padding, left_y, 
                                   panel_padding + col_width, left_y + weather_panel_height), 
                                  corner_radius=10,
                                  fill=PANEL_BG,
                                  outline=HEADER_COLOR,
                                  width=2)
            
            # Panel címsor
            draw.text((panel_padding + 15, left_y + 10), "Időjárás", font=title_font, fill=ACCENT_COLOR)
            
            # Időjárás adatok
            temp = round(weather_data["temperature"])
            desc = weather_data["description"].capitalize()
            
            # Időjárás ikon betöltése
            weather_icon = load_weather_icon(weather_data["icon"])
            if weather_icon:
                # Ikon átméretezése
                weather_icon = weather_icon.resize((60, 60), Image.LANCZOS)
                # Ikon elhelyezése
                image.paste(weather_icon, (panel_padding + 15, left_y + 40), weather_icon.convert('RGBA'))
            
            # Hőmérséklet kiírása
            draw.text((panel_padding + 85, left_y + 45), f"{temp}°C", font=large_font, fill=BLACK)
            draw.text((panel_padding + 85, left_y + 80), desc, font=main_font, fill=BLUE)
            
            # További időjárási adatok
            draw.text((panel_padding + 15, left_y + 110), 
                     f"Szél: {round(weather_data['wind_speed'])} km/h  |  Páratartalom: {weather_data['humidity']}%", 
                     font=small_font, fill=GRAY)
            
            left_y += weather_panel_height + panel_spacing
        
        # NAPI INFORMÁCIÓK PANEL
        info_panel_height = 120
        
        # Panel keret
        draw_rounded_rectangle(draw, 
                              (panel_padding, left_y, 
                               panel_padding + col_width, left_y + info_panel_height), 
                              corner_radius=10,
                              fill=PANEL_BG,
                              outline=HEADER_COLOR,
                              width=2)
        
        # Panel címsor
        draw.text((panel_padding + 15, left_y + 10), "Napi információk", font=title_font, fill=ACCENT_COLOR)
        
        # Speciális nap kiírása, ha van
        info_y = left_y + 45
        if special_day:
            special_day_name, _ = special_day
            draw.text((panel_padding + 20, info_y), f"Mai nap: {special_day_name}", font=main_font, fill=special_day_color)
            info_y += 30
        
        # Névnap kiírása
        draw.text((panel_padding + 20, info_y), f"Névnap: {nameday}", font=main_font, fill=BLUE)
        
        left_y += info_panel_height + panel_spacing
        
        # NAPKELTE/NAPNYUGTA PANEL
        sun_panel_height = 130
        
        # Panel keret
        draw_rounded_rectangle(draw, 
                              (panel_padding, left_y, 
                               panel_padding + col_width, left_y + sun_panel_height), 
                              corner_radius=10,
                              fill=PANEL_BG,
                              outline=HEADER_COLOR,
                              width=2)
        
        # Panel címsor
        draw.text((panel_padding + 15, left_y + 10), "Nap és Hold", font=title_font, fill=ACCENT_COLOR)
        
        # Napkelte és napnyugta információk
        sunrise_str = format_time(sunrise)
        sunset_str = format_time(sunset)
        
        # Rajzolj napot és holdat grafikusan
        # Nap
        sun_x = panel_padding + 50
        sun_y = left_y + 50
        draw.ellipse((sun_x-15, sun_y-15, sun_x+15, sun_y+15), fill=YELLOW, outline=ORANGE, width=2)
        
        # Sugarak a nap körül
        for i in range(8):
            angle = i * 45 * math.pi / 180  # Radián
            outer_x = sun_x + 24 * math.sin(angle)
            outer_y = sun_y - 24 * math.cos(angle)
            inner_x = sun_x + 18 * math.sin(angle)
            inner_y = sun_y - 18 * math.cos(angle)
            draw.line([(int(inner_x), int(inner_y)), (int(outer_x), int(outer_y))], fill=YELLOW, width=2)
        
        draw.text((sun_x + 25, sun_y - 10), f"↑ {sunrise_str}", font=main_font, fill=BLACK)
        draw.text((sun_x + 25, sun_y + 10), f"↓ {sunset_str}", font=main_font, fill=BLACK)
        
        # Hold
        moon_y = left_y + 95
        draw.ellipse((sun_x-12, moon_y-12, sun_x+12, moon_y+12), fill=(220, 220, 220), outline=(180, 180, 180), width=2)
        
        # Holdfázis árnyékolás
        if moon_phase_percent < 50:
            # Növekvő hold - jobb oldal világos
            shade_width = int(24 * (50 - moon_phase_percent) / 50)
            draw.ellipse((sun_x-12, moon_y-12, sun_x+12, moon_y+12), fill=(220, 220, 220))
            draw.rectangle((sun_x-12, moon_y-12, sun_x-12+shade_width, moon_y+12), fill=(100, 100, 100))
            draw.ellipse((sun_x-12, moon_y-12, sun_x+12, moon_y+12), outline=(180, 180, 180), width=1)
        else:
            # Fogyó hold - bal oldal világos
            shade_width = int(24 * (moon_phase_percent - 50) / 50)
            draw.ellipse((sun_x-12, moon_y-12, sun_x+12, moon_y+12), fill=(220, 220, 220))
            draw.rectangle((sun_x+12-shade_width, moon_y-12, sun_x+12, moon_y+12), fill=(100, 100, 100))
            draw.ellipse((sun_x-12, moon_y-12, sun_x+12, moon_y+12), outline=(180, 180, 180), width=1)
        
        # Holdkelte és holdnyugta információk
        moonrise_str = format_time(moonrise_val)
        moonset_str = format_time(moonset_val)
        
        draw.text((sun_x + 25, moon_y - 10), f"↑ {moonrise_str}", font=main_font, fill=BLACK)
        draw.text((sun_x + 25, moon_y + 10), f"↓ {moonset_str}", font=main_font, fill=BLACK)
        
        # Jobb oldali oszlop y pozíciója
        right_x = panel_padding * 2 + col_width
        right_y = 65
        
        # METEORRAJ PANEL
        if SHOW_METEORS and meteor_showers:
            meteor_panel_height = 120 if len(meteor_showers) > 1 else 90
            
            # Panel keret
            draw_rounded_rectangle(draw, 
                                  (right_x, right_y, 
                                   right_x + col_width, right_y + meteor_panel_height), 
                                  corner_radius=10,
                                  fill=PANEL_BG,
                                  outline=HEADER_COLOR,
                                  width=2)
            
            # Panel címsor
            draw.text((right_x + 15, right_y + 10), "Aktív meteorrajok", font=title_font, fill=ACCENT_COLOR)
            
            # Meteor információk kiírása
            meteor_y = right_y + 45
            for shower in meteor_showers:
                name = shower["name"]
                is_peak = shower["is_peak"]
                
                text = f"• {name}"
                if is_peak:
                    text += " (csúcs)"
                
                draw.text((right_x + 20, meteor_y), text, font=main_font, fill=(100, 0, 150))
                meteor_y += 25
            
            right_y += meteor_panel_height + panel_spacing
        
        # RSS HÍREK PANEL
        if SHOW_RSS_NEWS and rss_entries:
            # Számítsuk ki a fennmaradó helyet
            available_height = height - right_y - 20
            
            # Panel keret
            draw_rounded_rectangle(draw, 
                                  (right_x, right_y, 
                                   right_x + col_width, height - 20), 
                                  corner_radius=10,
                                  fill=PANEL_BG,
                                  outline=HEADER_COLOR,
                                  width=2)
            
            # Panel címsor
            draw.text((right_x + 15, right_y + 10), "Hírek (Telex.hu)", font=title_font, fill=ACCENT_COLOR)
            
            # RSS hírek kiírása
            news_y = right_y + 45
            for i, entry in enumerate(rss_entries):
                # Szöveg hosszának korlátozása
                max_lines = 2
                area = (right_x + 15, news_y, right_x + col_width - 15, news_y + 60)
                end_y = draw_text_in_area(draw, entry, area, small_font, BLACK, max_lines=max_lines)
                news_y = end_y + 10
                
                # Vonal az egyes hírek között
                if i < len(rss_entries) - 1:
                    draw.line([(right_x + 40, news_y - 5), (right_x + col_width - 40, news_y - 5)], 
                             fill=LIGHT_GRAY, width=1)
        
        # HOLDFÁZIS PANEL (ha nincs a RSS panel mellett)
        elif SHOW_MOON_PHASE and not meteor_showers:
            moon_panel_height = 100
            
            # Panel keret
            draw_rounded_rectangle(draw, 
                                  (right_x, right_y, 
                                   right_x + col_width, right_y + moon_panel_height), 
                                  corner_radius=10,
                                  fill=PANEL_BG,
                                  outline=HEADER_COLOR,
                                  width=2)
            
            # Panel címsor
            draw.text((right_x + 15, right_y + 10), "Holdfázis", font=title_font, fill=ACCENT_COLOR)
            
            # Hold fázis kiírása
            draw.text((right_x + 20, right_y + 50), 
                     f"Hold fázis: {moon_phase_percent}% ({moon_phase_text})", 
                     font=main_font, fill=BLUE)
        
        # Utolsó frissítés ideje legalul
        updated_str = f"Frissítve: {now.strftime('%Y-%m-%d %H:%M')}"
        draw.text((width - 150, height - 15), updated_str, font=small_font, fill=GRAY)
        
        # Képernyőkép mentése (debug)
        image_path = os.path.expanduser("~/epaper_calendar_latest.png")
        image.save(image_path)
        logger.info(f"Képernyőkép elmentve: {image_path}")
        
        # Kép megjelenítése a kijelzőn
        logger.info("Kép küldése a kijelzőre...")
        epd.display(epd.getbuffer(image))
        logger.info("Kép sikeresen megjelenítve a kijelzőn")
        
        # Kijelző alvó módba helyezése
        logger.info("Kijelző alvó módba helyezése...")
        epd.sleep()
        
        logger.info("Naptár sikeresen megjelenítve a kijelzőn")
        return True
    except Exception as e:
        logger.error(f"HIBA a naptár megjelenítésekor: {e}")
        logger.error(traceback.format_exc())
        return False
    finally:
        # Biztosítsuk, hogy az erőforrások felszabadulnak
        if epd is not None:
            try:
                # Már lehet, hogy meghívtuk a sleep()-et, de jobb biztosra menni
                epd.sleep()
            except:
                pass

def main():
    try:
        logger.info("E-Paper Naptár alkalmazás indítása")
        
        # Kezdeti frissítés
        if not update_display():
            logger.error("Nem sikerült a kijelző kezdeti frissítése, újrapróbálkozás 10 másodperc múlva...")
            time.sleep(10)
            if not update_display():
                logger.error("Ismételt hiba a kijelző frissítésekor, leállás.")
                return
        
        # Fő ciklus - konfigurálható frissítési gyakoriság
        while True:
            logger.info(f"Várakozás {REFRESH_INTERVAL} percig a következő frissítésig...")
            time.sleep(REFRESH_INTERVAL * 60)  # Percek -> másodpercek
            
            # Kijelző frissítése, hiba esetén újrapróbálkozás
            if not update_display():
                logger.error("Hiba a kijelző frissítésekor, újrapróbálkozás 30 másodperc múlva...")
                time.sleep(30)
                update_display()
            
    except KeyboardInterrupt:
        logger.info("Program megszakítva a felhasználó által")
    except Exception as e:
        logger.error(f"Váratlan hiba: {e}")
        logger.error(traceback.format_exc())
    finally:
        logger.info("Program leállítva")

if __name__ == "__main__":
    main()
EOL

chmod +x "$PROJECT_DIR/calendar_display.py"

# Systemd szolgáltatás létrehozása
echo "Systemd szolgáltatás létrehozása..."
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

sudo chmod 644 /etc/systemd/system/epaper-calendar.service

# Eltávolító szkript
echo "Eltávolító szkript létrehozása..."
cat > "$PROJECT_DIR/uninstall.sh" << 'EOL'
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
EOL

chmod +x "$PROJECT_DIR/uninstall.sh"

# Végezzük el a kijelző inicializálását
echo "Kijelző inicializálása a Waveshare könyvtár segítségével..."
python3 "$PROJECT_DIR/initialize_display.py"
INIT_RESULT=$?

# Systemd szolgáltatás aktiválása
echo "Systemd szolgáltatás aktiválása..."
sudo systemctl daemon-reload
sudo systemctl enable epaper-calendar.service

# Ha az inicializálás sikeres volt, indítsuk el a naptár programot
if [ $INIT_RESULT -eq 0 ]; then
    echo "A kijelző sikeresen inicializálva. Naptár program indítása..."
    sudo systemctl start epaper-calendar.service
else
    echo "FIGYELMEZTETÉS: A kijelző inicializálása sikertelen volt. A naptár program lehet, hogy nem fog megfelelően működni."
    echo "Ellenőrizd a naplót további részletekért: ~/epaper_init.log"
fi

# Összegzés
echo "========================================================================"
echo "Telepítés kész!"
echo ""
echo "A program két fő részből áll:"
echo "1. initialize_display.py - A Waveshare könyvtárat használja a kijelző kezdeti beállításához"
echo "2. calendar_display.py - Az önálló naptár program, amely szép megjelenítést és időjárási adatokat tartalmaz"
echo ""
echo "Ha az SPI interfész most lett engedélyezve, újraindítás szükséges."
echo ""
echo "Szolgáltatás ellenőrzése:"
echo "sudo systemctl status epaper-calendar.service"
echo ""
echo "Naplófájl megtekintése:"
echo "tail -f ~/epaper_calendar.log"
echo "journalctl -u epaper-calendar.service -f"
echo ""
echo "Kézi futtatás:"
echo "cd $PROJECT_DIR && python3 calendar_display.py"
echo ""
echo "A legutóbbi megjelenítés megtekintése:"
echo "xdg-open ~/epaper_calendar_latest.png"
echo ""
echo "Eltávolításhoz futtasd:"
echo "$PROJECT_DIR/uninstall.sh"
echo "========================================================================"

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
fi

echo "Telepítés sikeresen befejezve. Élvezd a továbbfejlesztett E-Paper naptárt!"
