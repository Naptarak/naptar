#!/bin/bash

# E-paper Calendar Display Uninstall Script
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch HAT (F) 7-color e-paper display

# Exit on error
set -e

# Display colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored message
print_msg() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Print error message
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Print success message
print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Print warning message
print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root (use sudo)"
    exit 1
fi

# Confirm uninstallation
print_warning "This script will remove the E-paper Calendar Display and all its components."
read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_msg "Uninstallation cancelled by user."
    exit 0
fi

# Stop and disable systemd service
stop_service() {
    print_msg "Stopping and disabling systemd service..."
    
    if systemctl is-active --quiet epaper-calendar.service; then
        systemctl stop epaper-calendar.service
        print_success "Service stopped."
    else
        print_warning "Service was not running."
    fi
    
    if systemctl is-enabled --quiet epaper-calendar.service 2>/dev/null; then
        systemctl disable epaper-calendar.service
        print_success "Service disabled."
    else
        print_warning "Service was not enabled."
    fi
    
    # Remove service file
    if [ -f "/etc/systemd/system/epaper-calendar.service" ]; then
        rm -f /etc/systemd/system/epaper-calendar.service
        systemctl daemon-reload
        print_success "Service file removed."
    else
        print_warning "Service file not found."
    fi
}

# Remove cron job
remove_cron() {
    print_msg "Removing cron job..."
    
    # Remove the cron job for service restart
    (crontab -l 2>/dev/null | grep -v "systemctl restart epaper-calendar.service") | crontab -
    
    print_success "Cron job removed."
}

# Remove application files
remove_app_files() {
    print_msg "Removing application files..."
    
    # Remove application directory
    if [ -d "/home/pi/epaper_calendar" ]; then
        rm -rf /home/pi/epaper_calendar
        print_success "Application directory removed."
    else
        print_warning "Application directory not found."
    fi
    
    # Remove log file
    if [ -f "/home/pi/epaper_calendar.log" ]; then
        rm -f /home/pi/epaper_calendar.log
        print_success "Log file removed."
    else
        print_warning "Log file not found."
    fi
}

# Remove Waveshare library
remove_waveshare_lib() {
    print_msg "Removing Waveshare e-Paper library..."
    
    # Remove library directory
    if [ -d "/home/pi/lib/waveshare_epd" ]; then
        rm -rf /home/pi/lib/waveshare_epd
        print_success "Waveshare library removed."
    else
        print_warning "Waveshare library directory not found."
    fi
    
    # Remove parent directory if empty
    if [ -d "/home/pi/lib" ] && [ -z "$(ls -A /home/pi/lib)" ]; then
        rmdir /home/pi/lib
        print_success "Empty lib directory removed."
    fi
}

# Remove Python virtual environment
remove_virtual_env() {
    print_msg "Removing Python virtual environment..."
    
    # Remove virtual environment directory
    if [ -d "/home/pi/epaper_env" ]; then
        rm -rf /home/pi/epaper_env
        print_success "Virtual environment removed."
    else
        print_warning "Virtual environment not found."
    fi
}

# Disable SPI (optional)
disable_spi() {
    print_msg "Would you like to disable the SPI interface?"
    print_warning "Note: This might affect other applications using SPI."
    read -p "Disable SPI? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if grep -q "dtparam=spi=on" /boot/config.txt; then
            sed -i '/dtparam=spi=on/d' /boot/config.txt
            print_success "SPI interface disabled. A reboot is required to apply this change."
            REBOOT_REQUIRED=true
        else
            print_warning "SPI setting not found in config.txt."
        fi
    else
        print_msg "SPI interface will remain enabled."
    fi
}

# Remove Python packages (optional)
remove_python_packages() {
    print_msg "Would you like to remove the installed Python packages?"
    print_warning "Note: This might affect other applications using these packages."
    read -p "Remove Python packages? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pip3 uninstall -y RPi.GPIO spidev pillow numpy feedparser requests pyephem || {
            print_warning "Failed to uninstall some Python packages."
            print_warning "This is normal if they were not installed or are being used by other applications."
        }
        print_success "Python packages uninstalled."
    else
        print_msg "Python packages will remain installed."
    fi
}

# Main uninstallation process
main() {
    print_msg "Starting e-Paper Calendar Display uninstallation..."
    
    REBOOT_REQUIRED=false
    
    stop_service
    remove_cron
    remove_app_files
    remove_waveshare_lib
    remove_virtual_env
    disable_spi
    remove_python_packages
    
    print_success "Uninstallation completed successfully!"
    
    if [ "$REBOOT_REQUIRED" = true ]; then
        print_warning "A reboot is required to apply all changes."
        read -p "Do you want to reboot now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_msg "Rebooting system..."
            reboot
        else
            print_msg "Please reboot your system manually when convenient."
        fi
    fi
}

# Run the main uninstallation process
main
