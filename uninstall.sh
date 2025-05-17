#!/bin/bash

# E-Paper Calendar Display Uninstaller
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch 7-color e-paper HAT

echo "======================================================"
echo "E-Paper Calendar Display Uninstaller"
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

log_message "=== STEP 1: Stopping Services ==="
# Stop and disable the systemd service
log_message "Stopping and disabling systemd service..."
sudo systemctl stop epaper-calendar.service
sudo systemctl disable epaper-calendar.service
sudo rm -f /etc/systemd/system/epaper-calendar.service
sudo systemctl daemon-reload
log_message "Systemd service removed"

log_message "=== STEP 2: Clearing Display ==="
# Clear the e-paper display if possible
log_message "Attempting to clear the e-paper display..."

# Create a directory for the cleanup script if the project directory doesn't exist
if [ ! -d "/home/pi/epaper_calendar" ]; then
    mkdir -p /tmp/epaper_cleanup
    cd /tmp/epaper_cleanup
    CLEANUP_DIR="/tmp/epaper_cleanup"
else
    cd /home/pi/epaper_calendar
    CLEANUP_DIR="/home/pi/epaper_calendar"
fi

# Create a small Python script to clear the display
cat > $CLEANUP_DIR/clear_display.py << 'EOL'
#!/usr/bin/env python3
import os
import sys
import logging
import traceback
import time

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

try:
    # Try to set up GPIO first
    logger.info("Setting up GPIO...")
    import RPi.GPIO as GPIO
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    
    # Define pins for Waveshare 4.01 inch display
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
    
    # Try different approaches to clear the display
    
    # 1. First try with waveshare_epd if available
    try:
        logger.info("Trying to import waveshare_epd module...")
        
        # Check if we're in the project directory or temp directory
        current_dir = os.path.dirname(os.path.realpath(__file__))
        logger.info(f"Current directory: {current_dir}")
        
        # Try multiple paths
        paths_to_try = [
            os.path.join(current_dir, "waveshare_epd"),
            "/home/pi/epaper_calendar/waveshare_epd",
            os.path.join(current_dir, "e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd")
        ]
        
        for path in paths_to_try:
            if os.path.exists(path):
                logger.info(f"Found potential module path: {path}")
                sys.path.append(path)
        
        from waveshare_epd import epd4in01f
        
        logger.info("Initializing display...")
        epd = epd4in01f.EPD()
        epd.init()
        
        logger.info("Clearing display...")
        epd.Clear()
        
        logger.info("Putting display to sleep...")
        epd.sleep()
        
        print("Display cleared successfully using waveshare_epd.")
        
    except ImportError as e:
        logger.warning(f"Could not import waveshare_epd: {e}")
        logger.warning("Trying direct approach...")
        
        # 2. Try a more direct approach
        try:
            # Simple reset sequence
            logger.info("Performing reset sequence...")
            GPIO.output(RST_PIN, 1)
            time.sleep(0.2)
            GPIO.output(RST_PIN, 0)
            time.sleep(0.01)
            GPIO.output(RST_PIN, 1)
            time.sleep(0.2)
            
            # Send a few commands to try to clear/reset the display
            # These are generic commands that might work with many e-paper displays
            logger.info("Sending reset commands...")
            
            def send_command(command):
                GPIO.output(DC_PIN, 0)  # Command mode
                GPIO.output(CS_PIN, 0)
                SPI.writebytes([command])
                GPIO.output(CS_PIN, 1)
            
            # This is a generic approach - might not work for all displays
            # Try to send reset command
            send_command(0x12)  # SWRESET - Software reset
            time.sleep(0.1)
            
            # Put the display to sleep
            send_command(0x10)  # DEEP_SLEEP
            time.sleep(0.1)
            
            print("Attempted to clear display using direct GPIO/SPI commands.")
            
        except Exception as direct_error:
            logger.error(f"Direct approach failed: {direct_error}")
    
    # Clean up GPIO and SPI
    logger.info("Cleaning up...")
    try:
        SPI.close()
        GPIO.cleanup([RST_PIN, DC_PIN, CS_PIN])
    except:
        pass
    
except Exception as e:
    logger.error(f"Critical error: {e}")
    logger.error(traceback.format_exc())
    print(f"Error clearing display: {e}")

logger.info("Display cleanup complete")
EOL

# Make the script executable and run it
chmod +x $CLEANUP_DIR/clear_display.py
python3 $CLEANUP_DIR/clear_display.py

# Remove the temporary cleanup files if we created them
if [ "$CLEANUP_DIR" = "/tmp/epaper_cleanup" ]; then
    rm -rf /tmp/epaper_cleanup
fi

log_message "=== STEP 3: Removing Files ==="
# Delete log files
log_message "Removing log files..."
rm -f /home/pi/epaper_calendar.log
rm -f /home/pi/epaper_test.log
rm -f /home/pi/epaper_clear.log
rm -f /home/pi/epaper_emergency_test.log
rm -f /home/pi/epaper_calendar_latest.png

# Remove the project directory
if [ -d "/home/pi/epaper_calendar" ]; then
    log_message "Removing project directory..."
    rm -rf /home/pi/epaper_calendar
    log_message "Project directory removed"
else
    log_message "Project directory not found, already removed"
fi

log_message "=== STEP 4: Dependency Cleanup ==="
# Ask if the user wants to remove dependencies
if confirm "Do you want to remove installed dependencies? This might affect other applications."; then
    log_message "Removing dependencies..."
    
    # Python packages via pip
    log_message "Removing Python packages..."
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
        log_message "Uninstalling $package..."
        pip3 uninstall -y $package || true
    done
    
    # System packages via apt
    log_message "Removing system packages..."
    sudo apt-get remove -y python3-pil python3-numpy python3-requests \
                          python3-rpi.gpio python3-spidev python3-gpiozero || true
    
    log_message "Running autoremove to clean up unused packages..."
    sudo apt-get autoremove -y
    
    log_message "Dependencies removed (where possible)"
else
    log_message "Dependencies were not removed by user choice"
fi

log_message "=== STEP 5: SPI Configuration ==="
# Ask if user wants to disable SPI
if confirm "Do you want to disable the SPI interface? Only do this if no other application uses it."; then
    log_message "Disabling SPI interface..."
    
    # Create a backup of config.txt
    sudo cp /boot/config.txt /boot/config.txt.backup
    
    # Remove SPI enable line
    sudo sed -i '/dtparam=spi=on/d' /boot/config.txt
    
    log_message "SPI interface disabled in config. Will take effect after reboot."
    REBOOT_NEEDED=true
else
    log_message "SPI interface remains enabled"
fi

log_message "=== Uninstallation Complete ==="
log_message "The E-Paper Calendar application has been successfully removed."

# Notify about reboot if needed
if [ "$REBOOT_NEEDED" = true ]; then
    log_message "A reboot is recommended to complete the uninstallation process."
    if confirm "Would you like to reboot now?"; then
        log_message "Rebooting system..."
        sudo reboot
    else
        log_message "Please reboot manually when convenient."
    fi
fi

echo "======================================================"
echo "E-Paper Calendar Display uninstallation completed!"
echo "All components have been removed."
echo "======================================================"

exit 0
