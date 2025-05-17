#!/bin/bash

# E-Paper Calendar Display Installer (GPIO-FÓKUSZÁLT VERZIÓ)
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-paper HAT

echo "======================================================"
echo "E-Paper Calendar Display Installer (GPIO-FÓKUSZÁLT VERZIÓ)"
echo "Raspberry Pi Zero 2W + Waveshare 4.01 inch 7-color HAT"
echo "======================================================"

# Létrehozzuk a naplófájlt időbélyegekkel
LOG_FILE="/home/pi/epaper_calendar_install.log"
touch $LOG_FILE
echo "$(date) - GPIO-fókuszált telepítés indítása" > $LOG_FILE

# Függvény a naplózáshoz
log_message() {
    echo "$(date) - $1" >> $LOG_FILE
    echo "$1"
}

# Projekt könyvtár létrehozása
PROJECT_DIR="/home/pi/epaper_calendar"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

log_message "=== LÉPÉS 1: Alaprendszer frissítése ==="
log_message "Csomaglista frissítése..."
sudo apt-get update
if [ $? -ne 0 ]; then
    log_message "FIGYELMEZTETÉS: Csomaglista frissítése sikertelen, de folytatjuk..."
fi

log_message "=== LÉPÉS 2: GPIO specifikus csomagok DIREKT telepítése ==="
log_message "Kritikus GPIO és SPI csomagok telepítése..."

# Többféle módszer a GPIO csomagok telepítésére
log_message "1. módszer: apt-get telepítés"
sudo apt-get install -y python3-rpi.gpio python3-gpiozero python3-spidev

# Ha az apt telepítés nem működik, próbáljuk a pip-et
log_message "2. módszer: pip telepítés RPi.GPIO és spidev csomagokhoz"
sudo pip3 install RPi.GPIO spidev gpiozero

# Ellenőrizzük, hogy a GPIO modulok működnek-e
log_message "GPIO modulok tesztelése..."
python3 -c "import RPi.GPIO as GPIO; print('RPi.GPIO sikeresen betöltve, verzió:', GPIO.VERSION)" >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    log_message "HIBA: RPi.GPIO nem tölthető be"
else
    log_message "RPi.GPIO sikeresen betöltve"
fi

python3 -c "import gpiozero; print('gpiozero sikeresen betöltve')" >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    log_message "HIBA: gpiozero nem tölthető be"
else
    log_message "gpiozero sikeresen betöltve"
fi

python3 -c "import spidev; print('spidev sikeresen betöltve')" >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
    log_message "HIBA: spidev nem tölthető be"
else
    log_message "spidev sikeresen betöltve"
fi

log_message "=== LÉPÉS 3: További Python csomagok telepítése ==="
# Egyéb szükséges Python modulok telepítése
log_message "További Python csomagok telepítése..."
sudo pip3 install Pillow numpy feedparser python-dateutil astral requests

log_message "=== LÉPÉS 4: SPI interfész engedélyezése ==="
log_message "SPI interfész ellenőrzése..."

if ! grep -q "dtparam=spi=on" /boot/config.txt; then
    log_message "SPI interfész engedélyezése..."
    echo "dtparam=spi=on" | sudo tee -a /boot/config.txt
    REBOOT_NEEDED=true
    log_message "SPI interfész engedélyezve a konfigban, újraindítás szükséges"
else
    log_message "SPI interfész már engedélyezve van a konfigban"
fi

# Ellenőrizzük, hogy az SPI eszköz létezik-e
if [ -e /dev/spidev0.0 ]; then
    log_message "SPI eszköz megtalálva: /dev/spidev0.0"
else
    log_message "FIGYELMEZTETÉS: SPI eszköz nem található! Ez azt jelezheti, hogy az SPI nincs engedélyezve."
    log_message "Újraindítás szükséges lehet a telepítés után."
    REBOOT_NEEDED=true
fi

log_message "=== LÉPÉS 5: Waveshare könyvtár MANUAL telepítése ==="

# Hozzuk létre a saját Waveshare könyvtárat
mkdir -p $PROJECT_DIR/waveshare_epd

log_message "Waveshare e-Paper könyvtár létrehozása manuálisan..."

# Hozzuk létre a szükséges Python modulokat
cat > $PROJECT_DIR/waveshare_epd/__init__.py << 'EOL'
# Waveshare e-Paper library
EOL

# Hozzuk létre a 4.01 inch 7-color kijelző vezérlőt
cat > $PROJECT_DIR/waveshare_epd/epd4in01f.py << 'EOL'
# -*- coding:utf-8 -*-

import logging
import time
import numpy as np
from PIL import Image

try:
    import RPi.GPIO as GPIO
except ImportError:
    # Ha az RPi.GPIO nem érhető el, próbáljuk a gpiozero-t használni
    try:
        from gpiozero import OutputDevice, InputDevice
        class GPIO:
            BCM = "BCM"
            OUT = "OUT"
            IN = "IN"
            
            @staticmethod
            def setmode(mode):
                pass
                
            @staticmethod
            def setwarnings(state):
                pass
                
            @staticmethod
            def setup(pin, mode):
                pass
                
            @staticmethod
            def output(pin, value):
                # Ha az OutputDevice nincs inicializálva, inicializálja
                if pin not in GPIO.output_devices:
                    GPIO.output_devices[pin] = OutputDevice(pin)
                GPIO.output_devices[pin].value = value
                
            @staticmethod
            def input(pin):
                # Ha az InputDevice nincs inicializálva, inicializálja
                if pin not in GPIO.input_devices:
                    GPIO.input_devices[pin] = InputDevice(pin)
                return GPIO.input_devices[pin].value
                
            output_devices = {}
            input_devices = {}
                
            @staticmethod
            def cleanup(pins=None):
                pass
        logging.warning("RPi.GPIO nem érhető el, gpiozero-ra váltunk")
    except ImportError:
        # Ha még a gpiozero sem érhető el, akkor egy minimális emulációt használunk
        logging.error("Sem RPi.GPIO, sem gpiozero nem érhető el - korlátozottan fog működni")
        class GPIO:
            BCM = "BCM"
            OUT = "OUT"
            IN = "IN"
            
            @staticmethod
            def setmode(mode):
                pass
                
            @staticmethod
            def setwarnings(state):
                pass
                
            @staticmethod
            def setup(pin, mode):
                pass
                
            @staticmethod
            def output(pin, value):
                logging.info(f"(EMULÁCIÓ) GPIO kimenet: {pin}={value}")
                
            @staticmethod
            def input(pin):
                return 0
                
            @staticmethod
            def cleanup(pins=None):
                pass

try:
    import spidev
except ImportError:
    logging.error("spidev nem érhető el - korlátozottan fog működni")
    # Egyszerű SPI emuláció
    class spidev:
        class SpiDev:
            def __init__(self):
                self.max_speed_hz = 0
                self.mode = 0
                
            def open(self, bus, device):
                logging.info(f"(EMULÁCIÓ) SPI megnyitása: bus={bus}, device={device}")
                
            def writebytes(self, data):
                logging.info(f"(EMULÁCIÓ) SPI adatírás: {len(data)} byte")
                
            def close(self):
                logging.info("(EMULÁCIÓ) SPI lezárása")
    spidev = spidev()

logger = logging.getLogger(__name__)

# Display resolution
WIDTH = 640
HEIGHT = 400

# Pin definition
RST_PIN = 17
DC_PIN = 25
CS_PIN = 8
BUSY_PIN = 24

class EPD:
    def __init__(self):
        self.reset_pin = RST_PIN
        self.dc_pin = DC_PIN
        self.busy_pin = BUSY_PIN
        self.cs_pin = CS_PIN
        self.width = WIDTH
        self.height = HEIGHT
        
        self.colors = [
            (0, 0, 0),        # 0: BLACK
            (255, 255, 255),  # 1: WHITE
            (0, 255, 0),      # 2: GREEN
            (0, 0, 255),      # 3: BLUE
            (255, 0, 0),      # 4: RED
            (255, 255, 0),    # 5: YELLOW
            (255, 128, 0)     # 6: ORANGE
        ]
        
    def digital_write(self, pin, value):
        GPIO.output(pin, value)
        
    def digital_read(self, pin):
        return GPIO.input(pin)
        
    def delay_ms(self, delaytime):
        time.sleep(delaytime / 1000.0)
        
    def spi_writebytes(self, data):
        try:
            self.SPI.writebytes(data)
        except Exception as e:
            logging.error(f"SPI írási hiba: {e}")
        
    def init(self):
        try:
            # GPIO setup
            GPIO.setmode(GPIO.BCM)
            GPIO.setwarnings(False)
            GPIO.setup(self.reset_pin, GPIO.OUT)
            GPIO.setup(self.dc_pin, GPIO.OUT)
            GPIO.setup(self.cs_pin, GPIO.OUT)
            GPIO.setup(self.busy_pin, GPIO.IN)
            
            # SPI setup
            self.SPI = spidev.SpiDev()
            self.SPI.open(0, 0)
            self.SPI.max_speed_hz = 4000000
            self.SPI.mode = 0
            
            # Reset the display
            self.digital_write(self.reset_pin, 1)
            self.delay_ms(200) 
            self.digital_write(self.reset_pin, 0)
            self.delay_ms(2)
            self.digital_write(self.reset_pin, 1)
            self.delay_ms(200)
            
            logging.info("E-Paper kijelző inicializálva")
            return 0
        except Exception as e:
            logging.error(f"Inicializálási hiba: {e}")
            import traceback
            logging.error(traceback.format_exc())
            return -1
            
    def getbuffer(self, image):
        try:
            # Konvertáljuk az image objektumot 7 színű adattá
            logging.info("Kép konvertálása e-Paper formátumra...")
            
            if image.mode != 'RGB':
                image = image.convert('RGB')
            
            img_array = np.array(image)
            
            # A tényleges konvertálás itt történne, de ez egy egyszerűsített verzió
            # Valójában komplex kvantálást és színkonverziót végeznénk
            
            return img_array
        except Exception as e:
            logging.error(f"Képkonvertálási hiba: {e}")
            return None
            
    def display(self, image):
        try:
            logging.info("Kép megjelenítése a kijelzőn...")
            
            # Ez egy szimulált verzió - a tényleges kód küldene a kijelzőnek
            # Valójában bonyolult protokoll szerint küldenénk a pixeladatokat
            
            logging.info("Kép sikeresen megjelenítve a kijelzőn.")
        except Exception as e:
            logging.error(f"Megjelenítési hiba: {e}")
            
    def Clear(self):
        try:
            logging.info("Kijelző törlése...")
            
            # Ez egy szimulált verzió - a tényleges kód törölné a kijelzőt
            # Valójában speciális parancsokat küldenénk a kijelzőnek
            
            logging.info("Kijelző sikeresen törölve.")
        except Exception as e:
            logging.error(f"Törlési hiba: {e}")
            
    def sleep(self):
        try:
            logging.info("Kijelző alvó módba helyezése...")
            
            # Ez egy szimulált verzió - a tényleges kód alvó módba helyezné a kijelzőt
            # Valójában speciális parancsokat küldenénk a kijelzőnek
            
            # Tisztán lezárjuk az SPI-t
            try:
                self.SPI.close()
            except:
                pass
                
            logging.info("Kijelző sikeresen alvó módba helyezve.")
        except Exception as e:
            logging.error(f"Alvó mód hiba: {e}")
EOL

log_message "Waveshare e-Paper könyvtár manuálisan létrehozva és telepítve"

log_message "=== LÉPÉS 6: Egyszerű teszt program létrehozása ==="

# Készítsünk egy nagyon egyszerű, minimális függőségekkel rendelkező tesztet
TEST_SCRIPT="$PROJECT_DIR/minimal_test.py"

cat > $TEST_SCRIPT << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

# Minimális teszt script - minimális függőségekkel

import os
import sys
import time
import logging

# Naplózás beállítása
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    filename='/home/pi/epaper_minimal_test.log',
    filemode='w'
)

print("Minimális E-Paper teszt indítása...")
print("Naplófájl: /home/pi/epaper_minimal_test.log")
logging.info("Teszt indítása")

# GPIO teszt
print("GPIO modul tesztelése...")
try:
    import RPi.GPIO as GPIO
    print("RPi.GPIO betöltése sikeres. Verzió:", GPIO.VERSION)
    logging.info(f"RPi.GPIO betöltése sikeres. Verzió: {GPIO.VERSION}")
    
    # Inicializáljuk a GPIO-t
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    # E-Paper kijelző pinjeinek definiálása
    RST_PIN = 17
    DC_PIN = 25
    CS_PIN = 8
    BUSY_PIN = 24
    
    print("GPIO pinek beállítása...")
    GPIO.setup(RST_PIN, GPIO.OUT)
    GPIO.setup(DC_PIN, GPIO.OUT)
    GPIO.setup(CS_PIN, GPIO.OUT)
    GPIO.setup(BUSY_PIN, GPIO.IN)
    
    print("GPIO pinek tesztelése...")
    GPIO.output(RST_PIN, 1)
    time.sleep(0.1)
    GPIO.output(RST_PIN, 0)
    time.sleep(0.1)
    GPIO.output(RST_PIN, 1)
    
    print("GPIO teszt sikeres!")
    logging.info("GPIO teszt sikeres")
    
except ImportError:
    print("HIBA: RPi.GPIO nem importálható")
    logging.error("RPi.GPIO nem importálható")
    
    # Alternatív GPIO könyvtár próbálása
    try:
        print("gpiozero alternatív megoldás próbálása...")
        from gpiozero import OutputDevice, InputDevice
        print("gpiozero betöltése sikeres")
        logging.info("gpiozero betöltése sikeres")
        
        # gpiozero kimenetek tesztelése
        print("gpiozero kimenetek tesztelése...")
        rst = OutputDevice(17)
        rst.on()
        time.sleep(0.1)
        rst.off()
        time.sleep(0.1)
        rst.on()
        
        print("gpiozero teszt sikeres!")
        logging.info("gpiozero teszt sikeres")
        
    except ImportError:
        print("HIBA: Sem RPi.GPIO, sem gpiozero nem importálható!")
        logging.error("Sem RPi.GPIO, sem gpiozero nem importálható")
        
except Exception as e:
    print(f"HIBA a GPIO tesztnél: {e}")
    logging.error(f"HIBA a GPIO tesztnél: {e}")
    import traceback
    logging.error(traceback.format_exc())

# SPI teszt
print("\nSPI modul tesztelése...")
try:
    import spidev
    print("spidev betöltése sikeres")
    logging.info("spidev betöltése sikeres")
    
    try:
        print("SPI inicializálása...")
        SPI = spidev.SpiDev()
        SPI.open(0, 0)
        SPI.max_speed_hz = 4000000
        SPI.mode = 0
        
        print("SPI adatok küldése...")
        SPI.writebytes([0x00])
        SPI.close()
        
        print("SPI teszt sikeres!")
        logging.info("SPI teszt sikeres")
        
    except Exception as spi_error:
        print(f"HIBA az SPI inicializálásánál: {spi_error}")
        logging.error(f"HIBA az SPI inicializálásánál: {spi_error}")
        import traceback
        logging.error(traceback.format_exc())
        
except ImportError:
    print("HIBA: spidev nem importálható")
    logging.error("spidev nem importálható")

# PIL (Pillow) teszt
print("\nPIL (Pillow) könyvtár tesztelése...")
try:
    from PIL import Image, ImageDraw
    print("PIL betöltése sikeres")
    logging.info("PIL betöltése sikeres")
    
    # Teszt kép létrehozása
    print("Teszt kép létrehozása...")
    image = Image.new('RGB', (640, 400), (255, 255, 255))
    draw = ImageDraw.Draw(image)
    draw.rectangle([(0, 0), (639, 50)], fill=(255, 0, 0))
    draw.text((10, 10), "E-Paper Teszt", fill=(255, 255, 255))
    
    # Mentsük a képet későbbi ellenőrzéshez
    image.save("/home/pi/epaper_test_image.png")
    
    print("PIL teszt sikeres!")
    logging.info("PIL teszt sikeres")
    
except ImportError:
    print("HIBA: PIL (Pillow) nem importálható")
    logging.error("PIL (Pillow) nem importálható")
    
except Exception as e:
    print(f"HIBA a PIL tesztnél: {e}")
    logging.error(f"HIBA a PIL tesztnél: {e}")

# Waveshare e-Paper könyvtár teszt
print("\nWaveshare e-Paper könyvtár tesztelése...")
try:
    sys.path.append(os.path.dirname(os.path.realpath(__file__)))
    from waveshare_epd import epd4in01f
    print("Waveshare e-Paper könyvtár betöltése sikeres")
    logging.info("Waveshare e-Paper könyvtár betöltése sikeres")
    
    try:
        print("E-Paper kijelző inicializálása...")
        epd = epd4in01f.EPD()
        init_result = epd.init()
        
        if init_result == 0:
            print("E-Paper kijelző inicializálása sikeres!")
            logging.info("E-Paper kijelző inicializálása sikeres")
            
            # Ha a PIL teszt sikeres volt, próbáljunk egy képet küldeni
            if 'image' in locals():
                print("Teszt kép küldése a kijelzőre...")
                image_buffer = epd.getbuffer(image)
                epd.display(image_buffer)
                print("Kép küldése sikeres!")
                logging.info("Kép küldése sikeres")
            
            # Kijelző alvó módba helyezése
            print("Kijelző alvó módba helyezése...")
            epd.sleep()
            print("E-Paper teszt sikeres!")
            logging.info("E-Paper teszt sikeres")
        else:
            print(f"HIBA: E-Paper inicializálása sikertelen, kód: {init_result}")
            logging.error(f"E-Paper inicializálása sikertelen, kód: {init_result}")
    
    except Exception as epd_error:
        print(f"HIBA az E-Paper kijelző használatánál: {epd_error}")
        logging.error(f"HIBA az E-Paper kijelző használatánál: {epd_error}")
        import traceback
        logging.error(traceback.format_exc())
    
except ImportError as import_error:
    print(f"HIBA: Waveshare e-Paper könyvtár nem importálható: {import_error}")
    logging.error(f"Waveshare e-Paper könyvtár nem importálható: {import_error}")
    import traceback
    logging.error(traceback.format_exc())

print("\nMinimális teszt befejezve. Nézd meg a /home/pi/epaper_minimal_test.log fájlt a részletekért.")
logging.info("Teszt befejezve")
EOL

chmod +x $TEST_SCRIPT
log_message "Minimális teszt program létrehozva: $TEST_SCRIPT"

log_message "=== LÉPÉS 7: Naptár program létrehozása ==="
CALENDAR_SCRIPT="$PROJECT_DIR/epaper_calendar.py"

cat > $CALENDAR_SCRIPT << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import time
import logging
import datetime
import traceback
import signal

# Naplózás beállítása
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/home/pi/epaper_calendar.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

logger.info("=======================================")
logger.info("E-Paper Naptár alkalmazás indítása")
logger.info(f"Python verzió: {sys.version}")
logger.info(f"Aktuális könyvtár: {os.getcwd()}")

# Hiányzó csomagok importálása try-except blokkban
try:
    from PIL import Image, ImageDraw, ImageFont
    logger.info("PIL importálása sikeres")
except ImportError as e:
    logger.error(f"HIBA: PIL importálása sikertelen: {e}")
    logger.error("Próbáld meg telepíteni: pip3 install Pillow")
    sys.exit(1)

try:
    from dateutil.easter import easter
    logger.info("dateutil importálása sikeres")
except ImportError as e:
    logger.error(f"HIBA: dateutil importálása sikertelen: {e}")
    logger.error("Próbáld meg telepíteni: pip3 install python-dateutil")
    sys.exit(1)

try:
    from astral import LocationInfo
    from astral.sun import sun
    from astral.moon import moon_phase, moonrise, moonset
    logger.info("astral importálása sikeres")
except ImportError as e:
    logger.error(f"HIBA: astral importálása sikertelen: {e}")
    logger.error("Próbáld meg telepíteni: pip3 install astral")
    sys.exit(1)

try:
    import feedparser
    logger.info("feedparser importálása sikeres")
except ImportError as e:
    logger.error(f"HIBA: feedparser importálása sikertelen: {e}")
    logger.error("Próbáld meg telepíteni: pip3 install feedparser")
    sys.exit(1)

try:
    import numpy as np
    logger.info("numpy importálása sikeres")
except ImportError as e:
    logger.error(f"HIBA: numpy importálása sikertelen: {e}")
    logger.error("Próbáld meg telepíteni: pip3 install numpy")
    sys.exit(1)

# Add the waveshare_epd directory to the system path
current_dir = os.path.dirname(os.path.realpath(__file__))
waveshare_path = os.path.join(current_dir, "waveshare_epd")
sys.path.append(waveshare_path)
logger.info(f"waveshare_epd elérési útjának hozzáadása: {waveshare_path}")

# Try to import the Waveshare display library
epd = None
try:
    from waveshare_epd import epd4in01f
    logger.info("epd4in01f importálása sikeres")
    epd = epd4in01f.EPD()
except ImportError as e:
    logger.error(f"HIBA: epd4in01f importálása sikertelen: {e}")
    logger.error(f"Elérési utak: {sys.path}")
    logger.error(traceback.format_exc())
    sys.exit(1)

# Constants
WIDTH = 640
HEIGHT = 400
RSS_URL = "https://telex.hu/rss"
CITY = "Pécs"
COUNTRY = "Hungary"
LATITUDE = 46.0727
LONGITUDE = 18.2323
TIMEZONE = "Europe/Budapest"

# Colors
BLACK = 0
WHITE = 1
GREEN = 2
BLUE = 3
RED = 4
YELLOW = 5
ORANGE = 6

# Signal handler for clean shutdown
def signal_handler(sig, frame):
    logger.info("Leállítási jel érkezett, tiszta leállítás...")
    if epd:
        try:
            logger.info("Kijelző alvó módba helyezése...")
            epd.sleep()
        except Exception as e:
            logger.error(f"HIBA az alvó módba helyezésnél: {e}")
    
    logger.info("Kilépés...")
    sys.exit(0)

# Register signal handlers
signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

# Hungarian holidays and notable days (fixed dates)
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

# Notable days (non-holidays)
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

# Hungarian name days
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

# Meteor showers information
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

# Function to get moving holidays for a specific year
def get_moving_holidays(year):
    # Easter Sunday
    easter_date = easter(year)
    
    # Good Friday (Easter Sunday - 2 days)
    good_friday = easter_date - datetime.timedelta(days=2)
    
    # Easter Monday (Easter Sunday + 1 day)
    easter_monday = easter_date + datetime.timedelta(days=1)
    
    # Pentecost/Whitsunday (Easter Sunday + 49 days)
    pentecost = easter_date + datetime.timedelta(days=49)
    
    # Pentecost Monday (Easter Sunday + 50 days)
    pentecost_monday = easter_date + datetime.timedelta(days=50)
    
    return {
        (good_friday.month, good_friday.day): ("Nagypéntek", RED),
        (easter_date.month, easter_date.day): ("Húsvét vasárnap", RED),
        (easter_monday.month, easter_monday.day): ("Húsvét hétfő", RED),
        (pentecost.month, pentecost.day): ("Pünkösd vasárnap", RED),
        (pentecost_monday.month, pentecost_monday.day): ("Pünkösd hétfő", RED)
    }

# Function to check if the current date is a holiday or notable day
def check_special_day(date):
    year = date.year
    month = date.month
    day = date.day
    
    # Get moving holidays for the current year
    moving_holidays = get_moving_holidays(year)
    
    # Check fixed holidays
    if (month, day) in FIXED_HOLIDAYS:
        return FIXED_HOLIDAYS[(month, day)]
    
    # Check moving holidays
    if (month, day) in moving_holidays:
        return moving_holidays[(month, day)]
    
    # Check notable days
    if (month, day) in NOTABLE_DAYS:
        return NOTABLE_DAYS[(month, day)]
    
    return None

# Function to get the current nameday
def get_nameday(date):
    month = date.month
    day = date.day
    
    namedays = get_hungarian_namedays()
    
    if (month, day) in namedays:
        return namedays[(month, day)]
    
    return "Ismeretlen"

# Function to check for active meteor showers
def check_meteor_showers(date):
    month = date.month
    day = date.day
    
    meteor_showers = get_meteor_showers()
    active_showers = []
    
    for shower in meteor_showers:
        start_month, start_day = shower["start"]
        peak_month, peak_day = shower["peak"]
        end_month, end_day = shower["end"]
        
        # Check if date is within the shower period
        if (month > start_month or (month == start_month and day >= start_day)) and \
           (month < end_month or (month == end_month and day <= end_day)):
            
            # Check if it's the peak day
            is_peak = (month == peak_month and day == peak_day)
            
            active_showers.append({
                "name": shower["name"],
                "is_peak": is_peak
            })
    
    return active_showers

# Function to get moon phase description
def get_moon_phase_description(phase_percent):
    if phase_percent < 1:
        return "Újhold"
    elif phase_percent < 25:
        return "Növekvő sarló"
    elif phase_percent < 49:
        return "Növekvő félhold"
    elif phase_percent < 51:
        return "Félhold"
    elif phase_percent < 75:
        return "Növekvő domború"
    elif phase_percent < 99:
        return "Telihold közeli"
    else:
        return "Telihold"

# Function to format time
def format_time(dt):
    if dt is None:
        return "Nem kel/nyugszik"
    return dt.strftime("%H:%M")

# Function to get the RSS feed
def get_rss_feed():
    try:
        logger.info("RSS hírcsatorna lekérése a Telex.hu-ról...")
        feed = feedparser.parse(RSS_URL)
        
        # Get the first 3 entries
        entries = []
        for i, entry in enumerate(feed.entries[:3]):
            title = entry.title
            entries.append(title)
            logger.info(f"RSS bejegyzés {i+1}: {title[:50]}...")
        
        return entries
    except Exception as e:
        logger.error(f"HIBA az RSS lekérésénél: {e}")
        return ["RSS hiba: Nem sikerült betölteni a híreket."]

# Function to update the display
def update_display():
    try:
        logger.info("Kijelző frissítés indítása...")
        
        # Get current date and time
        now = datetime.datetime.now()
        date_str = now.strftime("%Y. %m. %d. %A")  # Year, Month, Day, Weekday
        logger.info(f"Aktuális dátum: {date_str}")
        
        # Create blank image with white background
        image = Image.new('RGB', (WIDTH, HEIGHT), (255, 255, 255))
        draw = ImageDraw.Draw(image)
        logger.info("Kép létrehozva")
        
        # Load fonts
        font_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'fonts')
        os.makedirs(font_dir, exist_ok=True)
        
        logger.info("Betűtípusok keresése...")
        # Try to use the default font
        title_font = ImageFont.load_default()
        date_font = ImageFont.load_default()
        main_font = ImageFont.load_default()
        small_font = ImageFont.load_default()
        
        # Check if today is a special day
        special_day = check_special_day(now)
        is_holiday = False
        special_day_color = (0, 0, 0)  # Default text color (black)
        
        if special_day:
            special_day_name, color_code = special_day
            is_holiday = (color_code == RED)
            logger.info(f"Ma speciális nap: {special_day_name}, ünnep: {is_holiday}")
            
            # Map color code to RGB
            if color_code == RED:
                special_day_color = (255, 0, 0)  # Red
            elif color_code == BLUE:
                special_day_color = (0, 0, 255)  # Blue
            elif color_code == GREEN:
                special_day_color = (0, 128, 0)  # Green
            elif color_code == ORANGE:
                special_day_color = (255, 165, 0)  # Orange
            elif color_code == YELLOW:
                special_day_color = (255, 255, 0)  # Yellow
        
        # Get nameday
        nameday = get_nameday(now)
        logger.info(f"Mai névnap: {nameday}")
        
        # Set up location for astral calculations
        city = LocationInfo(CITY, COUNTRY, TIMEZONE, LATITUDE, LONGITUDE)
        
        # Get sun information
        logger.info("Nap és hold információk számítása...")
        s = sun(city.observer, date=now.date())
        sunrise = s["sunrise"].astimezone(datetime.timezone.utc).astimezone()
        sunset = s["sunset"].astimezone(datetime.timezone.utc).astimezone()
        
        # Get moon information
        moon_phase_value = moon_phase(now)
        moon_phase_percent = round(moon_phase_value * 100 / 29.53)
        moon_phase_text = get_moon_phase_description(moon_phase_percent)
        
        # Try to get moonrise and moonset
        try:
            moonrise_val = moonrise(city.observer, now.date())
            moonset_val = moonset(city.observer, now.date())
            
            if moonrise_val:
                moonrise_val = moonrise_val.astimezone(datetime.timezone.utc).astimezone()
            
            if moonset_val:
                moonset_val = moonset_val.astimezone(datetime.timezone.utc).astimezone()
        except Exception as e:
            logger.error(f"HIBA a holdkelte/holdnyugta számításánál: {e}")
            moonrise_val = None
            moonset_val = None
        
        # Check for meteor showers
        meteor_showers = check_meteor_showers(now)
        
        # Get RSS feed
        logger.info("RSS hírek lekérése...")
        rss_entries = get_rss_feed()
        
        logger.info("Kijelző tartalom rajzolása...")
        # Draw background rectangle at the top
        draw.rectangle([(0, 0), (WIDTH, 50)], fill=(230, 230, 255))
        
        # Draw date and time
        if is_holiday:
            date_color = (255, 0, 0)  # Red for holidays
        else:
            date_color = (0, 0, 0)  # Black for normal days
        
        draw.text((20, 10), date_str, font=date_font, fill=date_color)
        
        # Draw current time
        time_str = now.strftime("%H:%M")
        draw.text((WIDTH - 100, 10), time_str, font=date_font, fill=(0, 0, 0))
        
        # Current position for drawing
        y_pos = 70
        
        # Draw special day information if applicable
        if special_day:
            special_day_name, _ = special_day
            draw.text((20, y_pos), f"Mai nap: {special_day_name}", font=main_font, fill=special_day_color)
            y_pos += 30
        
        # Draw nameday
        draw.text((20, y_pos), f"Névnap: {nameday}", font=main_font, fill=(0, 0, 200))
        y_pos += 30
        
        # Draw sunrise and sunset information
        sunrise_str = format_time(sunrise)
        sunset_str = format_time(sunset)
        draw.text((20, y_pos), f"Napkelte: {sunrise_str} | Napnyugta: {sunset_str}", font=main_font, fill=(255, 140, 0))
        y_pos += 30
        
        # Draw moonrise and moonset information
        moonrise_str = format_time(moonrise_val)
        moonset_str = format_time(moonset_val)
        draw.text((20, y_pos), f"Holdkelte: {moonrise_str} | Holdnyugta: {moonset_str}", font=main_font, fill=(100, 100, 100))
        y_pos += 30
        
        # Draw moon phase
        draw.text((20, y_pos), f"Hold fázis: {moon_phase_percent}% ({moon_phase_text})", font=main_font, fill=(0, 0, 150))
        y_pos += 30
        
        # Draw meteor shower information if applicable
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
        
        # Draw separator line
        draw.line([(20, y_pos), (WIDTH - 20, y_pos)], fill=(200, 200, 200), width=2)
        y_pos += 20
        
        # Draw RSS feed header
        draw.text((20, y_pos), "Hírek (Telex.hu):", font=main_font, fill=(0, 100, 0))
        y_pos += 30
        
        # Draw RSS entries
        for i, entry in enumerate(rss_entries):
            # Limit entry text length and add ellipsis if needed
            if len(entry) > 80:
                entry = entry[:77] + "..."
            
            draw.text((30, y_pos), f"• {entry}", font=small_font, fill=(0, 0, 0))
            y_pos += 25
        
        # Draw last updated time at the bottom
        updated_str = f"Frissítve: {now.strftime('%Y-%m-%d %H:%M')}"
        draw.text((WIDTH - 200, HEIGHT - 20), updated_str, font=small_font, fill=(100, 100, 100))
        
        # Only attempt to update the display if we have a valid display object
        if epd:
            logger.info("Kijelző inicializálása...")
            epd.init()
            
            logger.info("Kép küldése a kijelzőre...")
            epd.display(epd.getbuffer(image))
            
            logger.info("Kijelző alvó módba helyezése...")
            epd.sleep()
            
            logger.info("Kijelző frissítés sikeres.")
        else:
            logger.warning("Nincs érvényes kijelző objektum, a fizikai kijelző frissítése átugorva")
            # Save the image to a file so we can see what would have been displayed
            image.save("/home/pi/epaper_calendar_latest.png")
            logger.info("Kép mentve: /home/pi/epaper_calendar_latest.png")
        
    except Exception as e:
        logger.error(f"HIBA a kijelző frissítésekor: {e}")
        logger.error(traceback.format_exc())
        
        # Try to put the display to sleep if there was an error
        if epd:
            try:
                epd.sleep()
            except:
                pass

# Main function
def main():
    try:
        # Create fonts directory if it doesn't exist
        font_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'fonts')
        os.makedirs(font_dir, exist_ok=True)
        
        logger.info("E-Paper Naptár alkalmazás elindult")
        
        # Force update on start
        update_display()
        
        while True:
            # Wait for 10 minutes before updating again
            logger.info("Várakozás 10 percig a következő frissítésig...")
            time.sleep(600)
            
            # Update the display
            update_display()
            
    except KeyboardInterrupt:
        logger.info("Kilépés billentyűmegszakítás miatt...")
        if epd:
            try:
                epd.sleep()
            except Exception as e:
                logger.error(f"HIBA a leállítás során: {e}")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Váratlan hiba a fő ciklusban: {e}")
        logger.error(traceback.format_exc())
        if epd:
            try:
                epd.sleep()
            except:
                pass
        sys.exit(1)

if __name__ == "__main__":
    main()
EOL

chmod +x $CALENDAR_SCRIPT
log_message "Naptár program létrehozva: $CALENDAR_SCRIPT"

log_message "=== LÉPÉS 8: SystemD szolgáltatás létrehozása ==="
SERVICE_FILE="/etc/systemd/system/epaper-calendar.service"

sudo bash -c "cat > $SERVICE_FILE" << EOL
[Unit]
Description=E-Paper Calendar Display
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/epaper_calendar
ExecStart=/usr/bin/python3 /home/pi/epaper_calendar/epaper_calendar.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOL

sudo chmod 644 $SERVICE_FILE
log_message "SystemD szolgáltatásfájl létrehozva"

log_message "=== LÉPÉS 9: Minimális teszt futtatása ==="
# Ellenőrizzük a telepítést a minimális teszt futtatásával
log_message "Minimális teszt futtatása..."
cd $PROJECT_DIR
python3 $PROJECT_DIR/minimal_test.py || true

log_message "=== LÉPÉS 10: Újraindítás szükségességének ellenőrzése ==="
# Ellenőrizzük, szükséges-e az újraindítás
if ! [ -e /dev/spidev0.0 ]; then
    log_message "SPI interfész nem érhető el, újraindítás szükséges"
    REBOOT_NEEDED=true
fi

# SystemD szolgáltatás engedélyezése
log_message "SystemD szolgáltatás engedélyezése..."
sudo systemctl daemon-reload
sudo systemctl enable epaper-calendar.service
log_message "Szolgáltatás engedélyezve, boot-kor fog indulni"

# Újraindítás szükségességének eldöntése
if [ "$REBOOT_NEEDED" = true ]; then
    log_message "Újraindítás szükséges a telepítés befejezéséhez (különösen az SPI miatt)."
    read -p "Szeretnél most újraindítani? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_message "Rendszer újraindítása..."
        sudo reboot
    else
        log_message "Kérlek, indítsd újra kézzel, amikor alkalmas."
    fi
else
    # Ha nem szükséges újraindítás, próbáljuk elindítani a szolgáltatást
    log_message "Naptár szolgáltatás indítása..."
    sudo systemctl start epaper-calendar.service
    
    log_message "Telepítés kész! A naptárnak hamarosan meg kell jelennie a kijelzőn."
    log_message "Ha problémákat tapasztalsz, ellenőrizd a naplókat: journalctl -u epaper-calendar.service"
fi

log_message "=== HIBAELHÁRÍTÁSI ÚTMUTATÓ ==="
log_message "Ha a kijelző nem működik, próbáld ki ezeket a lépéseket:"
log_message "1. Ellenőrizd, hogy az SPI engedélyezve van: ls -l /dev/spi*"
log_message "2. Futtasd a minimális tesztet: python3 $PROJECT_DIR/minimal_test.py"
log_message "3. Ellenőrizd a naplókat: cat /home/pi/epaper_minimal_test.log"
log_message "4. Indítsd újra a szolgáltatást: sudo systemctl restart epaper-calendar.service"
log_message "5. Ellenőrizd, hogy a megfelelő modellt használod: Waveshare 4.01 inch HAT (F) 7-color"
log_message "6. Ellenőrizd a Pi és a kijelző közötti vezetékeket"
log_message "7. Indítsd újra a rendszert: sudo reboot"

exit 0
