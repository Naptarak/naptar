#!/bin/bash

# E-Paper Calendar Display Uninstaller (JAVÍTOTT VERZIÓ)
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-paper HAT

echo "======================================================"
echo "E-Paper Calendar Display Uninstaller (JAVÍTOTT VERZIÓ)"
echo "Raspberry Pi Zero 2W + Waveshare 4.01 inch 7-color HAT"
echo "======================================================"

# Create log file
LOG_FILE="/home/pi/epaper_calendar_uninstall.log"
touch $LOG_FILE
echo "$(date) - Starting uninstallation" > $LOG_FILE

# Function to log messages
log_message() {
    echo "$(date) - $1" >> $LOG_FILE
    echo "$1"
}

# Function to check if a command was successful
check_success() {
    if [ $? -ne 0 ]; then
        log_message "ERROR: $1 failed. Check $LOG_FILE for details."
        exit 1
    else
        log_message "SUCCESS: $1 completed."
    fi
}

# Stop and disable the systemd service
log_message "Stopping and disabling systemd service..."
sudo systemctl stop epaper-calendar.service >> $LOG_FILE 2>&1
sudo systemctl disable epaper-calendar.service >> $LOG_FILE 2>&1
sudo rm -f /etc/systemd/system/epaper-calendar.service >> $LOG_FILE 2>&1
sudo systemctl daemon-reload >> $LOG_FILE 2>&1
check_success "systemd service removal"

# Clear the e-paper display if possible
log_message "Trying to clear the e-paper display..."
cd /home/pi/epaper_calendar
if [ -f "epaper_calendar.py" ]; then
    # Create a small Python script to clear the display
    cat > clear_display.py << 'EOL'
#!/usr/bin/env python3
import os
import sys
import logging
import traceback

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/home/pi/epaper_clear.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Add the waveshare_epd directory to the system path
current_dir = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(current_dir, "waveshare_epd"))

try:
    logger.info("Importing epd4in01f module...")
    from waveshare_epd import epd4in01f
    
    logger.info("Initializing display...")
    epd = epd4in01f.EPD()
    epd.init()
    
    logger.info("Clearing display...")
    epd.Clear()
    
    logger.info("Putting display to sleep...")
    epd.sleep()
    
    print("Display cleared successfully.")
except Exception as e:
    logger.error(f"Error clearing display: {e}")
    logger.error(traceback.format_exc())
    print(f"Error clearing display: {e}")
EOL

    # Make the script executable and run it
    chmod +x clear_display.py
    python3 clear_display.py >> $LOG_FILE 2>&1
    rm clear_display.py
fi

# Delete log files
log_message "Removing log files..."
rm -f /home/pi/epaper_calendar.log >> $LOG_FILE 2>&1
rm -f /home/pi/epaper_test.log >> $LOG_FILE 2>&1
rm -f /home/pi/epaper_clear.log >> $LOG_FILE 2>&1

# Remove the project directory
log_message "Removing project directory..."
rm -rf /home/pi/epaper_calendar >> $LOG_FILE 2>&1
check_success "project directory removal"

# Ask if the user wants to remove dependencies
read -p "Do you want to remove installed dependencies? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_message "Removing dependencies (this may not remove all dependencies)..."
    sudo apt-get remove -y python3-pil python3-numpy python3-requests python3-rpi.gpio python3-spidev python3-gpiozero >> $LOG_FILE 2>&1
    
    # Remove pip packages
    pip3 uninstall -y RPi.GPIO spidev feedparser python-dateutil astral Pillow numpy requests >> $LOG_FILE 2>&1
    
    sudo apt-get autoremove -y >> $LOG_FILE 2>&1
    log_message "Dependencies removed."
else
    log_message "Dependencies were not removed."
fi

# Uninstallation completed
log_message "======================================================"
log_message "E-Paper Calendar Display uninstallation completed!"
log_message "All components have been removed."

exit 0
