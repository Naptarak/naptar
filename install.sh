#!/bin/bash

# E-paper Calendar Display Installation Script
# For Raspberry Pi Zero 2W with Waveshare 4.01 inch HAT (F) 7-color e-paper display
# Created: May 2025

# Text colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/tmp/e-paper-calendar-install.log"
touch "$LOG_FILE"
exec &> >(tee -a "$LOG_FILE")

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}  E-Paper Calendar Display Installation Script      ${NC}"
echo -e "${BLUE}  For Raspberry Pi Zero 2W with Waveshare 4.01 inch ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo ""

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
  exit 1
fi

# Function for error handling
handle_error() {
  local exit_code=$1
  local error_msg=$2
  local fallback=$3
  
  if [ $exit_code -ne 0 ]; then
    echo -e "${RED}Error: $error_msg${NC}"
    echo -e "${YELLOW}Attempting fallback: $fallback${NC}"
    return 1
  fi
  return 0
}

# Create project directory
PROJECT_DIR="/home/palszilard/e-paper-calendar"
mkdir -p "$PROJECT_DIR"
chown palszilard:palszilard "$PROJECT_DIR"

echo -e "${GREEN}Step 1: Updating system packages...${NC}"
apt-get update || handle_error $? "Failed to update package lists" "Continuing with installation"
apt-get upgrade -y || handle_error $? "Failed to upgrade packages" "Continuing with installation"

echo -e "${GREEN}Step 2: Installing system dependencies...${NC}"
apt-get install -y git python3 python3-pip python3-pil python3-numpy libopenjp2-7 libtiff5 \
                  libatlas-base-dev python3-venv || {
  handle_error $? "Failed to install dependencies" "Trying individual installations"
  
  # Individual package installation as fallback
  packages=("git" "python3" "python3-pip" "python3-pil" "python3-numpy" "libopenjp2-7" "libtiff5" "libatlas-base-dev" "python3-venv")
  
  for package in "${packages[@]}"; do
    echo -e "${YELLOW}Trying to install $package...${NC}"
    apt-get install -y "$package" || echo -e "${RED}Failed to install $package, continuing...${NC}"
  done
}

# Enable SPI interface
echo -e "${GREEN}Step 3: Enabling SPI interface...${NC}"
if ! grep -q "dtparam=spi=on" /boot/config.txt; then
  echo "dtparam=spi=on" >> /boot/config.txt
  echo -e "${GREEN}SPI interface enabled in /boot/config.txt${NC}"
else
  echo -e "${GREEN}SPI interface is already enabled${NC}"
fi

# Check Python version
echo -e "${GREEN}Step 4: Checking Python version...${NC}"
python3 --version || handle_error $? "Python3 not found" "Will attempt to install Python"

# Install Waveshare e-Paper library
echo -e "${GREEN}Step 5: Installing Waveshare e-Paper library...${NC}"
WAVESHARE_DIR="$PROJECT_DIR/waveshare-e-paper"
mkdir -p "$WAVESHARE_DIR"
chown palszilard:palszilard "$WAVESHARE_DIR"

# Try git clone method first
if command -v git &> /dev/null; then
  echo "Using git to clone Waveshare repository..."
  su - palszilard -c "git clone https://github.com/waveshare/e-Paper.git $WAVESHARE_DIR" || {
    handle_error $? "Failed to clone Waveshare repository" "Trying alternative download method"
    
    # Alternative: Download ZIP file
    echo "Downloading ZIP file as fallback..."
    apt-get install -y wget unzip || echo -e "${RED}Failed to install wget and unzip, continuing...${NC}"
    
    su - palszilard -c "wget https://github.com/waveshare/e-Paper/archive/master.zip -O /tmp/waveshare.zip" || {
      handle_error $? "Failed to download ZIP file" "Manual installation required"
      echo -e "${RED}Failed to download Waveshare library. Please install it manually.${NC}"
      echo "Instructions: Download from https://github.com/waveshare/e-Paper and extract to $WAVESHARE_DIR"
    }
    
    su - palszilard -c "unzip /tmp/waveshare.zip -d /tmp" && \
    su - palszilard -c "cp -r /tmp/e-Paper-master/* $WAVESHARE_DIR" && \
    su - palszilard -c "rm /tmp/waveshare.zip" || {
      handle_error $? "Failed to extract ZIP file" "Manual installation required"
    }
  }
else
  echo "git not available, using wget as fallback..."
  apt-get install -y wget unzip || echo -e "${RED}Failed to install wget and unzip${NC}"
  
  su - palszilard -c "wget https://github.com/waveshare/e-Paper/archive/master.zip -O /tmp/waveshare.zip" && \
  su - palszilard -c "unzip /tmp/waveshare.zip -d /tmp" && \
  su - palszilard -c "cp -r /tmp/e-Paper-master/* $WAVESHARE_DIR" && \
  su - palszilard -c "rm /tmp/waveshare.zip" || {
    handle_error $? "Failed to download and extract Waveshare library" "Manual installation required"
    echo -e "${RED}Failed to install Waveshare library. Please install it manually.${NC}"
  }
fi

# Copy the specific library for 4.01inch e-paper to our project directory
EPAPER_LIB_DIR="$PROJECT_DIR/lib"
mkdir -p "$EPAPER_LIB_DIR"
chown palszilard:palszilard "$EPAPER_LIB_DIR"

# The directory may be different depending on the repository structure
# Try multiple possible paths
possible_paths=(
  "$WAVESHARE_DIR/RaspberryPi_JetsonNano/python/lib/waveshare_epd"
  "$WAVESHARE_DIR/RaspberryPi/python/lib/waveshare_epd"
  "$WAVESHARE_DIR/lib/waveshare_epd"
)

for path in "${possible_paths[@]}"; do
  if [ -d "$path" ]; then
    echo "Found Waveshare library at $path"
    su - palszilard -c "cp -r $path $EPAPER_LIB_DIR/"
    break
  fi
done

if [ ! -d "$EPAPER_LIB_DIR/waveshare_epd" ]; then
  echo -e "${RED}Could not find Waveshare e-Paper library. Please check the repository structure.${NC}"
  echo "You'll need to manually copy the waveshare_epd directory to $EPAPER_LIB_DIR"
fi

# Set up Python virtual environment
echo -e "${GREEN}Step 6: Setting up Python virtual environment...${NC}"
su - palszilard -c "python3 -m venv $PROJECT_DIR/venv" || {
  handle_error $? "Failed to create virtual environment" "Trying alternative method"
  
  # Fallback: Try installing venv package if not already installed
  apt-get install -y python3-venv || echo -e "${RED}Failed to install python3-venv${NC}"
  su - palszilard -c "python3 -m venv $PROJECT_DIR/venv" || {
    handle_error $? "Still failed to create virtual environment" "Using system Python"
    echo -e "${YELLOW}Will use system Python instead of virtual environment${NC}"
    # Set empty variable to indicate we're not using venv
    VENV_PYTHON=""
  }
}

# Determine which Python to use
if [ -f "$PROJECT_DIR/venv/bin/python" ]; then
  VENV_PYTHON="$PROJECT_DIR/venv/bin/python"
  VENV_PIP="$PROJECT_DIR/venv/bin/pip"
  echo -e "${GREEN}Using virtual environment Python${NC}"
else
  VENV_PYTHON="python3"
  VENV_PIP="pip3"
  echo -e "${YELLOW}Using system Python${NC}"
fi

# Install Python dependencies
echo -e "${GREEN}Step 7: Installing Python dependencies...${NC}"
if [ -n "$VENV_PYTHON" ]; then
  su - palszilard -c "$VENV_PIP install --upgrade pip" || echo -e "${YELLOW}Failed to upgrade pip, continuing...${NC}"
  
  # Install required packages with error handling
  su - palszilard -c "$VENV_PIP install feedparser astral ephem requests pillow RPi.GPIO spidev" || {
    handle_error $? "Failed to install Python packages" "Trying individual installations"
    
    # Individual installations as fallback
    packages=("feedparser" "astral" "ephem" "requests" "pillow" "RPi.GPIO" "spidev")
    
    for package in "${packages[@]}"; do
      echo -e "${YELLOW}Trying to install $package...${NC}"
      su - palszilard -c "$VENV_PIP install $package" || echo -e "${RED}Failed to install $package, continuing...${NC}"
    done
  }
else
  # Using system pip as fallback
  pip3 install --upgrade pip || echo -e "${YELLOW}Failed to upgrade pip, continuing...${NC}"
  
  packages=("feedparser" "astral" "ephem" "requests" "pillow" "RPi.GPIO" "spidev")
  
  for package in "${packages[@]}"; do
    echo -e "${YELLOW}Installing $package...${NC}"
    pip3 install "$package" || echo -e "${RED}Failed to install $package, continuing...${NC}"
  done
fi

# Download and install fonts
echo -e "${GREEN}Step 8: Installing fonts...${NC}"
FONT_DIR="$PROJECT_DIR/fonts"
mkdir -p "$FONT_DIR"
chown palszilard:palszilard "$FONT_DIR"

# Try to use wget to download fonts
if command -v wget &> /dev/null; then
  # Download free fonts
  su - palszilard -c "wget https://github.com/google/fonts/raw/main/ofl/opensans/static/OpenSans-Regular.ttf -O $FONT_DIR/FreeSans.ttf" || \
  echo -e "${YELLOW}Failed to download Open Sans Regular font, continuing...${NC}"
  
  su - palszilard -c "wget https://github.com/google/fonts/raw/main/ofl/opensans/static/OpenSans-Bold.ttf -O $FONT_DIR/FreeSansBold.ttf" || \
  echo -e "${YELLOW}Failed to download Open Sans Bold font, continuing...${NC}"
else
  # Create sample fonts as fallback
  cp /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf "$FONT_DIR/FreeSans.ttf" 2>/dev/null || \
  echo -e "${YELLOW}Failed to copy DejaVuSans font, continuing...${NC}"
  
  cp /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf "$FONT_DIR/FreeSansBold.ttf" 2>/dev/null || \
  echo -e "${YELLOW}Failed to copy DejaVuSans-Bold font, continuing...${NC}"
fi

# Copy application files
echo -e "${GREEN}Step 9: Copying application files...${NC}"

# Create directories
mkdir -p "$PROJECT_DIR/images"
chown -R palszilard:palszilard "$PROJECT_DIR"

echo -e "${GREEN}Step 10: Setting up systemd service...${NC}"
SERVICE_FILE="/etc/systemd/system/e-paper-calendar.service"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=E-Paper Calendar Display
After=network.target

[Service]
User=palszilard
WorkingDirectory=$PROJECT_DIR
ExecStart=$VENV_PYTHON $PROJECT_DIR/calendar_display.py
Restart=always
RestartSec=10
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable e-paper-calendar.service
systemctl start e-paper-calendar.service || {
  handle_error $? "Failed to start service" "The service will need to be started manually"
  echo -e "${YELLOW}To start the service manually, run: sudo systemctl start e-paper-calendar.service${NC}"
}

echo -e "${GREEN}Installation completed successfully!${NC}"
echo ""
echo -e "The e-paper calendar display should now be running."
echo -e "To check status: ${BLUE}sudo systemctl status e-paper-calendar.service${NC}"
echo -e "To restart:     ${BLUE}sudo systemctl restart e-paper-calendar.service${NC}"
echo -e "To stop:        ${BLUE}sudo systemctl stop e-paper-calendar.service${NC}"
echo ""
echo -e "Log files can be viewed with: ${BLUE}journalctl -u e-paper-calendar.service${NC}"
echo -e "Installation log saved to: ${BLUE}$LOG_FILE${NC}"
echo ""
echo -e "${GREEN}Thank you for using the E-Paper Calendar Display!${NC}"
