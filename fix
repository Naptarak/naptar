#!/bin/bash

# Hibajavító szkript az e-Paper naptár alkalmazáshoz

echo "E-Paper Naptár Hibajavító"
echo "========================="

# gpiozero telepítése
echo "1. A hiányzó gpiozero modul telepítése..."
sudo pip3 install gpiozero
echo "Telepítés kész!"

# Tesztprogram javítása
echo "2. Az epaper_test.py javítása..."
cat > ~/e_paper_calendar/epaper_test.py << 'EOF'
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
    # Javítás: Clear() függvény megfelelő használata - ne adjunk át paramétert
    epd.Clear()  # Vagy: epd.clear() - kis betűvel, API-tól függően
    logger.debug("Kijelző törölve")
    
    logger.debug("Alvó állapot...")
    epd.sleep()
    logger.debug("Teszt sikeresen befejezve")
    
except Exception as e:
    logger.error(f"Hiba: {e}")
    logger.error(traceback.format_exc())

logger.debug("Teszt futás befejezve")
EOF
chmod +x ~/e_paper_calendar/epaper_test.py

# Fő alkalmazás javítása
echo "3. A calendar_display.py javítása..."
cp ~/e_paper_calendar/calendar_display.py ~/e_paper_calendar/calendar_display.py.bak
sed -i 's/epd\.Clear(0xFF)/epd.Clear()/g' ~/e_paper_calendar/calendar_display.py
echo "Javítás kész!"

echo ""
echo "A hibajavítások telepítve lettek. Próbáljuk először a tesztprogramot:"
echo "cd ~/e_paper_calendar && python3 epaper_test.py"
echo ""
echo "Ha a teszt sikeres, indítsuk újra a fő alkalmazást:"
echo "cd ~/e_paper_calendar && ./start_calendar.sh"
