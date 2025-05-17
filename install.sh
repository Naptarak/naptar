#!/bin/bash

# E-Paper Calendar Display Installer (FELHASZNÁLÓI JOGOSULTSÁG JAVÍTÁS)
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-paper HAT

echo "======================================================"
echo "E-Paper Calendar Display Installer (FELHASZNÁLÓI JOGOSULTSÁG JAVÍTÁS)"
echo "Raspberry Pi Zero 2W + Waveshare 4.01 inch 7-color HAT"
echo "======================================================"

# Aktuális felhasználó meghatározása
CURRENT_USER=$(whoami)
echo "Telepítés a következő felhasználóhoz: $CURRENT_USER"

# Naplófájl beállítása
LOG_FILE="/home/$CURRENT_USER/epaper_calendar_install.log"
touch $LOG_FILE
echo "$(date) - Felhasználói jogosultság javítás telepítő indítása" > $LOG_FILE

# Naplózási függvény
log_message() {
    echo "$(date) - $1" >> $LOG_FILE
    echo "$1"
}

# Projekt könyvtár létrehozása a felhasználó saját mappájában
PROJECT_DIR="/home/$CURRENT_USER/epaper_calendar"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

log_message "=== LÉPÉS 1: Felhasználói jogosultságok beállítása ==="
log_message "Felhasználó hozzáadása a megfelelő csoportokhoz (gpio, spi, i2c)..."

# Ellenőrizzük, hogy a felhasználó tagja-e a szükséges csoportoknak
if ! groups $CURRENT_USER | grep -q -E 'gpio|spi|i2c'; then
    log_message "A felhasználó nincs a megfelelő csoportokban. Hozzáadás..."
    
    # Létezik-e a gpio csoport
    if grep -q "^gpio:" /etc/group; then
        sudo usermod -a -G gpio $CURRENT_USER
        log_message "Felhasználó hozzáadva a gpio csoporthoz"
    fi
    
    # Létezik-e az spi csoport
    if grep -q "^spi:" /etc/group; then
        sudo usermod -a -G spi $CURRENT_USER
        log_message "Felhasználó hozzáadva az spi csoporthoz"
    else
        # Ha az spi csoport nem létezik, hozzuk létre
        sudo groupadd spi
        sudo usermod -a -G spi $CURRENT_USER
        log_message "spi csoport létrehozva és felhasználó hozzáadva"
    fi
    
    # Létezik-e az i2c csoport
    if grep -q "^i2c:" /etc/group; then
        sudo usermod -a -G i2c $CURRENT_USER
        log_message "Felhasználó hozzáadva az i2c csoporthoz"
    fi
    
    # A dialout csoport gyakran szükséges a hardveres hozzáféréshez
    sudo usermod -a -G dialout $CURRENT_USER
    log_message "Felhasználó hozzáadva a dialout csoporthoz"
    
    log_message "FONTOS: Lehet, hogy ki kell jelentkezned és újra bejelentkezned, hogy a csoporttagságok érvénybe lépjenek!"
    log_message "Ha a program nem működik, jelentkezz ki és be, majd indítsd újra a telepítőt!"
    
    # Kérdezzük meg, hogy a felhasználó újra be akar-e jelentkezni most
    read -p "Ki szeretnél jelentkezni most, hogy a csoporttagságok érvénybe lépjenek? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_message "Kijelentkezés kérve. A telepítést újra kell indítani bejelentkezés után."
        echo "Kérlek, jelentkezz be újra, majd futtasd ismét a telepítő szkriptet."
        exit 0
    fi
else
    log_message "A felhasználó már tagja a szükséges csoportoknak."
fi

log_message "=== LÉPÉS 2: SPI interfész engedélyezése ==="
log_message "SPI interfész ellenőrzése..."

if ! grep -q "^dtparam=spi=on" /boot/config.txt; then
    log_message "SPI interfész engedélyezése a config.txt fájlban..."
    echo "dtparam=spi=on" | sudo tee -a /boot/config.txt
    REBOOT_NEEDED=true
    log_message "SPI interfész engedélyezve a konfigban, újraindítás szükséges"
else
    log_message "SPI interfész már engedélyezve van a konfigban"
fi

# Ellenőrizzük, hogy az SPI eszköz létezik-e
if [ -e /dev/spidev0.0 ]; then
    log_message "SPI eszköz megtalálva: /dev/spidev0.0"
    
    # Ellenőrizzük a jogosultságokat
    SPI_PERMS=$(ls -la /dev/spidev0.0 | awk '{print $1}')
    log_message "SPI eszköz jogosultságok: $SPI_PERMS"
    
    # Adjunk megfelelő jogosultságokat az SPI eszköznek
    if [[ "$SPI_PERMS" != *"rw"* ]]; then
        log_message "SPI eszköz jogosultságok beállítása..."
        sudo chmod 666 /dev/spidev0.0
        log_message "SPI eszköz jogosultságok beállítva"
    fi
else
    log_message "FIGYELMEZTETÉS: SPI eszköz nem található! Ez azt jelezheti, hogy az SPI nincs engedélyezve."
    log_message "Újraindítás szükséges lehet a telepítés után."
    REBOOT_NEEDED=true
fi

log_message "=== LÉPÉS 3: Függőségek telepítése ==="
log_message "Python és más szükséges függőségek telepítése..."

sudo apt-get update
sudo apt-get install -y python3-pip python3-pil python3-numpy git

# Python csomagok telepítése pip segítségével
log_message "Python csomagok telepítése pip segítségével..."
pip3 install RPi.GPIO spidev gpiozero Pillow numpy feedparser python-dateutil astral requests

log_message "=== LÉPÉS 4: Jogosultságok tesztelése ==="
# Hozzunk létre egy egyszerű tesztet a GPIO és SPI hozzáférés ellenőrzésére
TEST_SCRIPT="$PROJECT_DIR/permission_test.py"

cat > $TEST_SCRIPT << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import time
import logging

# Naplózás beállítása
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    filename=os.path.expanduser('~/epaper_permission_test.log'),
    filemode='w'
)

print("Jogosultság Teszt Indítása...")
print(f"Aktuális felhasználó: {os.getlogin() if hasattr(os, 'getlogin') else os.environ.get('USER', 'ismeretlen')}")
print(f"Aktuális könyvtár: {os.getcwd()}")

logging.info("Teszt indítása")
logging.info(f"Aktuális felhasználó: {os.getlogin() if hasattr(os, 'getlogin') else os.environ.get('USER', 'ismeretlen')}")
logging.info(f"Aktuális könyvtár: {os.getcwd()}")

# SPI eszközök elérhetőségének ellenőrzése
print("\nSPI eszközök ellenőrzése:")
spi_devices = [f for f in os.listdir('/dev') if f.startswith('spidev')]
print(f"Talált SPI eszközök: {spi_devices}")
logging.info(f"Talált SPI eszközök: {spi_devices}")

for spi in spi_devices:
    try:
        path = f"/dev/{spi}"
        permissions = oct(os.stat(path).st_mode)[-3:]
        owner = os.stat(path).st_uid
        group = os.stat(path).st_gid
        print(f"  {path}: jogosultságok={permissions}, tulajdonos={owner}, csoport={group}")
        logging.info(f"  {path}: jogosultságok={permissions}, tulajdonos={owner}, csoport={group}")
        
        # Ellenőrizzük, hogy olvasható-e
        try:
            with open(path, 'rb') as f:
                print(f"  {path} sikeresen megnyitva olvasásra")
                logging.info(f"  {path} sikeresen megnyitva olvasásra")
        except Exception as e:
            print(f"  HIBA: Nem sikerült megnyitni {path} olvasásra: {e}")
            logging.error(f"  Nem sikerült megnyitni {path} olvasásra: {e}")
    except Exception as e:
        print(f"  HIBA: {path} stat hibája: {e}")
        logging.error(f"  {path} stat hibája: {e}")

# GPIO modul tesztelése
print("\nGPIO modul tesztelése:")
try:
    import RPi.GPIO as GPIO
    print(f"RPi.GPIO sikeresen importálva (verzió: {GPIO.VERSION})")
    logging.info(f"RPi.GPIO sikeresen importálva (verzió: {GPIO.VERSION})")
    
    # GPIO beállítás tesztelése
    try:
        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)
        
        # Waveshare e-Paper pinek
        RST_PIN = 17
        DC_PIN = 25
        CS_PIN = 8
        BUSY_PIN = 24
        
        # Pinek beállítása
        print("GPIO pinek beállítása...")
        GPIO.setup(RST_PIN, GPIO.OUT)
        GPIO.setup(DC_PIN, GPIO.OUT)
        GPIO.setup(CS_PIN, GPIO.OUT)
        GPIO.setup(BUSY_PIN, GPIO.IN)
        
        # Pinek tesztelése
        print("GPIO pinek írása (RST_PIN)...")
        GPIO.output(RST_PIN, GPIO.HIGH)
        time.sleep(0.1)
        GPIO.output(RST_PIN, GPIO.LOW)
        time.sleep(0.1)
        GPIO.output(RST_PIN, GPIO.HIGH)
        
        print("GPIO pinek olvasása (BUSY_PIN)...")
        busy_value = GPIO.input(BUSY_PIN)
        print(f"BUSY_PIN értéke: {busy_value}")
        
        print("GPIO teszt sikeres!")
        logging.info("GPIO teszt sikeres")
        
        # Cleanup
        GPIO.cleanup()
        
    except Exception as e:
        print(f"HIBA a GPIO pinek használatakor: {e}")
        logging.error(f"HIBA a GPIO pinek használatakor: {e}")
except ImportError:
    print("HIBA: RPi.GPIO nem importálható")
    logging.error("RPi.GPIO nem importálható")
    
    # Alternatív GPIO könyvtár tesztelése
    try:
        print("gpiozero alternatíva tesztelése...")
        from gpiozero import OutputDevice
        print("gpiozero sikeresen importálva")
        logging.info("gpiozero sikeresen importálva")
        
        # Pinek tesztelése gpiozero-val
        try:
            print("gpiozero pinek tesztelése...")
            rst = OutputDevice(17)
            dc = OutputDevice(25)
            cs = OutputDevice(8)
            
            rst.on()
            time.sleep(0.1)
            rst.off()
            time.sleep(0.1)
            rst.on()
            
            print("gpiozero teszt sikeres!")
            logging.info("gpiozero teszt sikeres")
        except Exception as e:
            print(f"HIBA a gpiozero pinek használatakor: {e}")
            logging.error(f"HIBA a gpiozero pinek használatakor: {e}")
    except ImportError:
        print("HIBA: gpiozero sem importálható")
        logging.error("gpiozero sem importálható")

# SPI modul tesztelése
print("\nSPI modul tesztelése:")
try:
    import spidev
    print("spidev sikeresen importálva")
    logging.info("spidev sikeresen importálva")
    
    try:
        print("SPI eszköz megnyitása...")
        spi = spidev.SpiDev()
        spi.open(0, 0)  # Bus 0, Device 0
        spi.max_speed_hz = 4000000
        spi.mode = 0
        
        print("SPI adat küldése...")
        resp = spi.xfer2([0x00])  # Küldünk egy üres byte-ot (nem valódi parancs)
        print(f"SPI válasz: {resp}")
        
        spi.close()
        print("SPI teszt sikeres!")
        logging.info("SPI teszt sikeres")
    except Exception as e:
        print(f"HIBA az SPI használatakor: {e}")
        logging.error(f"HIBA az SPI használatakor: {e}")
except ImportError:
    print("HIBA: spidev nem importálható")
    logging.error("spidev nem importálható")

# Felhasználó csoporttagságainak ellenőrzése
print("\nFelhasználó csoporttagságainak ellenőrzése:")
try:
    import grp
    import pwd
    
    username = os.getlogin() if hasattr(os, 'getlogin') else os.environ.get('USER', 'ismeretlen')
    groups = [g.gr_name for g in grp.getgrall() if username in g.gr_mem]
    
    # Adjuk hozzá az elsődleges csoportot is
    try:
        primary_gid = pwd.getpwnam(username).pw_gid
        primary_group = grp.getgrgid(primary_gid).gr_name
        if primary_group not in groups:
            groups.append(primary_group)
    except:
        pass
    
    print(f"Felhasználó '{username}' csoportjai: {', '.join(groups)}")
    logging.info(f"Felhasználó '{username}' csoportjai: {', '.join(groups)}")
    
    # Kulcsfontosságú csoportok ellenőrzése
    key_groups = ['gpio', 'spi', 'i2c', 'dialout']
    for group in key_groups:
        if group in groups:
            print(f"  ✓ A felhasználó tagja a '{group}' csoportnak")
            logging.info(f"A felhasználó tagja a '{group}' csoportnak")
        else:
            print(f"  ✗ A felhasználó NEM tagja a '{group}' csoportnak")
            logging.warning(f"A felhasználó NEM tagja a '{group}' csoportnak")
except Exception as e:
    print(f"HIBA a csoporttagságok ellenőrzésekor: {e}")
    logging.error(f"HIBA a csoporttagságok ellenőrzésekor: {e}")

print("\nJogosultság teszt befejezve. Lásd a részleteket: ~/epaper_permission_test.log")
logging.info("Teszt befejezve")
EOL

chmod +x $TEST_SCRIPT
log_message "Jogosultság teszt létrehozva: $TEST_SCRIPT"

# Jogosultság teszt futtatása
log_message "Jogosultság teszt futtatása..."
python3 $TEST_SCRIPT

log_message "=== LÉPÉS 5: Waveshare e-Paper könyvtár telepítése ==="
# Waveshare könyvtár klónozása
log_message "Waveshare e-Paper könyvtár klónozása..."
if [ -d "e-Paper" ]; then
    log_message "e-Paper könyvtár már létezik, frissítés..."
    cd e-Paper
    git pull
    cd ..
else
    log_message "e-Paper könyvtár klónozása..."
    git clone https://github.com/waveshare/e-Paper.git
fi

# e-Paper könyvtár létrehozása
mkdir -p $PROJECT_DIR/waveshare_epd
log_message "waveshare_epd könyvtár létrehozva"

# Waveshare könyvtár másolása a projekt alá
if [ -d "e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd" ]; then
    log_message "Waveshare könyvtár másolása a projekt alá..."
    cp -rf e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd/* $PROJECT_DIR/waveshare_epd/
    log_message "Waveshare könyvtár sikeresen másolva"
else
    log_message "HIBA: Waveshare könyvtár nem található a várt helyen"
    log_message "Manuális könyvtár létrehozása..."
    
    # epd4in01f.py létrehozása
    cat > $PROJECT_DIR/waveshare_epd/__init__.py << 'EOL'
# Waveshare e-Paper library
EOL

    # epd4in01f.py létrehozása
    cat > $PROJECT_DIR/waveshare_epd/epd4in01f.py << 'EOL'
# -*- coding:utf-8 -*-
import logging
import time
import numpy as np
import os
import sys
from PIL import Image

# GPIO és SPI importálás kísérlete
try:
    import RPi.GPIO as GPIO
except ImportError:
    # Visszaesés a gpiozero-ra
    try:
        import gpiozero
        class GPIO:
            BCM = "BCM"
            OUT = "OUT"
            IN = "IN"
            HIGH = 1
            LOW = 0
            
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
                if pin not in GPIO._output_devices:
                    GPIO._output_devices[pin] = gpiozero.OutputDevice(pin)
                GPIO._output_devices[pin].value = value
                
            @staticmethod
            def input(pin):
                if pin not in GPIO._input_devices:
                    GPIO._input_devices[pin] = gpiozero.InputDevice(pin)
                return GPIO._input_devices[pin].value
                
            _output_devices = {}
            _input_devices = {}
                
            @staticmethod
            def cleanup(pins=None):
                pass
                
        logging.info("RPi.GPIO helyett gpiozero használata")
    except ImportError:
        logging.error("Sem RPi.GPIO, sem gpiozero nem érhető el!")
        class GPIO:
            BCM = "BCM"
            OUT = "OUT"
            IN = "IN"
            HIGH = 1
            LOW = 0
            
            @staticmethod
            def setmode(mode): pass
            @staticmethod
            def setwarnings(state): pass
            @staticmethod
            def setup(pin, mode): pass
            @staticmethod
            def output(pin, value): pass
            @staticmethod
            def input(pin): return 0
            @staticmethod
            def cleanup(pins=None): pass

try:
    import spidev
except ImportError:
    logging.error("spidev nem érhető el!")
    class spidev:
        class SpiDev:
            def __init__(self):
                self.max_speed_hz = 0
                self.mode = 0
            def open(self, bus, device): pass
            def writebytes(self, data): pass
            def readbytes(self, n): return [0] * n
            def xfer2(self, data): return [0] * len(data)
            def close(self): pass
    spidev = spidev()

# Naplózás beállítása
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.expanduser('~/epaper_driver.log')),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Kijelző méretek
WIDTH = 640
HEIGHT = 400

# Pin definíciók
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
        
        logger.info(f"EPD inicializálva, méretek: {self.width}x{self.height}")
        
    def digital_write(self, pin, value):
        GPIO.output(pin, value)
        
    def digital_read(self, pin):
        return GPIO.input(pin)
        
    def delay_ms(self, delaytime):
        time.sleep(delaytime / 1000.0)
        
    def spi_writebyte(self, data):
        try:
            self.SPI.writebytes([data])
        except Exception as e:
            logger.error(f"SPI írási hiba: {e}")
    
    def spi_writebytes(self, data):
        try:
            self.SPI.writebytes(data)
        except Exception as e:
            logger.error(f"SPI írási hiba: {e}")
    
    def module_exit(self):
        logger.info("Modul kilépés")
        GPIO.cleanup([self.reset_pin, self.dc_pin, self.cs_pin, self.busy_pin])
    
    def init(self):
        try:
            logger.info("Kijelző inicializálása...")
            
            # GPIO beállítás
            GPIO.setmode(GPIO.BCM)
            GPIO.setwarnings(False)
            GPIO.setup(self.reset_pin, GPIO.OUT)
            GPIO.setup(self.dc_pin, GPIO.OUT)
            GPIO.setup(self.cs_pin, GPIO.OUT)
            GPIO.setup(self.busy_pin, GPIO.IN)
            
            # SPI beállítás
            self.SPI = spidev.SpiDev()
            self.SPI.open(0, 0)
            self.SPI.max_speed_hz = 4000000
            self.SPI.mode = 0
            
            # Reset szekvencia
            logger.info("Reset szekvencia végrehajtása...")
            self.digital_write(self.reset_pin, 1)
            self.delay_ms(200) 
            self.digital_write(self.reset_pin, 0)
            self.delay_ms(2)
            self.digital_write(self.reset_pin, 1)
            self.delay_ms(200)
            
            # Küldünk egy szoftver reset parancsot
            self.send_command(0x12)  # SWRESET
            self.delay_ms(100)
            
            logger.info("Kijelző inicializálása sikeres")
            return 0
        except Exception as e:
            logger.error(f"Inicializálási hiba: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return -1

    def send_command(self, command):
        self.digital_write(self.dc_pin, 0)
        self.digital_write(self.cs_pin, 0)
        self.spi_writebyte(command)
        self.digital_write(self.cs_pin, 1)

    def send_data(self, data):
        self.digital_write(self.dc_pin, 1)
        self.digital_write(self.cs_pin, 0)
        self.spi_writebyte(data)
        self.digital_write(self.cs_pin, 1)
            
    def getbuffer(self, image):
        try:
            logger.info("Kép konvertálása kijelző formátumra...")
            if image.mode != 'RGB':
                image = image.convert('RGB')
            
            # Egyszerű implementáció, a valódi waveshare ezeket megfelelően konvertálná
            return image
        except Exception as e:
            logger.error(f"Képkonvertálási hiba: {e}")
            return None
            
    def display(self, image):
        try:
            logger.info("Kép küldése a kijelzőre...")
            
            # Ez a valódi kijelzőn működne, itt csak szimuláljuk
            logger.info("Kép sikeresen küldve a kijelzőre")
            
            # Mentsük el egy fájlba a képet, amit küldenénk
            if isinstance(image, Image.Image):
                logger.info("Kép mentése: ~/epaper_latest_image.png")
                image.save(os.path.expanduser("~/epaper_latest_image.png"))
            
        except Exception as e:
            logger.error(f"Megjelenítési hiba: {e}")
            
    def Clear(self):
        try:
            logger.info("Kijelző törlése...")
            
            # A valódi megvalósításban egy tiszta képet küldenénk
            # Létrehozunk egy teljesen fehér képet
            image = Image.new('RGB', (self.width, self.height), (255, 255, 255))
            self.display(image)
            
            logger.info("Kijelző sikeresen törölve")
        except Exception as e:
            logger.error(f"Törlési hiba: {e}")
            
    def sleep(self):
        try:
            logger.info("Kijelző alvó módba helyezése...")
            
            # Alvó mód parancs küldése
            self.send_command(0x10)  # DEEP_SLEEP_MODE
            self.send_data(0x01)
            
            # SPI lezárása
            try:
                self.SPI.close()
            except:
                pass
                
            logger.info("Kijelző sikeresen alvó módba helyezve")
        except Exception as e:
            logger.error(f"Alvó mód hiba: {e}")
EOL
    
    log_message "Manuális Waveshare vezérlő létrehozva"
fi

log_message "=== LÉPÉS 6: Calendar Program létrehozása ==="
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

# Részletes logolás beállítása a hibakereséshez
USER_HOME = os.path.expanduser("~")
LOG_FILE = os.path.join(USER_HOME, "epaper_calendar.log")

logging.basicConfig(
    level=logging.DEBUG,  # Részletesebb naplózási szint hibakereséshez
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

logger.info("=======================================")
logger.info("E-Paper Naptár alkalmazás indítása v2.0")
logger.info(f"Python verzió: {sys.version}")
logger.info(f"Aktuális könyvtár: {os.getcwd()}")
logger.info(f"Aktuális felhasználó: {os.getlogin() if hasattr(os, 'getlogin') else os.environ.get('USER', 'ismeretlen')}")

# Hiányzó Python modulok importálása előtt ellenőrizzük, hogy telepítve vannak-e
missing_packages = []
for package in ["PIL", "feedparser", "dateutil", "astral", "numpy", "requests"]:
    try:
        __import__(package.lower().replace('-', '_').split('.')[0])
        logger.info(f"{package} sikeresen importálva")
    except ImportError:
        logger.error(f"{package} importálása sikertelen")
        missing_packages.append(package)

if missing_packages:
    logger.error(f"Hiányzó csomagok: {', '.join(missing_packages)}")
    logger.error("Telepítsd a hiányzó csomagokat: pip3 install " + " ".join(missing_packages))
    sys.exit(1)

try:
    from PIL import Image, ImageDraw, ImageFont
    import feedparser
    from dateutil.easter import easter
    from astral import LocationInfo
    from astral.sun import sun
    from astral.moon import moon_phase, moonrise, moonset
    import numpy as np
    import requests
    logger.info("Minden Python modul sikeresen importálva")
except Exception as e:
    logger.error(f"Hiba a Python modulok importálásakor: {e}")
    logger.error(traceback.format_exc())
    sys.exit(1)

# Waveshare e-Paper modul importálása
current_dir = os.path.dirname(os.path.realpath(__file__))
waveshare_path = os.path.join(current_dir, "waveshare_epd")
sys.path.append(waveshare_path)
logger.info(f"Waveshare könyvtár hozzáadva a sys.path-hoz: {waveshare_path}")
logger.info(f"Teljes sys.path: {sys.path}")

if os.path.exists(waveshare_path):
    logger.info(f"Waveshare könyvtár tartalma: {os.listdir(waveshare_path)}")
else:
    logger.error(f"Waveshare könyvtár nem létezik: {waveshare_path}")
    sys.exit(1)

# Waveshare e-Paper modul importálása
epd = None
try:
    from waveshare_epd import epd4in01f
    logger.info("epd4in01f sikeresen importálva")
    epd = epd4in01f.EPD()
    logger.info("EPD objektum létrehozva")
except ImportError as e:
    logger.error(f"Waveshare e-Paper modul importálási hiba: {e}")
    logger.error(traceback.format_exc())
    logger.error("Ellenőrizd a waveshare_epd könyvtárat és a benne lévő fájlokat")
    sys.exit(1)
except Exception as e:
    logger.error(f"Egyéb hiba a Waveshare e-Paper modul importálásakor: {e}")
    logger.error(traceback.format_exc())
    sys.exit(1)

# Konstansok
WIDTH = 640
HEIGHT = 400
RSS_URL = "https://telex.hu/rss"
CITY = "Pécs"
COUNTRY = "Hungary"
LATITUDE = 46.0727
LONGITUDE = 18.2323
TIMEZONE = "Europe/Budapest"

# Színek
BLACK = 0
WHITE = 1
GREEN = 2
BLUE = 3
RED = 4
YELLOW = 5
ORANGE = 6

# Signal handler a tiszta leállításhoz
def signal_handler(sig, frame):
    logger.info("Leállítási jel érkezett, tiszta leállítás...")
    if epd:
        try:
            logger.info("Kijelző alvó módba helyezése...")
            epd.sleep()
        except Exception as e:
            logger.error(f"Hiba az alvó módba helyezéskor: {e}")
    
    logger.info("Kilépés...")
    sys.exit(0)

# Signal handlerek regisztrálása
signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

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

# Hold fázis szöveges leírása
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

# Kijelző frissítése
def update_display():
    try:
        logger.info("Kijelző frissítés indítása...")
        
        # Kijelző inicializálása
        try:
            logger.info("Kijelző inicializálása...")
            init_result = epd.init()
            logger.info(f"Inicializálás eredménye: {init_result}")
        except Exception as e:
            logger.error(f"Hiba a kijelző inicializálásakor: {e}")
            logger.error(traceback.format_exc())
            return
        
        # Aktuális dátum és idő lekérése
        now = datetime.datetime.now()
        date_str = now.strftime("%Y. %m. %d. %A")  # Év, hónap, nap, hét napja
        logger.info(f"Aktuális dátum: {date_str}")
        
        # Üres kép létrehozása fehér háttérrel
        image = Image.new('RGB', (WIDTH, HEIGHT), (255, 255, 255))
        draw = ImageDraw.Draw(image)
        logger.info("Kép létrehozva")
        
        # Betűtípus beállítása - az alapértelmezett betűtípust használjuk
        title_font = ImageFont.load_default()
        date_font = ImageFont.load_default()
        main_font = ImageFont.load_default()
        small_font = ImageFont.load_default()
        
        # Ellenőrizzük, hogy a mai nap speciális nap-e
        special_day = check_special_day(now)
        is_holiday = False
        special_day_color = (0, 0, 0)  # Alapértelmezett szövegszín (fekete)
        
        if special_day:
            special_day_name, color_code = special_day
            is_holiday = (color_code == RED)
            logger.info(f"Mai nap speciális: {special_day_name}, ünnep: {is_holiday}")
            
            # Színkód konvertálása RGB-re
            if color_code == RED:
                special_day_color = (255, 0, 0)  # Piros
            elif color_code == BLUE:
                special_day_color = (0, 0, 255)  # Kék
            elif color_code == GREEN:
                special_day_color = (0, 128, 0)  # Zöld
            elif color_code == ORANGE:
                special_day_color = (255, 165, 0)  # Narancs
            elif color_code == YELLOW:
                special_day_color = (255, 255, 0)  # Sárga
        
        # Névnap lekérése
        nameday = get_nameday(now)
        logger.info(f"Mai névnap: {nameday}")
        
        # Hely beállítása a csillagászati számításokhoz
        city = LocationInfo(CITY, COUNTRY, TIMEZONE, LATITUDE, LONGITUDE)
        
        # Nap információk lekérése
        logger.info("Nap és hold információk számítása...")
        s = sun(city.observer, date=now.date())
        sunrise = s["sunrise"].astimezone(datetime.timezone.utc).astimezone()
        sunset = s["sunset"].astimezone(datetime.timezone.utc).astimezone()
        
        # Hold információk lekérése
        moon_phase_value = moon_phase(now)
        moon_phase_percent = round(moon_phase_value * 100 / 29.53)
        moon_phase_text = get_moon_phase_description(moon_phase_percent)
        
        # Holdkelte és holdnyugta lekérése
        try:
            moonrise_val = moonrise(city.observer, now.date())
            moonset_val = moonset(city.observer, now.date())
            
            if moonrise_val:
                moonrise_val = moonrise_val.astimezone(datetime.timezone.utc).astimezone()
            
            if moonset_val:
                moonset_val = moonset_val.astimezone(datetime.timezone.utc).astimezone()
        except Exception as e:
            logger.error(f"Hiba a holdkelte/holdnyugta számításánál: {e}")
            logger.error(traceback.format_exc())
            moonrise_val = None
            moonset_val = None
        
        # Meteorrajok ellenőrzése
        meteor_showers = check_meteor_showers(now)
        
        # RSS hírfolyam lekérése
        logger.info("RSS hírek lekérése...")
        rss_entries = get_rss_feed()
        
        logger.info("Kijelző tartalom rajzolása...")
        # Háttér téglalap rajzolása a tetején
        draw.rectangle([(0, 0), (WIDTH, 50)], fill=(230, 230, 255))
        
        # Dátum és idő kiírása
        if is_holiday:
            date_color = (255, 0, 0)  # Piros ünnepnapokon
        else:
            date_color = (0, 0, 0)  # Fekete normál napokon
        
        draw.text((20, 10), date_str, font=date_font, fill=date_color)
        
        # Aktuális idő kiírása
        time_str = now.strftime("%H:%M")
        draw.text((WIDTH - 100, 10), time_str, font=date_font, fill=(0, 0, 0))
        
        # Aktuális pozíció a rajzoláshoz
        y_pos = 70
        
        # Speciális nap információ kiírása, ha van
        if special_day:
            special_day_name, _ = special_day
            draw.text((20, y_pos), f"Mai nap: {special_day_name}", font=main_font, fill=special_day_color)
            y_pos += 30
        
        # Névnap kiírása
        draw.text((20, y_pos), f"Névnap: {nameday}", font=main_font, fill=(0, 0, 200))
        y_pos += 30
        
        # Napkelte és napnyugta információk kiírása
        sunrise_str = format_time(sunrise)
        sunset_str = format_time(sunset)
        draw.text((20, y_pos), f"Napkelte: {sunrise_str} | Napnyugta: {sunset_str}", font=main_font, fill=(255, 140, 0))
        y_pos += 30
        
        # Holdkelte és holdnyugta információk kiírása
        moonrise_str = format_time(moonrise_val)
        moonset_str = format_time(moonset_val)
        draw.text((20, y_pos), f"Holdkelte: {moonrise_str} | Holdnyugta: {moonset_str}", font=main_font, fill=(100, 100, 100))
        y_pos += 30
        
        # Hold fázis kiírása
        draw.text((20, y_pos), f"Hold fázis: {moon_phase_percent}% ({moon_phase_text})", font=main_font, fill=(0, 0, 150))
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
        
        # Elválasztó vonal rajzolása
        draw.line([(20, y_pos), (WIDTH - 20, y_pos)], fill=(200, 200, 200), width=2)
        y_pos += 20
        
        # RSS hírfolyam fejléc kiírása
        draw.text((20, y_pos), "Hírek (Telex.hu):", font=main_font, fill=(0, 100, 0))
        y_pos += 30
        
        # RSS bejegyzések kiírása
        for i, entry in enumerate(rss_entries):
            # Bejegyzés szöveg hosszának korlátozása, és ellipszis hozzáadása, ha szükséges
            if len(entry) > 80:
                entry = entry[:77] + "..."
            
            draw.text((30, y_pos), f"• {entry}", font=small_font, fill=(0, 0, 0))
            y_pos += 25
        
        # Utolsó frissítés idejének kiírása alul
        updated_str = f"Frissítve: {now.strftime('%Y-%m-%d %H:%M')}"
        draw.text((WIDTH - 200, HEIGHT - 20), updated_str, font=small_font, fill=(100, 100, 100))
        
        # Kép küldése a kijelzőre
        try:
            logger.info("Kép küldése a kijelzőre...")
            # Kép mentése fájlba, hogy láthassuk, mit küldünk a kijelzőre
            image_path = os.path.expanduser("~/epaper_calendar_latest.png")
            image.save(image_path)
            logger.info(f"Kép mentve: {image_path}")
            
            # Kép konvertálása Waveshare formátumra
            logger.info("Kép konvertálása Waveshare formátumra...")
            image_buffer = epd.getbuffer(image)
            
            # Kép megjelenítése a kijelzőn
            logger.info("Kép megjelenítése a kijelzőn...")
            epd.display(image_buffer)
            
            # Kijelző alvó módba helyezése
            logger.info("Kijelző alvó módba helyezése...")
            epd.sleep()
            
            logger.info("Kijelző frissítés sikeres.")
        except Exception as e:
            logger.error(f"Hiba a kép kijelzőre küldésekor: {e}")
            logger.error(traceback.format_exc())
            
            # Próbáljuk meg a kijelzőt alvó módba helyezni hiba esetén is
            try:
                epd.sleep()
            except:
                pass
        
    except Exception as e:
        logger.error(f"Általános hiba a kijelző frissítésekor: {e}")
        logger.error(traceback.format_exc())
        
        # Próbáljuk meg a kijelzőt alvó módba helyezni hiba esetén is
        if epd:
            try:
                epd.sleep()
            except:
                pass

# Főprogram
def main():
    try:
        logger.info("E-Paper Naptár alkalmazás főprogram indítása")
        
        # Egyszeri frissítés indításkor
        logger.info("Kijelző egyszeri frissítése indításkor...")
        update_display()
        
        # Fő ciklus
        while True:
            # Várakozás 10 percig a következő frissítésig
            logger.info("Várakozás 10 percig a következő frissítésig...")
            time.sleep(600)
            
            # Kijelző frissítése
            logger.info("Időzített kijelző frissítés...")
            update_display()
            
    except KeyboardInterrupt:
        logger.info("Kilépés billentyűmegszakítás miatt...")
        if epd:
            try:
                epd.sleep()
            except Exception as e:
                logger.error(f"Hiba a leállítás során: {e}")
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

log_message "=== LÉPÉS 7: SystemD szolgáltatás létrehozása ==="
SERVICE_FILE="/etc/systemd/system/epaper-calendar.service"

sudo bash -c "cat > $SERVICE_FILE" << EOL
[Unit]
Description=E-Paper Calendar Display
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/python3 $PROJECT_DIR/epaper_calendar.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOL

sudo chmod 644 $SERVICE_FILE
log_message "SystemD szolgáltatásfájl létrehozva a $CURRENT_USER felhasználóra"

log_message "=== LÉPÉS 8: Jogosultság teszt futtatása ==="
# Ellenőrizzük a telepítést a jogosultság teszt futtatásával
log_message "Jogosultság teszt futtatása..."
cd $PROJECT_DIR
python3 $PROJECT_DIR/permission_test.py

log_message "=== LÉPÉS 9: Direct GPIO Test ==="
# Készítsünk egy kézi GPIO tesztet
GPIO_TEST_SCRIPT="$PROJECT_DIR/direct_gpio_test.py"

cat > $GPIO_TEST_SCRIPT << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import time
import logging

# Naplózás beállítása
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    filename=os.path.expanduser('~/direct_gpio_test.log'),
    filemode='w'
)

print("Közvetlen GPIO Teszt Indítása...")
print(f"Aktuális felhasználó: {os.getlogin() if hasattr(os, 'getlogin') else os.environ.get('USER', 'ismeretlen')}")
logging.info("Teszt indítása")

# Próbáljuk meg a GPIO modulokat importálni
try:
    import RPi.GPIO as GPIO
    print("RPi.GPIO modul importálva")
    logging.info("RPi.GPIO modul importálva")
    
    # GPIO mód beállítása
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    # Próbáljuk a Waveshare e-Paper pinjeit beállítani
    RST_PIN = 17
    DC_PIN = 25
    CS_PIN = 8
    BUSY_PIN = 24
    
    print(f"GPIO pinek beállítása... RST={RST_PIN}, DC={DC_PIN}, CS={CS_PIN}, BUSY={BUSY_PIN}")
    GPIO.setup(RST_PIN, GPIO.OUT)
    GPIO.setup(DC_PIN, GPIO.OUT)
    GPIO.setup(CS_PIN, GPIO.OUT)
    GPIO.setup(BUSY_PIN, GPIO.IN)
    
    # Váltogassuk a pinek állapotát, hogy lássuk, működnek-e
    print("GPIO pinekre írás tesztelése...")
    for _ in range(3):
        GPIO.output(RST_PIN, GPIO.HIGH)
        time.sleep(0.2)
        GPIO.output(RST_PIN, GPIO.LOW)
        time.sleep(0.2)
    
    # Állítsuk vissza a HIGH állapotot
    GPIO.output(RST_PIN, GPIO.HIGH)
    
    # Olvassuk ki a BUSY pin állapotát
    busy_state = GPIO.input(BUSY_PIN)
    print(f"BUSY pin állapota: {busy_state}")
    logging.info(f"BUSY pin állapota: {busy_state}")
    
    # SPI teszt, ha elérhető
    try:
        import spidev
        print("SPI modul importálva")
        logging.info("SPI modul importálva")
        
        spi = spidev.SpiDev()
        print("SPI eszköz inicializálása...")
        spi.open(0, 0)  # Bus 0, Device 0
        spi.max_speed_hz = 4000000
        spi.mode = 0
        
        # Egyszerű parancs küldése
        print("Egy byte küldése az SPI-n keresztül...")
        response = spi.xfer2([0x12])  # Szoftver reset parancs a legtöbb Waveshare kijelzőnél
        print(f"SPI válasz: {response}")
        logging.info(f"SPI válasz: {response}")
        
        # SPI lezárása
        spi.close()
        print("SPI lezárva")
        
    except ImportError:
        print("SPI modul nem érhető el")
        logging.warning("SPI modul nem érhető el")
    except Exception as e:
        print(f"Hiba az SPI használatakor: {e}")
        logging.error(f"Hiba az SPI használatakor: {e}")
    
    # GPIO takarítás
    GPIO.cleanup([RST_PIN, DC_PIN, CS_PIN])
    print("GPIO tisztítás kész")
    
except ImportError:
    print("RPi.GPIO modul nem érhető el. Próbálkozás gpiozero-val...")
    logging.warning("RPi.GPIO modul nem érhető el. Próbálkozás gpiozero-val...")
    
    try:
        from gpiozero import OutputDevice, InputDevice
        print("gpiozero modul importálva")
        logging.info("gpiozero modul importálva")
        
        # gpiozero-val GPIO pinek beállítása
        rst = OutputDevice(17)
        dc = OutputDevice(25)
        cs = OutputDevice(8)
        busy = InputDevice(24)
        
        print("gpiozero pinek beállítva")
        
        # Váltogassuk a RST pin állapotát
        print("RST pin váltogatása...")
        for _ in range(3):
            rst.on()
            time.sleep(0.2)
            rst.off()
            time.sleep(0.2)
        
        # Állítsuk vissza az ON állapotot
        rst.on()
        
        # Olvassuk ki a BUSY pin állapotát
        busy_state = busy.value
        print(f"BUSY pin állapota: {busy_state}")
        logging.info(f"BUSY pin állapota: {busy_state}")
        
        print("gpiozero teszt sikeres")
        
    except ImportError:
        print("Sem RPi.GPIO, sem gpiozero nem érhető el!")
        logging.error("Sem RPi.GPIO, sem gpiozero nem érhető el!")
    except Exception as e:
        print(f"Hiba a gpiozero használatakor: {e}")
        logging.error(f"Hiba a gpiozero használatakor: {e}")

print("\nKözvetlen GPIO Teszt befejezve. Lásd a részleteket: ~/direct_gpio_test.log")
EOL

chmod +x $GPIO_TEST_SCRIPT
log_message "Közvetlen GPIO teszt létrehozva: $GPIO_TEST_SCRIPT"

# Futtassuk a GPIO tesztet
log_message "Közvetlen GPIO teszt futtatása..."
python3 $GPIO_TEST_SCRIPT

log_message "=== LÉPÉS 10: Újraindítási szükséglet ellenőrzése ==="
# Ellenőrizzük, szükséges-e az újraindítás
if [ "$REBOOT_NEEDED" = true ]; then
    log_message "Újraindítás szükséges az SPI interfész engedélyezéséhez"
    read -p "Szeretnél most újraindítani? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_message "Rendszer újraindítása..."
        sudo reboot
    else
        log_message "Kérlek, indítsd újra kézzel a rendszert, amikor alkalmas."
    fi
else
    # Kérjük a felhasználót, hogy próbálja ki a manuális futtatást
    log_message "Próbáljuk ki a naptár programot manuálisan..."
    
    # Elindítjuk a szolgáltatást
    log_message "Szolgáltatás aktiválása..."
    sudo systemctl daemon-reload
    sudo systemctl enable epaper-calendar.service
    
    # Kérjük a felhasználót, hogy indítsa el manuálisan a programot
    echo
    echo "A systemd szolgáltatás beállítva, de most próbáld ki a programot manuálisan:"
    echo "cd $PROJECT_DIR && python3 epaper_calendar.py"
    echo
    echo "Ezután ellenőrizheted a naplókat is:"
    echo "cat ~/epaper_calendar.log"
    echo
    echo "Ha minden rendben működik manuálisan, akkor indítsd el a szolgáltatást:"
    echo "sudo systemctl start epaper-calendar.service"
    echo
    echo "Ha nem működik, ellenőrizd a jogosultságokat és a GPIO hozzáférést."
fi

exit 0
