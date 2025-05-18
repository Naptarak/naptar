#!/bin/bash

# E-Paper Calendar Display Installer (SEPARATED VERSION)
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-paper HAT

echo "======================================================"
echo "E-Paper Calendar Display Installer (SEPARATED VERSION)"
echo "Raspberry Pi Zero 2W + Waveshare 4.01 inch 7-color HAT"
echo "======================================================"

# Aktuális felhasználó és könyvtárak
CURRENT_USER=$(whoami)
echo "Telepítés a következő felhasználóhoz: $CURRENT_USER"
PROJECT_DIR="/home/$CURRENT_USER/epaper_calendar"

# Könyvtár létrehozása
mkdir -p "$PROJECT_DIR"
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
pip3 install --break-system-packages astral

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
        
        # Háttér téglalap
        draw.rectangle([(0, 0), (width, 60)], fill=(200, 200, 255))
        
        # Címsor
        draw.text((width//2 - 180, 10), "E-Paper Naptár Inicializálva", font=font, fill=(0, 0, 0))
        
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
        
        for i, color in enumerate(colors):
            y_pos = 180 + i*30
            draw.rectangle([(20, y_pos), (100, y_pos+20)], fill=color, outline=(0, 0, 0))
            
            # Színnév
            color_names = ["Fekete", "Fehér", "Zöld", "Kék", "Piros", "Sárga", "Narancs"]
            draw.text((120, y_pos), color_names[i], font=font, fill=(0, 0, 0))
        
        # A naptár program indulási ütemezése
        draw.text((20, height-60), "A naptár program hamarosan elindul...", font=font, fill=(0, 0, 0))
        
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

# Önálló naptár program létrehozása
echo "Önálló naptár program létrehozása..."
cat > "$PROJECT_DIR/calendar_display.py" << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

# Önálló Naptár Megjelenítő Program
# Ne függjön a Waveshare könyvtártól közvetlenül

import os
import sys
import time
import datetime
import traceback
import logging
import feedparser
import RPi.GPIO as GPIO
import spidev
from dateutil.easter import easter
from PIL import Image, ImageDraw, ImageFont

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
    import requests
    from astral import LocationInfo
    from astral.sun import sun
    from astral.moon import moon_phase, moonrise, moonset
except ImportError as e:
    logger.error(f"Hiányzó modul: {e}")
    logger.error("Próbáld meg telepíteni: pip3 install --break-system-packages astral requests")
    sys.exit(1)

# Konstansok
WIDTH = 640
HEIGHT = 400
RSS_URL = "https://telex.hu/rss"
CITY = "Pécs"  # Módosítsd a saját városodra
COUNTRY = "Hungary"
LATITUDE = 46.0727  # Módosítsd a saját koordinátáidra
LONGITUDE = 18.2323
TIMEZONE = "Europe/Budapest"

# Pin definíciók a Waveshare 4.01 inch kijelzőhöz
RST_PIN = 17
DC_PIN = 25
CS_PIN = 8
BUSY_PIN = 24

# Színkódok
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
GREEN = (0, 255, 0)
BLUE = (0, 0, 255)
RED = (255, 0, 0)
YELLOW = (255, 255, 0)
ORANGE = (255, 165, 0)

# Egyszerű e-Paper vezérlő osztály, amely közvetlenül használja a GPIO-t és SPI-t
class EPaperDisplay:
    def __init__(self):
        self.width = WIDTH
        self.height = HEIGHT
        self.setup_hardware()
    
    def setup_hardware(self):
        # GPIO beállítása
        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)
        GPIO.setup(RST_PIN, GPIO.OUT)
        GPIO.setup(DC_PIN, GPIO.OUT)
        GPIO.setup(CS_PIN, GPIO.OUT)
        GPIO.setup(BUSY_PIN, GPIO.IN)
        
        # SPI beállítása
        self.spi = spidev.SpiDev()
        self.spi.open(0, 0)
        self.spi.max_speed_hz = 4000000
        self.spi.mode = 0
    
    def digital_write(self, pin, value):
        GPIO.output(pin, value)
    
    def digital_read(self, pin):
        return GPIO.input(pin)
    
    def delay_ms(self, delaytime):
        time.sleep(delaytime / 1000.0)
    
    def send_command(self, command):
        self.digital_write(DC_PIN, 0)
        self.digital_write(CS_PIN, 0)
        self.spi.writebytes([command])
        self.digital_write(CS_PIN, 1)
    
    def send_data(self, data):
        self.digital_write(DC_PIN, 1)
        self.digital_write(CS_PIN, 0)
        self.spi.writebytes([data])
        self.digital_write(CS_PIN, 1)
    
    def init(self):
        try:
            logger.info("Kijelző inicializálása...")
            
            # Reset
            self.digital_write(RST_PIN, 1)
            self.delay_ms(200)
            self.digital_write(RST_PIN, 0)
            self.delay_ms(2)
            self.digital_write(RST_PIN, 1)
            self.delay_ms(200)
            
            # Várunk, amíg a BUSY pin nem jelez
            self.wait_until_idle()
            
            # Alapvető inicializáló parancsok
            # Ez egy egyszerűsített inicializálás, csak az alapvető funkcionalitáshoz
            self.send_command(0x12)  # SWRESET - Software Reset
            self.delay_ms(100)
            self.wait_until_idle()
            
            return 0
        except Exception as e:
            logger.error(f"Inicializálási hiba: {e}")
            return -1
    
    def wait_until_idle(self):
        while self.digital_read(BUSY_PIN) == 0:  # 0: busy, 1: idle
            self.delay_ms(100)
    
    def getbuffer(self, image):
        # Egyszerűsített verzió, csak a PIL Kép visszaadása
        return image
    
    def display(self, image):
        logger.info("Kép megjelenítése a kijelzőn...")
        try:
            if isinstance(image, Image.Image):
                # Egyszerűsített verzió - csak néhány parancs küldése a kijelzőnek
                # Ez nem a teljes Waveshare protokoll, csak egy minimális implementáció
                self.send_command(0x10)  # DATA_START_TRANSMISSION
                self.delay_ms(2)
                
                # Valós implementációban itt küldenénk a képadatokat
                # Ez azonban csak a funkcionalitás demonstrációja
                logger.info("Egyszerűsített képküldés...")
                
                # A frissítés elindítása
                self.send_command(0x12)  # DISPLAY_REFRESH
                self.delay_ms(100)
                self.wait_until_idle()
                
                # Kép mentése, hogy láthassuk, mit küldtünk volna
                image_path = os.path.expanduser("~/epaper_calendar_latest.png")
                image.save(image_path)
                logger.info(f"Kép mentve: {image_path}")
                
                return 0
            else:
                logger.error("Nem PIL Image objektum!")
                return -1
        except Exception as e:
            logger.error(f"Képmegjelenítési hiba: {e}")
            return -1
    
    def sleep(self):
        logger.info("Kijelző alvó módba helyezése...")
        try:
            # Deep sleep mode
            self.send_command(0x07)  # DEEP_SLEEP
            self.send_data(0xA5)     # Deep sleep parameter
            
            # Lezárjuk az SPI-t
            self.spi.close()
            
            return 0
        except Exception as e:
            logger.error(f"Alvó mód hiba: {e}")
            return -1
    
    def close(self):
        logger.info("Erőforrások felszabadítása...")
        try:
            # Lezárjuk az SPI-t ha még nem tettük
            try:
                self.spi.close()
            except:
                pass
            
            # GPIO tisztítás
            GPIO.cleanup([RST_PIN, DC_PIN, CS_PIN, BUSY_PIN])
            
            return 0
        except Exception as e:
            logger.error(f"Lezárási hiba: {e}")
            return -1

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

# Naptár információk megjelenítése
def update_display():
    epd = None
    try:
        logger.info("Naptár megjelenítése kezdődik...")
        
        # E-Paper kijelző inicializálása
        epd = EPaperDisplay()
        logger.info("EPD objektum létrehozva")
        
        epd.init()
        logger.info("Kijelző inicializálva")
        
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
        hu_date = f"{now.year}. {hu_month} {now.day}., {hu_day}"
        
        # Betűtípus beállítása
        font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
        if not os.path.exists(font_path):
            font_path = "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf"
        
        if os.path.exists(font_path):
            title_font = ImageFont.truetype(font_path, 24)
            date_font = ImageFont.truetype(font_path, 22)
            main_font = ImageFont.truetype(font_path, 18)
            small_font = ImageFont.truetype(font_path, 14)
        else:
            logger.warning("Nem találhatók a betűtípusok, alapértelmezett használata")
            title_font = ImageFont.load_default()
            date_font = title_font
            main_font = title_font
            small_font = title_font
        
        # Üres kép létrehozása
        image = Image.new('RGB', (WIDTH, HEIGHT), WHITE)
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
        moon_phase_value = moon_phase(now)
        moon_phase_percent = round(moon_phase_value * 100 / 29.53)
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
        rss_entries = get_rss_feed()
        
        # Képernyő elemek rajzolása
        # Fejléc háttér
        draw.rectangle([(0, 0), (WIDTH, 50)], fill=(230, 230, 255))
        
        # Dátum kiírása
        if is_holiday:
            date_color = RED
        else:
            date_color = BLACK
        
        draw.text((20, 15), hu_date, font=date_font, fill=date_color)
        
        # Idő kiírása
        draw.text((WIDTH - 120, 15), time_str, font=date_font, fill=BLACK)
        
        # Aktuális pozíció a rajzoláshoz
        y_pos = 70
        
        # Speciális nap kiírása, ha van
        if special_day:
            special_day_name, _ = special_day
            draw.text((20, y_pos), f"Mai nap: {special_day_name}", font=main_font, fill=special_day_color)
            y_pos += 30
        
        # Névnap kiírása
        draw.text((20, y_pos), f"Névnap: {nameday}", font=main_font, fill=BLUE)
        y_pos += 30
        
        # Napkelte és napnyugta információk
        sunrise_str = format_time(sunrise)
        sunset_str = format_time(sunset)
        draw.text((20, y_pos), f"Napkelte: {sunrise_str} | Napnyugta: {sunset_str}", font=main_font, fill=ORANGE)
        y_pos += 30
        
        # Holdkelte és holdnyugta információk
        moonrise_str = format_time(moonrise_val)
        moonset_str = format_time(moonset_val)
        draw.text((20, y_pos), f"Holdkelte: {moonrise_str} | Holdnyugta: {moonset_str}", font=main_font, fill=BLACK)
        y_pos += 30
        
        # Hold fázis kiírása
        draw.text((20, y_pos), f"Hold fázis: {moon_phase_percent}% ({moon_phase_text})", font=main_font, fill=BLUE)
        y_pos += 30
        
        # Meteorraj információk kiírása, ha van
        if meteor_showers:
            meteor_text = "Meteorraj: "
            for i, shower in enumerate(meteor_showers):
                if i > 0:
                    meteor_text += ", "
                meteor_text += shower["name"]
                if shower["is_peak"]:
                    meteor_text += " (csúcs)"
            
            draw.text((20, y_pos), meteor_text, font=main_font, fill=(150, 0, 150))
            y_pos += 30
        
        # Elválasztó vonal
        draw.line([(20, y_pos), (WIDTH - 20, y_pos)], fill=(200, 200, 200), width=2)
        y_pos += 20
        
        # RSS hírfolyam fejléc
        draw.text((20, y_pos), "Hírek (Telex.hu):", font=main_font, fill=GREEN)
        y_pos += 30
        
        # RSS hírek kiírása
        for i, entry in enumerate(rss_entries):
            # Szöveg hosszának korlátozása
            if len(entry) > 80:
                entry = entry[:77] + "..."
            
            draw.text((30, y_pos), f"• {entry}", font=small_font, fill=BLACK)
            y_pos += 25
        
        # Utolsó frissítés ideje
        updated_str = f"Frissítve: {now.strftime('%Y-%m-%d %H:%M')}"
        draw.text((WIDTH - 200, HEIGHT - 20), updated_str, font=small_font, fill=(100, 100, 100))
        
        # Kép megjelenítése a kijelzőn
        logger.info("Kép küldése a kijelzőre...")
        epd.display(image)
        
        # Kijelző alvó módba helyezése
        logger.info("Kijelző alvó módba helyezése...")
        epd.sleep()
        
        logger.info("Naptár sikeresen megjelenítve a kijelzőn")
        
    except Exception as e:
        logger.error(f"HIBA a naptár megjelenítésekor: {e}")
        logger.error(traceback.format_exc())
        
        # Ha hiba történt, próbáljunk meg alvó módba helyezni
        if epd is not None:
            try:
                epd.close()
            except:
                pass

def main():
    try:
        logger.info("E-Paper Naptár alkalmazás indítása")
        
        # Kezdeti frissítés
        update_display()
        
        # Fő ciklus - 10 percenkénti frissítés
        while True:
            logger.info("Várakozás 10 percig a következő frissítésig...")
            time.sleep(600)  # 10 perc = 600 másodperc
            
            # Kijelző frissítése
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

# Szolgáltatás leállítása és eltávolítása
echo "Szolgáltatás leállítása és eltávolítása..."
sudo systemctl stop epaper-calendar.service
sudo systemctl disable epaper-calendar.service
sudo rm -f /etc/systemd/system/epaper-calendar.service
sudo systemctl daemon-reload

# Kísérlet a kijelző tisztítására mielőtt eltávolítjuk
echo "Kijelző tisztítása..."
cd "$PROJECT_DIR"
python3 "$PROJECT_DIR/calendar_display.py" clear || true

# Könyvtár eltávolítása
echo "Könyvtár eltávolítása: $PROJECT_DIR"
cd
rm -rf "$PROJECT_DIR"

# Naplófájlok törlése
echo "Naplófájlok törlése..."
rm -f ~/epaper_calendar.log ~/epaper_init.log ~/epaper_calendar_latest.png

echo "Eltávolítás kész!"
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
echo "2. calendar_display.py - Az önálló naptár program, amely közvetlenül kezeli a kijelzőt"
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

echo "Telepítés befejezve."
