#!/bin/bash

# E-Paper Calendar Display Uninstaller (FELHASZNÁLÓI JOGOSULTSÁG VERZIÓ)
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-paper HAT

echo "======================================================"
echo "E-Paper Calendar Display Uninstaller (FELHASZNÁLÓI JOGOSULTSÁG VERZIÓ)"
echo "Raspberry Pi Zero 2W + Waveshare 4.01 inch 7-color HAT"
echo "======================================================"

# Aktuális felhasználó meghatározása
CURRENT_USER=$(whoami)
echo "Eltávolítás a következő felhasználóhoz: $CURRENT_USER"

# Naplófájl létrehozása
LOG_FILE="/home/$CURRENT_USER/epaper_calendar_uninstall.log"
touch $LOG_FILE
echo "$(date) - Eltávolítás indítása" > $LOG_FILE

# Naplózási függvény
log_message() {
    echo "$(date) - $1" >> $LOG_FILE
    echo "$1"
}

log_message "=== LÉPÉS 1: Szolgáltatások leállítása ==="
# Stop and disable the systemd service
log_message "SystemD szolgáltatás leállítása és letiltása..."
sudo systemctl stop epaper-calendar.service
sudo systemctl disable epaper-calendar.service
sudo rm -f /etc/systemd/system/epaper-calendar.service
sudo systemctl daemon-reload
log_message "SystemD szolgáltatás eltávolítva"

log_message "=== LÉPÉS 2: Kijelző törlése ==="
# Create a simple script to clear the display
cat > /tmp/clear_display.py << 'EOL'
#!/usr/bin/env python3
import os
import sys
import time
import logging
import traceback

USER_HOME = os.path.expanduser("~")
LOG_FILE = os.path.join(USER_HOME, "epaper_clear.log")

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    filename=LOG_FILE,
    filemode='w'
)
logger = logging.getLogger(__name__)

logger.info("E-Paper kijelző tisztítási kísérlet indítása")

try:
    # Próbáljuk meg a GPIO-t elérni
    logger.info("GPIO elérése...")
    import RPi.GPIO as GPIO
    
    # GPIO beállítása
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    # E-Paper kijelző pinjei
    RST_PIN = 17
    DC_PIN = 25
    CS_PIN = 8
    BUSY_PIN = 24
    
    # Pinek beállítása
    GPIO.setup(RST_PIN, GPIO.OUT)
    GPIO.setup(DC_PIN, GPIO.OUT)
    GPIO.setup(CS_PIN, GPIO.OUT)
    GPIO.setup(BUSY_PIN, GPIO.IN)
    
    logger.info("GPIO beállítva")
    
    # SPI beállítása
    try:
        logger.info("SPI beállítása...")
        import spidev
        SPI = spidev.SpiDev()
        SPI.open(0, 0)
        SPI.max_speed_hz = 4000000
        SPI.mode = 0
        logger.info("SPI beállítva")
        
        # Reset szekvencia
        logger.info("Reset szekvencia végrehajtása...")
        GPIO.output(RST_PIN, 1)
        time.sleep(0.2)
        GPIO.output(RST_PIN, 0)
        time.sleep(0.2)
        GPIO.output(RST_PIN, 1)
        time.sleep(0.2)
        
        # Parancs küldése funkció
        def send_command(command):
            GPIO.output(DC_PIN, 0)  # Command mode
            GPIO.output(CS_PIN, 0)
            SPI.writebytes([command])
            GPIO.output(CS_PIN, 1)
        
        # Adat küldése funkció
        def
