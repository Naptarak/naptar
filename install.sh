#!/bin/bash

# E-Paper Calendar Display Installer
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-paper HAT

echo "======================================================"
echo "E-Paper Calendar Display Installer"
echo "Raspberry Pi Zero 2W + Waveshare 4.01 inch 7-color HAT"
echo "======================================================"

# Create log file
LOG_FILE="/home/pi/epaper_calendar_install.log"
touch $LOG_FILE
echo "$(date) - Starting installation" > $LOG_FILE

# Function to log messages
log_message() {
    echo "$(date) - $1" >> $LOG_FILE
    echo "$1"
}

# Function to check if a command was successful
check_success() {
    if [ $? -ne 0 ]; then
        log_message "ERROR: $1 failed. Check $LOG_FILE for details."
        log_message "You can try running the installation again or fix the issue manually."
        exit 1
    else
        log_message "SUCCESS: $1 completed."
    fi
}

# Function to install Python if needed
install_python() {
    log_message "Checking Python installation..."
    
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_VERSION=$(python3 --version)
        log_message "Python is already installed: $PYTHON_VERSION"
    else
        log_message "Python not found. Installing Python 3..."
        sudo apt-get update >> $LOG_FILE 2>&1
        sudo apt-get install -y python3 python3-pip >> $LOG_FILE 2>&1
        check_success "Python installation"
    fi
    
    # Ensure pip is installed
    if ! command -v pip3 >/dev/null 2>&1; then
        log_message "Installing pip3..."
        sudo apt-get install -y python3-pip >> $LOG_FILE 2>&1
        check_success "pip3 installation"
    fi
}

# Function to install required system packages
install_dependencies() {
    log_message "Installing system dependencies..."
    
    # Update package lists
    log_message "Updating package lists..."
    sudo apt-get update >> $LOG_FILE 2>&1
    check_success "Package list update"
    
    # Essential packages
    log_message "Installing essential packages..."
    sudo apt-get install -y git python3-pil python3-numpy python3-requests >> $LOG_FILE 2>&1
    check_success "Essential packages installation"
    
    # Try different approaches for problematic packages
    log_message "Installing potentially problematic packages (wiringpi, libtiff5)..."
    
    # First attempt - standard installation
    if ! sudo apt-get install -y wiringpi >> $LOG_FILE 2>&1; then
        log_message "Standard wiringpi installation failed. Trying alternative method..."
        
        # Alternative 1 - Use GPIO Zero instead
        log_message "Installing GPIO Zero as an alternative to wiringpi..."
        sudo apt-get install -y python3-gpiozero >> $LOG_FILE 2>&1
        
        # If that also fails, try the git version
        if [ $? -ne 0 ]; then
            log_message "GPIO Zero installation failed. Trying to install wiringpi from source..."
            cd /tmp
            git clone https://github.com/WiringPi/WiringPi --depth 1 >> $LOG_FILE 2>&1
            cd WiringPi
            ./build >> $LOG_FILE 2>&1
            
            if [ $? -ne 0 ]; then
                log_message "WARNING: All wiringpi installation methods failed. The display may not work correctly."
                log_message "You may need to manually install wiringpi."
            else
                log_message "Successfully installed wiringpi from source."
            fi
        fi
    fi
    
    # Try to install libtiff5
    if ! sudo apt-get install -y libtiff5 >> $LOG_FILE 2>&1; then
        log_message "Standard libtiff5 installation failed. Trying alternative method..."
        
        # Alternative - Try libtiff5-dev
        if ! sudo apt-get install -y libtiff5-dev >> $LOG_FILE 2>&1; then
            # Another alternative - Try libtiff-dev
            if ! sudo apt-get install -y libtiff-dev >> $LOG_FILE 2>&1; then
                log_message "WARNING: All libtiff installation methods failed. The display may not work correctly."
                log_message "You may need to manually install libtiff."
            else
                log_message "Successfully installed libtiff-dev as an alternative."
            fi
        else
            log_message "Successfully installed libtiff5-dev as an alternative."
        fi
    fi
    
    # Additional required packages
    log_message "Installing additional required packages..."
    sudo apt-get install -y python3-rpi.gpio python3-spidev python3-feedparser python3-dateutil python3-astral >> $LOG_FILE 2>&1
    
    if [ $? -ne 0 ]; then
        log_message "WARNING: Some additional packages could not be installed via apt. Trying pip installation..."
        
        # Try installing via pip if apt fails
        pip3 install RPi.GPIO spidev feedparser python-dateutil astral >> $LOG_FILE 2>&1
        
        if [ $? -ne 0 ]; then
            log_message "WARNING: Some pip installations failed. You may need to manually install missing packages."
        else
            log_message "Successfully installed packages via pip."
        fi
    fi
}

# Function to install Waveshare e-paper display library
install_waveshare_library() {
    log_message "Installing Waveshare e-paper display library..."
    
    # Create directory for the project
    PROJECT_DIR="/home/pi/epaper_calendar"
    mkdir -p $PROJECT_DIR
    cd $PROJECT_DIR
    
    # Clone Waveshare e-paper library
    if [ -d "e-Paper" ]; then
        log_message "Waveshare library directory already exists. Updating..."
        cd e-Paper
        git pull >> $LOG_FILE 2>&1
        cd ..
    else
        log_message "Cloning Waveshare e-paper library..."
        git clone https://github.com/waveshare/e-Paper.git >> $LOG_FILE 2>&1
        check_success "Waveshare library cloning"
    fi
    
    # Check if we can find the correct display driver
    if [ ! -d "e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd" ]; then
        log_message "ERROR: Could not find Waveshare library files. The repository structure may have changed."
        log_message "Please check the Waveshare GitHub repository and update the script accordingly."
        exit 1
    fi
    
    # Create symbolic link to the library
    ln -sf $PROJECT_DIR/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd $PROJECT_DIR/waveshare_epd
    check_success "Waveshare library symbolic link creation"
    
    # Set SPI interface to be enabled
    log_message "Enabling SPI interface..."
    if ! grep -q "dtparam=spi=on" /boot/config.txt; then
        echo "dtparam=spi=on" | sudo tee -a /boot/config.txt >> $LOG_FILE 2>&1
        log_message "SPI interface enabled. A reboot will be required."
        REBOOT_NEEDED=true
    else
        log_message "SPI interface is already enabled."
    fi
}

# Function to create the Python calendar program
create_calendar_program() {
    log_message "Creating the Python calendar program..."
    
    PROJECT_DIR="/home/pi/epaper_calendar"
    PROGRAM_FILE="$PROJECT_DIR/epaper_calendar.py"
    
    # Write the Python program
    cat > $PROGRAM_FILE << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import time
import logging
import datetime
import calendar
import feedparser
import requests
from dateutil.easter import easter
from astral import LocationInfo
from astral.sun import sun
from astral.moon import moon_phase, moonrise, moonset
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Add the waveshare_epd directory to the system path
current_dir = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(current_dir, "waveshare_epd"))

# Import the Waveshare display library
# Note: The specific import depends on the exact model. Adjust if needed.
try:
    from waveshare_epd import epd4in01f
except ImportError:
    print("Error importing Waveshare display library. Check if it's correctly installed.")
    print("Trying alternative import...")
    try:
        sys.path.append(os.path.join(current_dir, "e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd"))
        from waveshare_epd import epd4in01f
    except ImportError:
        print("Failed to import display library. Please check the installation.")
        sys.exit(1)

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
logger = logging.getLogger(__name__)

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
        feed = feedparser.parse(RSS_URL)
        
        # Get the first 3 entries
        entries = []
        for i, entry in enumerate(feed.entries[:3]):
            title = entry.title
            entries.append(title)
        
        return entries
    except Exception as e:
        logger.error(f"Error fetching RSS feed: {e}")
        return ["RSS hiba: Nem sikerült betölteni a híreket."]

# Function to update the display
def update_display():
    try:
        # Initialize display
        epd = epd4in01f.EPD()
        epd.init()
        
        # Create blank image with white background
        image = Image.new('RGB', (WIDTH, HEIGHT), (255, 255, 255))
        draw = ImageDraw.Draw(image)
        
        # Load fonts
        font_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'fonts')
        os.makedirs(font_dir, exist_ok=True)
        
        # Try to find system fonts if custom fonts not available
        try:
            main_font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
            title_font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
            if not os.path.exists(main_font_path):
                # Try alternative font locations
                font_locations = [
                    "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
                    "/usr/share/fonts/TTF/Arial.ttf",
                    "/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf"
                ]
                for font_loc in font_locations:
                    if os.path.exists(font_loc):
                        main_font_path = font_loc
                        break
            
            if not os.path.exists(title_font_path):
                # Try alternative font locations for bold
                bold_font_locations = [
                    "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
                    "/usr/share/fonts/TTF/Arial_Bold.ttf",
                    "/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans-Bold.ttf"
                ]
                for font_loc in bold_font_locations:
                    if os.path.exists(font_loc):
                        title_font_path = font_loc
                        break
            
            # Load fonts
            title_font = ImageFont.truetype(title_font_path, 36)
            date_font = ImageFont.truetype(title_font_path, 28)
            main_font = ImageFont.truetype(main_font_path, 20)
            small_font = ImageFont.truetype(main_font_path, 16)
            
        except Exception as e:
            logger.error(f"Error loading fonts: {e}. Using default font.")
            title_font = ImageFont.load_default()
            date_font = ImageFont.load_default()
            main_font = ImageFont.load_default()
            small_font = ImageFont.load_default()
        
        # Get current date and time
        now = datetime.datetime.now()
        date_str = now.strftime("%Y. %m. %d. %A")  # Year, Month, Day, Weekday
        
        # Check if today is a special day
        special_day = check_special_day(now)
        is_holiday = False
        special_day_color = (0, 0, 0)  # Default text color (black)
        
        if special_day:
            special_day_name, color_code = special_day
            is_holiday = (color_code == RED)
            
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
        
        # Set up location for astral calculations
        city = LocationInfo(CITY, COUNTRY, TIMEZONE, LATITUDE, LONGITUDE)
        
        # Get sun information
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
        except:
            moonrise_val = None
            moonset_val = None
        
        # Check for meteor showers
        meteor_showers = check_meteor_showers(now)
        
        # Get RSS feed
        rss_entries = get_rss_feed()
        
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
        time_size = date_font.getbbox(time_str)
        draw.text((WIDTH - time_size[2] - 20, 10), time_str, font=date_font, fill=(0, 0, 0))
        
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
        updated_size = small_font.getbbox(updated_str)
        draw.text((WIDTH - updated_size[2] - 10, HEIGHT - 20), updated_str, font=small_font, fill=(100, 100, 100))
        
        # Convert image to Waveshare format
        epd.display(epd.getbuffer(image))
        
        logger.info("Display updated successfully.")
        
    except Exception as e:
        logger.error(f"Error updating display: {e}")
    finally:
        if 'epd' in locals():
            epd.sleep()

# Main function
def main():
    try:
        # Create fonts directory if it doesn't exist
        font_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'fonts')
        os.makedirs(font_dir, exist_ok=True)
        
        logger.info("E-Paper Calendar Display started")
        
        while True:
            # Update the display
            update_display()
            
            # Wait for 10 minutes before updating again
            time.sleep(600)
            
    except KeyboardInterrupt:
        logger.info("Exiting...")
        epd = epd4in01f.EPD()
        epd.init()
        epd.sleep()
        sys.exit()

if __name__ == "__main__":
    main()
EOL
    
    # Make the Python script executable
    chmod +x $PROGRAM_FILE
    check_success "Python calendar program creation"
}

# Function to create the systemd service for autostart
create_systemd_service() {
    log_message "Creating systemd service for autostart..."
    
    SERVICE_FILE="/etc/systemd/system/epaper-calendar.service"
    
    sudo bash -c "cat > $SERVICE_FILE" << EOL
[Unit]
Description=E-Paper Calendar Display
After=network.target

[Service]
User=pi
WorkingDirectory=/home/pi/epaper_calendar
ExecStart=/usr/bin/python3 /home/pi/epaper_calendar/epaper_calendar.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL
    
    check_success "systemd service creation"
    
    # Enable and start the service
    log_message "Enabling and starting systemd service..."
    sudo systemctl daemon-reload >> $LOG_FILE 2>&1
    sudo systemctl enable epaper-calendar.service >> $LOG_FILE 2>&1
    sudo systemctl start epaper-calendar.service >> $LOG_FILE 2>&1
    check_success "systemd service activation"
}

# Main installation process
REBOOT_NEEDED=false

# 1. Install Python
install_python

# 2. Install dependencies
install_dependencies

# 3. Install Waveshare e-paper display library
install_waveshare_library

# 4. Create the Python calendar program
create_calendar_program

# 5. Create the systemd service for autostart
create_systemd_service

# Installation completed
log_message "======================================================"
log_message "E-Paper Calendar Display installation completed!"
log_message "The display should now start showing calendar information."
log_message "If the display doesn't work, check $LOG_FILE for details."

if [ "$REBOOT_NEEDED" = true ]; then
    log_message "A reboot is required to complete the installation."
    read -p "Would you like to reboot now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_message "Rebooting..."
        sudo reboot
    else
        log_message "Please reboot manually when convenient."
    fi
fi

exit 0
