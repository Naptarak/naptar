#!/bin/bash

# E-Paper Calendar Display Uninstaller (FRISSÍTETT)
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-paper HAT

echo "======================================================"
echo "E-Paper Calendar Display Uninstaller (FRISSÍTETT)"
echo "Raspberry Pi Zero 2W + Waveshare 4.01 inch 7-color HAT"
echo "======================================================"

# Create log file with timestamps
LOG_FILE="/home/pi/epaper_calendar_uninstall.log"
touch $LOG_FILE
echo "$(date) - Starting uninstallation" > $LOG_FILE

# Function to log messages
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
# Minimal script to clear the display - using direct GPIO access
cat > /tmp/clear_display.py << 'EOL'
#!/usr/bin/env python3
import os
import sys
import time
import logging

# Naplózás beállítása
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    filename='/home/pi/epaper_clear.log',
    filemode='w'
)

print("E-Paper kijelző tisztítása...")
logging.info("E-Paper kijelző tisztítása")

# GPIO elérés próbálása több módon
try:
    # 1. Módszer - RPi.GPIO
    print("RPi.GPIO használata...")
    import RPi.GPIO as GPIO
    
    # GPIO beállítása
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    # Pinek definiálása
    RST_PIN = 17
    DC_PIN = 25
    CS_PIN = 8
    BUSY_PIN = 24
    
    # Pinek beállítása
    GPIO.setup(RST_PIN, GPIO.OUT)
    GPIO.setup(DC_PIN, GPIO.OUT)
    GPIO.setup(CS_PIN, GPIO.OUT)
    GPIO.setup(BUSY_PIN, GPIO.IN)
    
    # Reset szekvencia (a legtöbb e-Paper kijelzőnél működik)
    print("Reset szekvencia végrehajtása...")
    GPIO.output(RST_PIN, 1)
    time.sleep(0.2)
    GPIO.output(RST_PIN, 0)
    time.sleep(0.2)
    GPIO.output(RST_PIN, 1)
    time.sleep(0.2)
    
    # Próbáljuk meg SPI-val
    try:
        import spidev
        print("SPI használata...")
        SPI = spidev.SpiDev()
        SPI.open(0, 0)
        SPI.max_speed_hz = 4000000
        SPI.mode = 0
        
        # Egyszerű parancs küldése (pl. bekapcsolás vagy reset)
        print("Parancs küldése...")
        GPIO.output(DC_PIN, 0)  # Command mode
        GPIO.output(CS_PIN, 0)
        SPI.writebytes([0x12])  # Software reset command
        GPIO.output(CS_PIN, 1)
        time.sleep(0.1)
        
        # Deep sleep parancs
        GPIO.output(DC_PIN, 0)  # Command mode
        GPIO.output(CS_PIN, 0)
        SPI.writebytes([0x10])  # Deep sleep command
        GPIO.output(CS_PIN, 1)
        
        SPI.close()
    except Exception as e:
        print(f"SPI hiba: {e}")
        logging.error(f"SPI hiba: {e}")
    
    # Takarítás
    GPIO.cleanup([RST_PIN, DC_PIN, CS_PIN])
    print("RPi.GPIO tisztítás kész")
    
except ImportError:
    print("RPi.GPIO nem érhető el, próbálkozás gpiozero-val...")
    
    try:
        # 2. Módszer - gpiozero
        from gpiozero import OutputDevice
        
        print("gpiozero használata...")
        rst = OutputDevice(17)
        dc = OutputDevice(25)
        cs = OutputDevice(8)
        
        # Reset szekvencia
        print("Reset szekvencia végrehajtása...")
        rst.on()
        time.sleep(0.2)
        rst.off()
        time.sleep(0.2)
        rst.on()
        time.sleep(0.2)
        
        # Nincs közvetlen SPI hozzáférés a gpiozero-ban
        print("gpiozero tisztítás kész")
        
    except ImportError:
        print("Sem RPi.GPIO, sem gpiozero nem érhető el")
        logging.error("Sem RPi.GPIO, sem gpiozero nem érhető el")

print("Kijelző törlési kísérlet befejezve")
logging.info("Kijelző törlési kísérlet befejezve")
EOL

# Futtatható jogosultság beállítása és futtatás
chmod +x /tmp/clear_display.py
python3 /tmp/clear_display.py
rm /tmp/clear_display.py

log_message "=== LÉPÉS 3: Fájlok eltávolítása ==="
# Delete log files
log_message "Naplófájlok eltávolítása..."
rm -f /home/pi/epaper_calendar.log
rm -f /home/pi/epaper_minimal_test.log
rm -f /home/pi/epaper_clear.log
rm -f /home/pi/epaper_test_image.png
rm -f /home/pi/epaper_calendar_latest.png

# Remove the project directory
if [ -d "/home/pi/epaper_calendar" ]; then
    log_message "Projekt könyvtár eltávolítása..."
    rm -rf /home/pi/epaper_calendar
    log_message "Projekt könyvtár eltávolítva"
else
    log_message "Projekt könyvtár nem található, már eltávolították"
fi

log_message "=== LÉPÉS 4: Függőségek eltávolítása ==="
# Ask if the user wants to remove dependencies
read -p "Szeretnéd eltávolítani a telepített függőségeket? Ez más alkalmazásokat is érinthet. (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_message "Függőségek eltávolítása..."
    
    # Python packages via pip
    log_message "Python csomagok eltávolítása..."
    pip_packages=(
        "RPi.GPIO"
        "spidev"
        "gpiozero"
        "feedparser"
        "python-dateutil"
        "astral"
        "Pillow"
        "numpy"
        "requests"
    )
    
    for package in "${pip_packages[@]}"; do
        log_message "Eltávolítás: $package..."
        pip3 uninstall -y $package || true
    done
    
    # System packages via apt
    log_message "Rendszer csomagok eltávolítása..."
    sudo apt-get remove -y python3-pil python3-numpy python3-requests \
                          python3-rpi.gpio python3-spidev python3-gpiozero || true
    
    log_message "Autoremove futtatása a nem használt csomagok tisztításához..."
    sudo apt-get autoremove -y
    
    log_message "Függőségek eltávolítva (ahol lehetséges)"
else
    log_message "Függőségek nem lettek eltávolítva a felhasználó választása miatt"
fi

log_message "=== LÉPÉS 5: SPI konfiguráció ==="
# Ask if user wants to disable SPI
read -p "Szeretnéd letiltani az SPI interfészt? Csak akkor tedd ezt, ha más alkalmazás nem használja. (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_message "SPI interfész letiltása..."
    
    # Create a backup of config.txt
    sudo cp /boot/config.txt /boot/config.txt.backup
    
    # Remove SPI enable line
    sudo sed -i '/dtparam=spi=on/d' /boot/config.txt
    
    log_message "SPI interfész letiltva a konfigban. Újraindítás után lép érvénybe."
    REBOOT_NEEDED=true
else
    log_message "SPI interfész engedélyezve marad"
fi

log_message "=== Eltávolítás kész ==="
log_message "Az E-Paper Naptár alkalmazás sikeresen eltávolítva."

# Notify about reboot if needed
if [ "$REBOOT_NEEDED" = true ]; then
    log_message "Ajánlott az újraindítás az eltávolítási folyamat befejezéséhez."
    read -p "Szeretnél most újraindítani? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_message "Rendszer újraindítása..."
        sudo reboot
    else
        log_message "Kérlek, indítsd újra kézzel, amikor alkalmas."
    fi
fi

echo "======================================================"
echo "E-Paper Calendar Display eltávolítás befejezve!"
echo "Minden komponens eltávolítva."
echo "======================================================"

exit 0
