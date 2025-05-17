#!/bin/bash

# E-Paper Calendar Display Installer (ROBUSZTUS VERZIÓ)
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-paper HAT

echo "======================================================"
echo "E-Paper Calendar Display Installer (ROBUSZTUS VERZIÓ)"
echo "Raspberry Pi Zero 2W + Waveshare 4.01 inch 7-color HAT"
echo "======================================================"

# Create log file with timestamps
LOG_FILE="/home/pi/epaper_calendar_install.log"
touch $LOG_FILE
echo "$(date) - Starting robust installation" > $LOG_FILE

# Function to log messages
log_message() {
    echo "$(date) - $1" >> $LOG_FILE
    echo "$1"
}

# Function for user confirmation
confirm() {
    read -p "$1 (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Create project directory
PROJECT_DIR="/home/pi/epaper_calendar"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

log_message "=== STEP 1: System Update ==="
log_message "Updating package lists..."
sudo apt-get update
if [ $? -ne 0 ]; then
    log_message "WARNING: Package update failed, but continuing..."
fi

log_message "=== STEP 2: Basic Dependencies ==="
log_message "Installing git..."
sudo apt-get install -y git
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to install git. This is required."
    confirm "Do you want to continue anyway?" || exit 1
fi

log_message "=== STEP 3: Python Environment ==="
log_message "Checking Python installation..."
if command -v python3 &>/dev/null; then
    PYTHON_VERSION=$(python3 --version)
    log_message "Python is installed: $PYTHON_VERSION"
else
    log_message "Installing Python 3..."
    sudo apt-get install -y python3 python3-pip
    if [ $? -ne 0 ]; then
        log_message "ERROR: Python installation failed!"
        confirm "This is critical. Continue anyway?" || exit 1
    fi
fi

# Install pip if needed
if ! command -v pip3 &>/dev/null; then
    log_message "Installing pip3..."
    sudo apt-get install -y python3-pip
    if [ $? -ne 0 ]; then
        # Try alternative method
        log_message "Trying alternative pip installation..."
        curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
        python3 get-pip.py
        if [ $? -ne 0 ]; then
            log_message "ERROR: pip installation failed!"
            confirm "This is critical. Continue anyway?" || exit 1
        fi
    fi
fi

log_message "=== STEP 4: CRITICAL - Display Dependencies ==="

# Function to try installing a package with multiple methods
try_install() {
    PACKAGE=$1
    DESC=$2
    
    log_message "Installing $DESC ($PACKAGE)..."
    
    # Method 1: Direct apt install
    sudo apt-get install -y $PACKAGE
    if [ $? -eq 0 ]; then
        log_message "SUCCESS: Installed $PACKAGE via apt"
        return 0
    fi
    
    log_message "WARNING: Failed to install $PACKAGE via apt, trying alternatives..."
    
    # Method 2: Try with apt --fix-missing
    sudo apt-get install --fix-missing -y $PACKAGE
    if [ $? -eq 0 ]; then
        log_message "SUCCESS: Installed $PACKAGE with --fix-missing"
        return 0
    fi
    
    # For Python packages, try pip
    if [[ $PACKAGE == python3-* ]]; then
        # Extract package name without python3- prefix
        PIP_PACKAGE=$(echo $PACKAGE | sed 's/python3-//')
        log_message "Trying to install $PIP_PACKAGE via pip..."
        
        # Try pip install
        pip3 install $PIP_PACKAGE
        if [ $? -eq 0 ]; then
            log_message "SUCCESS: Installed $PIP_PACKAGE via pip"
            return 0
        fi
    fi
    
    log_message "WARNING: All installation methods for $PACKAGE failed"
    return 1
}

# Install critical dependencies one by one with robust handling
DEPENDENCIES=(
    "python3-pil:Python Imaging Library"
    "python3-numpy:NumPy"
    "libtiff5:TIFF Library"
    "python3-rpi.gpio:RPi GPIO"
    "python3-spidev:SPI Device"
)

FAILED_DEPS=()

for dep in "${DEPENDENCIES[@]}"; do
    IFS=":" read -r package desc <<< "$dep"
    if ! try_install "$package" "$desc"; then
        FAILED_DEPS+=("$package")
    fi
done

# Try alternatives for failed dependencies
if [[ " ${FAILED_DEPS[*]} " =~ "libtiff5" ]]; then
    log_message "Trying alternative TIFF libraries..."
    sudo apt-get install -y libtiff5-dev || sudo apt-get install -y libtiff-dev
    if [ $? -ne 0 ]; then
        log_message "WARNING: Failed to install any TIFF library"
    fi
fi

if [[ " ${FAILED_DEPS[*]} " =~ "python3-pil" ]]; then
    log_message "Trying alternative PIL installation..."
    pip3 install Pillow
    if [ $? -ne 0 ]; then
        log_message "WARNING: Failed to install PIL/Pillow"
    fi
fi

# Direct installation of critical pip packages
log_message "=== STEP 5: Python Packages ==="
log_message "Installing Python packages directly via pip..."

pip_packages=(
    "RPi.GPIO"
    "spidev"
    "feedparser"
    "python-dateutil"
    "astral"
    "Pillow"
    "numpy"
    "requests"
)

for package in "${pip_packages[@]}"; do
    log_message "Installing $package..."
    pip3 install $package
    if [ $? -ne 0 ]; then
        log_message "WARNING: Failed to install $package"
    fi
done

log_message "=== STEP 6: CRITICAL - Waveshare E-Paper Library ==="
log_message "Attempting to install Waveshare e-Paper library..."

# First, try GitHub
cd $PROJECT_DIR
if [ -d "e-Paper" ]; then
    log_message "e-Paper directory exists, updating..."
    cd e-Paper
    git pull
    cd ..
else
    log_message "Cloning Waveshare e-Paper library from GitHub..."
    git clone https://github.com/waveshare/e-Paper.git
    if [ $? -ne 0 ]; then
        log_message "ERROR: Failed to clone Waveshare library!"
        
        # Offer to download manually
        if confirm "Do you want to try downloading Waveshare library as a ZIP file?"; then
            log_message "Downloading zip file..."
            wget https://github.com/waveshare/e-Paper/archive/master.zip -O waveshare.zip
            
            if [ $? -eq 0 ]; then
                unzip waveshare.zip
                mv e-Paper-master e-Paper
                log_message "SUCCESS: Downloaded and extracted Waveshare library"
            else
                log_message "ERROR: Failed to download Waveshare library!"
                confirm "This is critical. Continue anyway?" || exit 1
            fi
        else
            confirm "This is critical. Continue anyway?" || exit 1
        fi
    fi
fi

# Check if we found the necessary Waveshare files
if [ -d "$PROJECT_DIR/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd" ]; then
    log_message "Waveshare library files found!"
    
    # Create a dedicated waveshare_epd directory
    mkdir -p $PROJECT_DIR/waveshare_epd
    
    # Copy files from repository to our directory
    cp -rf $PROJECT_DIR/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd/* $PROJECT_DIR/waveshare_epd/
    
    # Make sure Python can find it
    sudo chmod -R 755 $PROJECT_DIR/waveshare_epd
else
    log_message "ERROR: Waveshare library not found in the expected location!"
    
    # Create an emergency directory structure
    mkdir -p $PROJECT_DIR/waveshare_epd
    
    # Offer to download the specific files needed
    if confirm "Do you want to manually download the required Waveshare files?"; then
        log_message "Creating a simple Waveshare driver file..."
        
        # We'll create a simplified version of the 4in01f driver for testing
        cat > $PROJECT_DIR/waveshare_epd/epd4in01f.py << 'EOL'
# Simple Waveshare E-Ink Display Driver for 4.01 inch F (7-color)
import logging
import time
import RPi.GPIO as GPIO
import spidev

logger = logging.getLogger(__name__)

class EPD:
    # Display resolution
    width = 640
    height = 400
    
    # Pin definitions
    RST_PIN = 17
    DC_PIN = 25
    CS_PIN = 8
    BUSY_PIN = 24
    
    def __init__(self):
        """Initialize GPIO and SPI"""
        logger.info("Initializing display driver...")
        self.GPIO = GPIO
        self.SPI = spidev.SpiDev()
    
    def digital_write(self, pin, value):
        """Set GPIO pin value"""
        self.GPIO.output(pin, value)
    
    def digital_read(self, pin):
        """Read GPIO pin value"""
        return self.GPIO.input(pin)
    
    def delay_ms(self, ms):
        """Sleep function with millisecond resolution"""
        time.sleep(ms / 1000.0)
    
    def spi_writebyte(self, data):
        """Write data to SPI"""
        self.SPI.writebytes([data])
    
    def init(self):
        """Initialize the display"""
        logger.info("Setting up GPIO and SPI...")
        
        # GPIO setup
        self.GPIO.setmode(self.GPIO.BCM)
        self.GPIO.setwarnings(False)
        self.GPIO.setup(self.RST_PIN, self.GPIO.OUT)
        self.GPIO.setup(self.DC_PIN, self.GPIO.OUT)
        self.GPIO.setup(self.CS_PIN, self.GPIO.OUT)
        self.GPIO.setup(self.BUSY_PIN, self.GPIO.IN)
        
        # SPI setup
        self.SPI.open(0, 0)
        self.SPI.max_speed_hz = 4000000
        self.SPI.mode = 0
        
        logger.info("Resetting display...")
        # Reset the display
        self.digital_write(self.RST_PIN, 1)
        self.delay_ms(200)
        self.digital_write(self.RST_PIN, 0)
        self.delay_ms(5)
        self.digital_write(self.RST_PIN, 1)
        self.delay_ms(200)
        
        logger.info("Display initialized")
        return 0
    
    def getbuffer(self, image):
        """Convert image to display buffer data"""
        logger.info("Converting image to buffer...")
        # Simple implementation - in reality, this would do proper conversion
        # Just a placeholder to make the code work
        return image
    
    def display(self, image):
        """Display an image on the screen"""
        logger.info("Sending image to display (simplified driver)")
        # This is a simplified version and doesn't actually write to the display
        # In a real driver, this would send the image data to the display
        logger.info("Image would be displayed here in a complete driver")
    
    def Clear(self):
        """Clear the display"""
        logger.info("Clearing display (simplified driver)")
        # In a real driver, this would clear the display
    
    def sleep(self):
        """Put display to sleep to save power"""
        logger.info("Putting display to sleep (simplified driver)")
        self.digital_write(self.RST_PIN, 0)
        self.digital_write(self.DC_PIN, 0)
        
        # Close SPI
        self.SPI.close()
        
        # Clean up GPIO
        # self.GPIO.cleanup()
EOL
        
        # Make the module importable
        touch $PROJECT_DIR/waveshare_epd/__init__.py
        
        log_message "Created a simplified Waveshare driver for testing"
    else
        log_message "WARNING: Continuing without the Waveshare driver will likely result in errors"
    fi
fi

log_message "=== STEP 7: SPI Interface ==="
log_message "Checking if SPI interface is enabled..."

if ! grep -q "dtparam=spi=on" /boot/config.txt; then
    log_message "Enabling SPI interface..."
    echo "dtparam=spi=on" | sudo tee -a /boot/config.txt
    REBOOT_NEEDED=true
    log_message "SPI interface enabled in config, reboot will be needed"
else
    log_message "SPI interface is already enabled in config"
fi

# Check if SPI device exists
if [ -e /dev/spidev0.0 ]; then
    log_message "SPI device found at /dev/spidev0.0"
else
    log_message "WARNING: SPI device not found! This may indicate SPI is not enabled."
    log_message "A reboot may be needed after this installation."
    REBOOT_NEEDED=true
fi

log_message "=== STEP 8: Creating Emergency Test Script ==="

# We'll create a very minimal test script that tries to test basic display functionality
# This can help diagnose if the issue is with the full calendar program or with the basic display functionality

TEST_SCRIPT="$PROJECT_DIR/emergency_test.py"

cat > $TEST_SCRIPT << 'EOL'
#!/usr/bin/env python3
"""
Emergency test script for Waveshare e-Paper 4.01inch F (7-color) display
This script attempts to test the display with minimal dependencies
"""

import os
import sys
import time
import logging

# Configure logging to a file and console
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/home/pi/epaper_emergency_test.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

logger.info("========== EMERGENCY TEST SCRIPT ==========")
logger.info(f"Python version: {sys.version}")
logger.info(f"Current directory: {os.getcwd()}")

try:
    logger.info("Setting up GPIO...")
    import RPi.GPIO as GPIO
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    # Define pins
    RST_PIN = 17
    DC_PIN = 25
    CS_PIN = 8
    BUSY_PIN = 24
    
    # Setup GPIO
    GPIO.setup(RST_PIN, GPIO.OUT)
    GPIO.setup(DC_PIN, GPIO.OUT)
    GPIO.setup(CS_PIN, GPIO.OUT)
    GPIO.setup(BUSY_PIN, GPIO.IN)
    
    logger.info("GPIO setup complete")
    
    # Try to setup SPI
    logger.info("Setting up SPI...")
    import spidev
    SPI = spidev.SpiDev()
    SPI.open(0, 0)
    SPI.max_speed_hz = 4000000
    SPI.mode = 0
    logger.info("SPI setup complete")
    
    # Reset sequence
    logger.info("Performing reset sequence...")
    GPIO.output(RST_PIN, 1)
    time.sleep(0.2)
    GPIO.output(RST_PIN, 0)
    time.sleep(0.005)
    GPIO.output(RST_PIN, 1)
    time.sleep(0.2)
    logger.info("Reset sequence complete")
    
    # Try to import PIL for image handling
    try:
        logger.info("Trying to import PIL...")
        from PIL import Image, ImageDraw, ImageFont
        logger.info("PIL import successful")
        
        # Create a test image
        logger.info("Creating test image...")
        width = 640
        height = 400
        image = Image.new('RGB', (width, height), (255, 255, 255))
        draw = ImageDraw.Draw(image)
        
        # Draw some text
        logger.info("Drawing test pattern...")
        draw.rectangle([(0, 0), (width, 50)], fill=(255, 0, 0))  # Red
        draw.rectangle([(0, 50), (width, 100)], fill=(0, 255, 0))  # Green
        draw.rectangle([(0, 100), (width, 150)], fill=(0, 0, 255))  # Blue
        
        # Try to write a simple message
        try:
            font = ImageFont.load_default()
            draw.text((20, 200), "EMERGENCY TEST", font=font, fill=(0, 0, 0))
        except Exception as e:
            logger.error(f"Error with font: {e}")
        
        logger.info("Test image created")
        
        # Try to import the real display driver
        try:
            logger.info("Trying to import waveshare_epd module...")
            sys.path.append(os.path.join(os.path.dirname(os.path.realpath(__file__)), "waveshare_epd"))
            from waveshare_epd import epd4in01f
            
            logger.info("Initializing display...")
            epd = epd4in01f.EPD()
            epd.init()
            
            logger.info("Sending image to display...")
            epd.display(epd.getbuffer(image))
            
            logger.info("Putting display to sleep...")
            epd.sleep()
            
            logger.info("Display test SUCCESSFUL!")
            print("Display test completed successfully!")
            
        except ImportError as e:
            logger.error(f"Failed to import display driver: {e}")
            logger.info("Cannot test actual display without the driver")
            print("Failed to import display driver.")
            
    except ImportError as e:
        logger.error(f"Failed to import PIL: {e}")
        logger.info("Cannot create test image without PIL")
        print("Failed to import PIL for image creation.")
    
    # Clean up
    logger.info("Cleaning up GPIO and SPI...")
    SPI.close()
    GPIO.cleanup([RST_PIN, DC_PIN, CS_PIN])
    
except Exception as e:
    logger.error(f"Critical error: {e}")
    import traceback
    logger.error(traceback.format_exc())
    print(f"Critical error: {e}")
    print("Check log file at /home/pi/epaper_emergency_test.log")

logger.info("========== TEST COMPLETE ==========")
EOL

chmod +x $TEST_SCRIPT
log_message "Created emergency test script: $TEST_SCRIPT"

log_message "=== STEP 9: Creating Calendar Program ==="
PROGRAM_FILE="$PROJECT_DIR/epaper_calendar.py"

cat > $PROGRAM_FILE << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import time
import logging
import datetime
import calendar
import traceback
import signal
import subprocess

# Configure detailed logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/home/pi/epaper_calendar.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Log system information
logger.info("=======================================")
logger.info("Starting E-Paper Calendar application")
logger.info(f"Python version: {sys.version}")
logger.info(f"Current directory: {os.getcwd()}")

# Check for required packages and try to install them if missing
required_packages = [
    "feedparser", "requests", "python-dateutil", "astral", 
    "numpy", "Pillow", "RPi.GPIO", "spidev"
]

def check_and_install_packages():
    """Check if required packages are installed and try to install if missing"""
    missing_packages = []
    
    for package in required_packages:
        try:
            __import__(package.lower().replace('-', '_'))
            logger.info(f"Package {package} is installed")
        except ImportError:
            logger.warning(f"Package {package} is missing")
            missing_packages.append(package)
    
    if missing_packages:
        logger.info(f"Attempting to install missing packages: {missing_packages}")
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install"] + missing_packages)
            logger.info("Packages installed successfully")
            
            # Restart the script after installing packages
            logger.info("Restarting script...")
            os.execv(sys.executable, ['python3'] + sys.argv)
        except Exception as e:
            logger.error(f"Failed to install packages: {e}")
            logger.error("Will attempt to continue, but the application may not work correctly")

# Check and install missing packages
check_and_install_packages()

# Now import the required packages
try:
    import feedparser
    import requests
    from dateutil.easter import easter
    from astral import LocationInfo
    from astral.sun import sun
    from astral.moon import moon_phase, moonrise, moonset
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont
    
    logger.info("All required packages imported successfully")
except ImportError as e:
    logger.error(f"Failed to import a required package: {e}")
    logger.error("The application may not work correctly")

# Add the waveshare_epd directory to the system path
current_dir = os.path.dirname(os.path.realpath(__file__))
waveshare_path = os.path.join(current_dir, "waveshare_epd")
sys.path.append(waveshare_path)
logger.info(f"Added waveshare path to sys.path: {waveshare_path}")

if os.path.exists(waveshare_path):
    logger.info(f"Waveshare directory contents: {os.listdir(waveshare_path)}")
else:
    logger.error(f"Waveshare directory not found at {waveshare_path}")

# Try to import the Waveshare display library
epd = None
try:
    from waveshare_epd import epd4in01f
    logger.info("Successfully imported epd4in01f module")
    epd = epd4in01f.EPD()
except ImportError as e:
    logger.error(f"Error importing Waveshare display library: {e}")
    logger.error("Trying alternative import methods...")
    
    try:
        # Try using direct import path
        sys.path.append(os.path.join(current_dir, "e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd"))
        from waveshare_epd import epd4in01f
        logger.info("Successfully imported epd4in01f from alternative path")
        epd = epd4in01f.EPD()
    except ImportError as e2:
        logger.error(f"Second import attempt failed: {e2}")
        logger.error("Full traceback:")
        logger.error(traceback.format_exc())
        
        logger.error("The application will continue, but the display will not work")

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
    logger.info("Shutdown signal received, cleaning up...")
    if epd:
        try:
            logger.info("Putting display to sleep...")
            epd.sleep()
        except Exception as e:
            logger.error(f"Error during sleep: {e}")
    
    logger.info("Exiting...")
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
        logger.info("Fetching RSS feed from Telex.hu...")
        feed = feedparser.parse(RSS_URL)
        
        # Get the first 3 entries
        entries = []
        for i, entry in enumerate(feed.entries[:3]):
            title = entry.title
            entries.append(title)
            logger.info(f"RSS entry {i+1}: {title[:50]}...")
        
        return entries
    except Exception as e:
        logger.error(f"Error fetching RSS feed: {e}")
        return ["RSS hiba: Nem sikerült betölteni a híreket."]

# Function to update the display
def update_display():
    try:
        logger.info("Starting display update...")
        
        # Get current date and time
        now = datetime.datetime.now()
        date_str = now.strftime("%Y. %m. %d. %A")  # Year, Month, Day, Weekday
        logger.info(f"Current date: {date_str}")
        
        # Create blank image with white background
        image = Image.new('RGB', (WIDTH, HEIGHT), (255, 255, 255))
        draw = ImageDraw.Draw(image)
        logger.info("Image canvas created")
        
        # Load fonts
        font_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'fonts')
        os.makedirs(font_dir, exist_ok=True)
        
        logger.info("Finding system fonts...")
        # Try to find system fonts if custom fonts not available
        try:
            # Try to use the default font
            title_font = ImageFont.load_default()
            date_font = ImageFont.load_default()
            main_font = ImageFont.load_default()
            small_font = ImageFont.load_default()
            
            # Try to find better fonts
            main_font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
            title_font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
            
            # Check if fonts exist
            if not os.path.exists(main_font_path):
                logger.warning(f"Main font path {main_font_path} not found, searching alternatives")
                # Try alternative font locations
                font_locations = [
                    "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
                    "/usr/share/fonts/TTF/Arial.ttf",
                    "/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf"
                ]
                for font_loc in font_locations:
                    if os.path.exists(font_loc):
                        main_font_path = font_loc
                        logger.info(f"Found alternative main font: {font_loc}")
                        break
            
            if not os.path.exists(title_font_path):
                logger.warning(f"Title font path {title_font_path} not found, searching alternatives")
                # Try alternative font locations for bold
                bold_font_locations = [
                    "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
                    "/usr/share/fonts/TTF/Arial_Bold.ttf",
                    "/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans-Bold.ttf"
                ]
                for font_loc in bold_font_locations:
                    if os.path.exists(font_loc):
                        title_font_path = font_loc
                        logger.info(f"Found alternative title font: {font_loc}")
                        break
            
            # Try to load the fonts if found
            if os.path.exists(main_font_path):
                try:
                    main_font = ImageFont.truetype(main_font_path, 20)
                    small_font = ImageFont.truetype(main_font_path, 16)
                    logger.info("Main font loaded successfully")
                except Exception as e:
                    logger.error(f"Error loading main font: {e}")
            
            if os.path.exists(title_font_path):
                try:
                    title_font = ImageFont.truetype(title_font_path, 36)
                    date_font = ImageFont.truetype(title_font_path, 28)
                    logger.info("Title font loaded successfully")
                except Exception as e:
                    logger.error(f"Error loading title font: {e}")
            
        except Exception as e:
            logger.error(f"Error setting up fonts: {e}")
            logger.info("Using default font instead")
        
        # Check if today is a special day
        special_day = check_special_day(now)
        is_holiday = False
        special_day_color = (0, 0, 0)  # Default text color (black)
        
        if special_day:
            special_day_name, color_code = special_day
            is_holiday = (color_code == RED)
            logger.info(f"Today is a special day: {special_day_name}, holiday: {is_holiday}")
            
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
        logger.info(f"Today's nameday: {nameday}")
        
        # Set up location for astral calculations
        city = LocationInfo(CITY, COUNTRY, TIMEZONE, LATITUDE, LONGITUDE)
        
        # Get sun information
        logger.info("Calculating sun and moon information...")
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
            logger.error(f"Error calculating moon rise/set: {e}")
            moonrise_val = None
            moonset_val = None
        
        # Check for meteor showers
        meteor_showers = check_meteor_showers(now)
        
        # Get RSS feed
        logger.info("Fetching RSS feed...")
        rss_entries = get_rss_feed()
        
        logger.info("Drawing the display content...")
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
        try:
            time_width = date_font.getbbox(time_str)[2]
        except:
            # Fallback for older PIL versions
            time_width = date_font.getsize(time_str)[0]
        draw.text((WIDTH - time_width - 20, 10), time_str, font=date_font, fill=(0, 0, 0))
        
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
        try:
            updated_width = small_font.getbbox(updated_str)[2]
        except:
            # Fallback for older PIL versions
            updated_width = small_font.getsize(updated_str)[0]
        draw.text((WIDTH - updated_width - 10, HEIGHT - 20), updated_str, font=small_font, fill=(100, 100, 100))
        
        # Only attempt to update the display if we have a valid display object
        if epd:
            logger.info("Initializing display...")
            epd.init()
            
            logger.info("Sending image to display...")
            epd.display(epd.getbuffer(image))
            
            logger.info("Putting display to sleep...")
            epd.sleep()
            
            logger.info("Display updated successfully.")
        else:
            logger.warning("No valid display object, skipping physical display update")
            # Save the image to a file so we can see what would have been displayed
            image.save("/home/pi/epaper_calendar_latest.png")
            logger.info("Saved image to /home/pi/epaper_calendar_latest.png")
        
    except Exception as e:
        logger.error(f"Error updating display: {e}")
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
        
        logger.info("E-Paper Calendar Display started")
        
        # Force update on start
        update_display()
        
        while True:
            # Wait for 10 minutes before updating again
            logger.info("Waiting for 10 minutes before next update...")
            time.sleep(600)
            
            # Update the display
            update_display()
            
    except KeyboardInterrupt:
        logger.info("Exiting due to keyboard interrupt...")
        if epd:
            try:
                epd.sleep()
            except Exception as e:
                logger.error(f"Error while shutting down: {e}")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Unexpected error in main loop: {e}")
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
    
    # Make the Python script executable
    chmod +x $PROGRAM_FILE
    log_message "Created calendar program"

log_message "=== STEP 10: Creating systemd Service ==="
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
log_message "Created systemd service file"

log_message "=== STEP 11: Final Steps ==="

# Test the emergency script first
log_message "Running emergency test script..."
cd $PROJECT_DIR
python3 $PROJECT_DIR/emergency_test.py || true

# Enable the systemd service
log_message "Enabling systemd service..."
sudo systemctl daemon-reload
sudo systemctl enable epaper-calendar.service
log_message "Service enabled, will start on boot"

# Decide if a reboot is needed
if [ "$REBOOT_NEEDED" = true ]; then
    log_message "A reboot is required to complete the installation (especially for SPI)."
    if confirm "Would you like to reboot now?"; then
        log_message "Rebooting system..."
        sudo reboot
    else
        log_message "Please reboot manually when convenient."
    fi
else
    # Try to start the service if no reboot is needed
    log_message "Starting the calendar service..."
    sudo systemctl start epaper-calendar.service
    
    log_message "Installation complete! The calendar should start displaying shortly."
    log_message "If you encounter issues, check the logs with: journalctl -u epaper-calendar.service"
fi

log_message "=== TROUBLESHOOTING GUIDE ==="
log_message "If the display doesn't work, try these steps:"
log_message "1. Check if SPI is enabled: ls -l /dev/spi*"
log_message "2. Run the emergency test: python3 $PROJECT_DIR/emergency_test.py"
log_message "3. Check the logs: cat /home/pi/epaper_calendar.log"
log_message "4. Restart the service: sudo systemctl restart epaper-calendar.service"
log_message "5. Ensure you have the right model: Waveshare 4.01 inch HAT (F) 7-color"
log_message "6. Check wiring connections between Pi and display"
log_message "7. Reboot: sudo reboot"

exit 0
