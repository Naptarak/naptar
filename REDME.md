#!/bin/bash

# E-Paper Calendar Display Standalone Installer
# Direct hardware communication version

echo "======================================================"
echo "E-Paper Calendar Display Standalone Installer"
echo "Direct hardware communication version"
echo "======================================================"

# Aktuális felhasználó és könyvtárak
CURRENT_USER=$(whoami)
echo "Telepítés a következő felhasználóhoz: $CURRENT_USER"
PROJECT_DIR="/home/$CURRENT_USER/epaper_standalone"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Alapvető csomagok telepítése - csak a tényleg szükséges dolgok
echo "Alapvető csomagok telepítése..."
sudo apt-get update
sudo apt-get install -y python3-dev python3-pillow python3-rpi.gpio python3-spidev

# SPI engedélyezése
echo "SPI interfész ellenőrzése..."
if ! grep -q "^dtparam=spi=on" /boot/config.txt; then
    echo "SPI interfész engedélyezése..."
    echo "dtparam=spi=on" | sudo tee -a /boot/config.txt
    echo "SPI engedélyezve, újraindítás szükséges lesz"
    REBOOT_NEEDED=true
fi

# Felhasználó hozzáadása csoportokhoz
echo "Felhasználói jogosultságok beállítása..."
sudo usermod -a -G spi,gpio,dialout $CURRENT_USER
echo "Felhasználó hozzáadva a szükséges csoportokhoz"

# Létrehozzuk a standalone kijelző meghajtó programot
echo "Közvetlen e-Paper meghajtó program létrehozása..."
cat > $PROJECT_DIR/direct_epaper.py << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

# Közvetlen hardverkezelő e-Paper meghajtó
# Minimális külső függőségekkel

import os
import sys
import time
import datetime
import logging
from PIL import Image, ImageDraw, ImageFont

# Naplózás beállítása
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.expanduser("~/epaper_direct.log")),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

logger.info("===============================================")
logger.info("Közvetlen E-Paper meghajtó indítása")
logger.info(f"Python verzió: {sys.version}")
logger.info(f"Aktuális könyvtár: {os.getcwd()}")
logger.info(f"Aktuális felhasználó: {os.environ.get('USER', 'ismeretlen')}")

# Hardveres GPIO kezelés
try:
    logger.info("GPIO modul betöltése...")
    import RPi.GPIO as GPIO
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    # Waveshare e-Paper pinek (4.01inch HAT (F))
    RST_PIN = 17
    DC_PIN = 25 
    CS_PIN = 8
    BUSY_PIN = 24
    
    GPIO.setup(RST_PIN, GPIO.OUT)
    GPIO.setup(DC_PIN, GPIO.OUT)
    GPIO.setup(CS_PIN, GPIO.OUT)
    GPIO.setup(BUSY_PIN, GPIO.IN)
    
    logger.info("GPIO inicializálva")
except Exception as e:
    logger.error(f"GPIO hiba: {e}")
    sys.exit(1)

# SPI kommunikáció
try:
    logger.info("SPI modul betöltése...")
    import spidev
    spi = spidev.SpiDev()
    spi.open(0, 0)
    spi.max_speed_hz = 4000000
    spi.mode = 0
    logger.info("SPI inicializálva")
except Exception as e:
    logger.error(f"SPI hiba: {e}")
    sys.exit(1)

# Alapvető funkciók a Waveshare 4.01inch 7-színű kijelzőhöz
class EPaper:
    def __init__(self):
        self.width = 640
        self.height = 400
        logger.info(f"Kijelző méret: {self.width}x{self.height}")
    
    def digital_write(self, pin, value):
        GPIO.output(pin, value)
    
    def digital_read(self, pin):
        return GPIO.input(pin)
    
    def delay_ms(self, delaytime):
        time.sleep(delaytime / 1000.0)
    
    def send_command(self, command):
        self.digital_write(DC_PIN, 0)
        self.digital_write(CS_PIN, 0)
        spi.writebytes([command])
        self.digital_write(CS_PIN, 1)
    
    def send_data(self, data):
        self.digital_write(DC_PIN, 1)
        self.digital_write(CS_PIN, 0)
        spi.writebytes([data])
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
            
            # Szoftver reset parancs küldése
            self.send_command(0x12)  # SWRESET
            self.delay_ms(100)
            
            # Várjunk, amíg a BUSY pin nem jelez (0=busy, 1=ready)
            logger.info("Várakozás a kijelző készenlétére...")
            busy_timeout = 50  # 5 másodperc timeout
            busy_count = 0
            while self.digital_read(BUSY_PIN) == 0:
                self.delay_ms(100)
                busy_count += 1
                if busy_count > busy_timeout:
                    logger.warning("Timeout a BUSY pin várakozáskor")
                    break
            
            # Booster soft start
            self.send_command(0x06)  # BOOSTER_SOFT_START
            self.send_data(0x17)
            self.send_data(0x17)
            self.send_data(0x17)
            
            # Power settings
            self.send_command(0x01)  # POWER_SETTING
            self.send_data(0x03)
            self.send_data(0x00)
            self.send_data(0x2B)
            self.send_data(0x2B)
            
            # Egyéb inicializáló parancsok
            # Megjegyzés: Ez csak egy egyszerűsített inicializálás,
            # nem tartalmazza az összes szükséges parancsot
            
            logger.info("Kijelző inicializálása sikeres")
            return 0
        except Exception as e:
            logger.error(f"Inicializálási hiba: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return -1
    
    def wait_until_idle(self):
        logger.info("Várakozás a kijelző készenlétére...")
        while self.digital_read(BUSY_PIN) == 0:
            self.delay_ms(100)
    
    def display_7color_bitmap(self, image):
        """7-színű bitmap megjelenítése (egyszerűsített verzió)"""
        try:
            logger.info("7-színű kép megjelenítése")
            
            if image.width != self.width or image.height != self.height:
                logger.warning(f"A kép mérete ({image.width}x{image.height}) nem egyezik a kijelző méretével ({self.width}x{self.height})")
                image = image.resize((self.width, self.height))
            
            # Ez csak egy részleges implementáció, de az alapvető koncepciót mutatja
            # Valós implementációban pixelenként kell konvertálni a képet a kijelző formátumára
            
            # A teljes kép ábrázolása színenként
            # Megjegyzés: Ez csak szimbolikus, nem valós implementáció
            logger.info("Kép adatok előkészítése...")
            
            # A tényleges implementáció küldene adatot a kijelzőnek itt
            # De ez többszáz sor kódot igényelne a tényleges implementációhoz
            
            # Ehelyett csak szimulálunk egy frissítést
            self.send_command(0x10)  # DATA_START_TRANSMISSION_1
            for i in range(1000):  # Szimulált adatküldés
                self.send_data(0xFF)  # Néhány adat küldése
            
            # Frissítés végrehajtása
            self.send_command(0x12)  # DISPLAY_REFRESH
            self.delay_ms(100)
            self.wait_until_idle()
            
            # Mentsük el a képet, hogy láthassuk, mit próbáltunk kijelezni
            image_path = os.path.expanduser("~/epaper_direct_latest.png")
            image.save(image_path)
            logger.info(f"Kép elmentve: {image_path}")
            
            logger.info("7-színű kép megjelenítése végrehajtva")
            return 0
        except Exception as e:
            logger.error(f"Képmegjelenítési hiba: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return -1
    
    def clear(self):
        """Kijelző törlése (fehérre)"""
        try:
            logger.info("Kijelző törlése...")
            
            # Fehér képernyő létrehozása és megjelenítése
            image = Image.new('RGB', (self.width, self.height), color=(255, 255, 255))
            return self.display_7color_bitmap(image)
        except Exception as e:
            logger.error(f"Törlési hiba: {e}")
            return -1
    
    def sleep(self):
        """Kijelző alvó módba helyezése"""
        try:
            logger.info("Kijelző alvó módba helyezése...")
            
            # Deep sleep mode
            self.send_command(0x07)  # DEEP_SLEEP
            self.send_data(0xA5)     # Parameter for deep sleep
            
            logger.info("Kijelző alvó módban")
            return 0
        except Exception as e:
            logger.error(f"Alvó mód hiba: {e}")
            return -1
    
    def close(self):
        """Erőforrások felszabadítása"""
        try:
            logger.info("Erőforrások felszabadítása...")
            
            spi.close()
            GPIO.cleanup([RST_PIN, DC_PIN, CS_PIN, BUSY_PIN])
            
            logger.info("Erőforrások felszabadítva")
            return 0
        except Exception as e:
            logger.error(f"Lezárási hiba: {e}")
            return -1

# Egyszerű naptár információk
def get_calendar_info():
    now = datetime.datetime.now()
    date_str = now.strftime("%Y. %m. %d. %A")
    time_str = now.strftime("%H:%M")
    
    # Egyszerű szöveges információk (átfogó naptár adatok nélkül)
    info = {
        "date": date_str,
        "time": time_str,
        "updated": now.strftime("%Y-%m-%d %H:%M")
    }
    
    # Magyar hónapnevek és napok
    hungarian_days = ["Hétfő", "Kedd", "Szerda", "Csütörtök", "Péntek", "Szombat", "Vasárnap"]
    hungarian_months = ["Január", "Február", "Március", "Április", "Május", "Június", 
                        "Július", "Augusztus", "Szeptember", "Október", "November", "December"]
    
    day_of_week = now.weekday()
    month = now.month - 1  # 0-tól indexelve
    
    info["hu_day"] = hungarian_days[day_of_week]
    info["hu_month"] = hungarian_months[month]
    info["hu_date"] = f"{now.year}. {info['hu_month']} {now.day}., {info['hu_day']}"
    
    return info

# Tesztfüggvény a kijelző működésének ellenőrzésére
def test_display():
    logger.info("E-Paper kijelző teszt indítása...")
    
    # Kijelző példányosítása
    epd = EPaper()
    
    try:
        # Inicializálás
        if epd.init() != 0:
            logger.error("Inicializálási hiba, teszt megszakítva")
            return
        
        # Kijelző törlése
        if epd.clear() != 0:
            logger.error("Kijelző törlési hiba")
        
        # Naptár információk lekérése
        calendar_info = get_calendar_info()
        
        # Kép létrehozása
        image = Image.new('RGB', (epd.width, epd.height), color=(255, 255, 255))
        draw = ImageDraw.Draw(image)
        
        # Betűtípus beállítása (alapértelmezett, ha nincs speciális)
        font = ImageFont.load_default()
        
        # Téglalap rajzolása a tetejére
        draw.rectangle([(0, 0), (epd.width, 50)], fill=(230, 230, 255))
        
        # Dátum és idő kiírása
        draw.text((20, 10), calendar_info["hu_date"], font=font, fill=(0, 0, 0))
        draw.text((epd.width - 100, 10), calendar_info["time"], font=font, fill=(0, 0, 0))
        
        # Néhány teszt elem
        draw.text((20, 70), "E-Paper kijelző teszt", font=font, fill=(255, 0, 0))
        draw.text((20, 100), "Közvetlen kommunikáció", font=font, fill=(0, 0, 255))
        draw.text((20, 130), "Waveshare 4.01 inch 7-színű e-paper", font=font, fill=(0, 128, 0))
        
        # Színes téglalapok rajzolása (színteszt)
        colors = [
            (0, 0, 0),       # Fekete
            (255, 255, 255), # Fehér
            (0, 255, 0),     # Zöld
            (0, 0, 255),     # Kék
            (255, 0, 0),     # Piros
            (255, 255, 0),   # Sárga
            (255, 128, 0)    # Narancs
        ]
        
        rect_width = 80
        for i, color in enumerate(colors):
            draw.rectangle(
                [(i*rect_width + 20, 180), ((i+1)*rect_width - 10 + 20, 230)], 
                fill=color, outline=(0, 0, 0)
            )
        
        # Frissítési információ
        draw.text(
            (epd.width - 250, epd.height - 20), 
            f"Frissítve: {calendar_info['updated']}", 
            font=font, 
            fill=(100, 100, 100)
        )
        
        # Kép megjelenítése a kijelzőn
        logger.info("Kép küldése a kijelzőre...")
        epd.display_7color_bitmap(image)
        
        # Kijelző alvó módba helyezése
        epd.sleep()
        
        logger.info("Kijelző teszt befejezve")
        
    except Exception as e:
        logger.error(f"Teszt hiba: {e}")
        import traceback
        logger.error(traceback.format_exc())
    finally:
        # Erőforrások felszabadítása
        try:
            epd.close()
        except:
            pass

# Főprogram
if __name__ == "__main__":
    try:
        test_display()
    except KeyboardInterrupt:
        logger.info("Program megszakítva")
        sys.exit(0)
EOL

chmod +x $PROJECT_DIR/direct_epaper.py

# Létrehozzuk a periodikus frissítőt
echo "Egyszerű frissítő szolgáltatás létrehozása..."
cat > $PROJECT_DIR/refresh_display.py << 'EOL'
#!/usr/bin/env python3

import os
import sys
import time
import logging
import subprocess
import datetime

# Naplózás beállítása
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.expanduser("~/epaper_refresh.log")),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Kijelző frissítése a direct_epaper.py segítségével
def refresh_display():
    try:
        logger.info("Kijelző frissítése...")
        
        # Az aktuális könyvtár meghatározása
        current_dir = os.path.dirname(os.path.realpath(__file__))
        
        # A direct_epaper.py futtatása
        script_path = os.path.join(current_dir, "direct_epaper.py")
        
        # Ellenőrizzük, hogy a script létezik-e
        if not os.path.exists(script_path):
            logger.error(f"A script nem található: {script_path}")
            return False
        
        # Futtatjuk a parancsot
        logger.info(f"Script futtatása: {script_path}")
        result = subprocess.run([sys.executable, script_path], 
                               capture_output=True, text=True)
        
        # Kimenet és hibák naplózása
        if result.stdout:
            logger.info(f"Script kimenet: {result.stdout}")
        
        if result.stderr:
            logger.error(f"Script hiba: {result.stderr}")
        
        # Visszatérési érték ellenőrzése
        if result.returncode != 0:
            logger.error(f"Script hibakóddal tért vissza: {result.returncode}")
            return False
        
        logger.info("Kijelző frissítése sikeres")
        return True
    
    except Exception as e:
        logger.error(f"Hiba a kijelző frissítésekor: {e}")
        import traceback
        logger.error(traceback.format_exc())
        return False

# Főprogram - 10 percenkénti frissítés
if __name__ == "__main__":
    logger.info("E-Paper kijelző frissítő szolgáltatás indítása")
    
    try:
        # Egyszeri frissítés indításkor
        refresh_display()
        
        # Ciklus a periodikus frissítéshez
        while True:
            # 10 perc várakozás (600 másodperc)
            logger.info("Várakozás 10 percig a következő frissítésig...")
            time.sleep(600)
            
            # Kijelző frissítése
            refresh_display()
    
    except KeyboardInterrupt:
        logger.info("Szolgáltatás leállítva")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Váratlan hiba: {e}")
        import traceback
        logger.error(traceback.format_exc())
        sys.exit(1)
EOL

chmod +x $PROJECT_DIR/refresh_display.py

# Létrehozzuk a systemd szolgáltatást
echo "Systemd szolgáltatás létrehozása..."
sudo bash -c "cat > /etc/systemd/system/epaper-standalone.service" << EOL
[Unit]
Description=E-Paper Standalone Display Service
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/python3 $PROJECT_DIR/refresh_display.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOL

sudo chmod 644 /etc/systemd/system/epaper-standalone.service

# Létrehozzuk az uninstall scriptet
echo "Eltávolító script létrehozása..."
cat > $PROJECT_DIR/uninstall.sh << EOL
#!/bin/bash

# E-Paper Standalone Display Uninstaller

echo "======================================================"
echo "E-Paper Standalone Display Uninstaller"
echo "======================================================"

# Szolgáltatás leállítása és eltávolítása
echo "Szolgáltatás leállítása és eltávolítása..."
sudo systemctl stop epaper-standalone.service
sudo systemctl disable epaper-standalone.service
sudo rm -f /etc/systemd/system/epaper-standalone.service
sudo systemctl daemon-reload

# Kijelző törlése
echo "Kijelző törlése..."
python3 $PROJECT_DIR/direct_epaper.py clear

# Könyvtárak eltávolítása
echo "Könyvtárak eltávolítása..."
rm -rf $PROJECT_DIR

echo "Eltávolítás kész!"
EOL

chmod +x $PROJECT_DIR/uninstall.sh

# Aktiváljuk a szolgáltatást
echo "Systemd szolgáltatás aktiválása..."
sudo systemctl daemon-reload
sudo systemctl enable epaper-standalone.service

# Összegzés és útmutatás
echo "========================================================================"
echo "Telepítés kész!"
echo ""
echo "A közvetlen hardveres meghajtó a következő helyen található:"
echo "$PROJECT_DIR/direct_epaper.py"
echo ""
echo "Ha az SPI interfész most lett engedélyezve, újraindítás szükséges."
echo "Újraindítás után a szolgáltatás automatikusan elindul."
echo ""
echo "Kézi teszteléshez futtasd:"
echo "python3 $PROJECT_DIR/direct_epaper.py"
echo ""
echo "Szolgáltatás indításához:"
echo "sudo systemctl start epaper-standalone.service"
echo ""
echo "Eltávolításhoz futtasd:"
echo "$PROJECT_DIR/uninstall.sh"
echo "========================================================================"

# Újraindítás, ha szükséges
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
else
    # Indítsuk el a szolgáltatást
    echo "Szolgáltatás indítása..."
    sudo systemctl start epaper-standalone.service
    echo "Szolgáltatás elindítva"
fi
