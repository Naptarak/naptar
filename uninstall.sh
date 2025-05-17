#!/bin/bash

# E-paper Calendar Display Uninstallation Script
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch HAT (F) 7-color e-paper display
# Created: May 2025

# Text colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}  E-Paper Calendar Display Uninstallation Script    ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo ""

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
  exit 1
fi

PROJECT_DIR="/home/palszilard/e-paper-calendar"
SERVICE_FILE="/etc/systemd/system/e-paper-calendar.service"

# Function to confirm actions
confirm() {
  read -p "$1 (y/n): " response
  case "$response" in
    [yY][eE][sS]|[yY]) 
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Stop and disable the service
echo -e "${GREEN}Stopping and disabling e-paper-calendar service...${NC}"
systemctl stop e-paper-calendar.service 2>/dev/null
systemctl disable e-paper-calendar.service 2>/dev/null
rm -f "$SERVICE_FILE" 2>/dev/null
systemctl daemon-reload

# Remove project files
echo -e "${GREEN}Removing project files...${NC}"
if [ -d "$PROJECT_DIR" ]; then
  rm -rf "$PROJECT_DIR"
  echo -e "${GREEN}Project directory removed${NC}"
else
  echo -e "${YELLOW}Project directory not found${NC}"
fi

# Ask if user wants to remove Python dependencies
if confirm "Do you want to remove installed Python dependencies?"; then
  echo -e "${GREEN}Removing Python dependencies...${NC}"
  pip3 uninstall -y feedparser astral ephem requests pillow RPi.GPIO spidev 2>/dev/null
  echo -e "${GREEN}Python dependencies removed${NC}"
fi

# Ask if user wants to restore SPI settings
if confirm "Do you want to disable SPI interface?"; then
  echo -e "${GREEN}Disabling SPI interface...${NC}"
  sed -i '/dtparam=spi=on/d' /boot/config.txt
  echo -e "${GREEN}SPI interface disabled. You'll need to reboot for this to take effect.${NC}"
fi

echo -e "${GREEN}Uninstallation completed successfully!${NC}"
echo ""
echo -e "The e-paper calendar display has been removed from your system."
echo -e "You may need to reboot your Raspberry Pi for all changes to take effect."
echo -e "To reboot, run: ${BLUE}sudo reboot${NC}"
echo ""
echo -e "${GREEN}Thank you for using the E-Paper Calendar Display!${NC}"
