#!/bin/bash

# E-paper Calendar Display Installation Script
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

# Check if Raspberry Pi model is compatible
check_raspberry_pi_model() {
    print_msg "Checking Raspberry Pi model..."
    if grep -q "Raspberry Pi Zero 2" /proc/device-tree/model 2>/dev/null; then
        print_success "Raspberry Pi Zero 2W detected."
    else
        print_warning "This script is optimized for Raspberry Pi Zero 2W. Your device may not be fully compatible."
        read -p "Do you want to continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_msg "Installation cancelled by user."
            exit 1
        fi
    fi
}

# Update system
update_system() {
    print_msg "Updating system packages..."
    apt-get update -y || {
        print_error "Failed to update package list. Trying alternative repository mirror..."
        # Try changing the repository mirror if update fails
        sed -i 's|http://raspbian.raspberrypi.org|http://archive.raspbian.org|g' /etc/apt/sources.list
        apt-get update -y || {
            print_error "Failed to update package list even with alternative mirror."
            exit 1
        }
    }
    apt-get upgrade -y || print_warning "System upgrade failed, continuing with installation..."
}

# Enable SPI interface
enable_spi() {
    print_msg "Enabling SPI interface..."
    if ! grep -q "dtparam=spi=on" /boot/config.txt; then
        echo "dtparam=spi=on" >> /boot/config.txt
        print_success "SPI interface enabled. A reboot will be required."
        REBOOT_REQUIRED=true
    else
        print_success "SPI interface is already enabled."
    fi
}

# Install system dependencies
install_system_dependencies() {
    print_msg "Installing system dependencies..."
    apt-get install -y python3-pip python3-pil python3-numpy git libopenjp2-7 libtiff5 python3-venv \
        libatlas-base-dev libopenblas-dev wiringpi i2c-tools libfreetype6-dev || {
        print_error "Failed to install system dependencies. Trying individual installations..."
        
        # Try installing packages one by one
        packages=("python3-pip" "python3-pil" "python3-numpy" "git" "libopenjp2-7" "libtiff5" 
                 "python3-venv" "libatlas-base-dev" "libopenblas-dev" "wiringpi" "i2c-tools" "libfreetype6-dev")
        
        for package in "${packages[@]}"; do
            apt-get install -y "$package" || print_warning "Failed to install $package, continuing..."
        done
    }
    
    # Install pip if it's not already installed
    if ! command -v pip3 &> /dev/null; then
        print_warning "pip3 not found, trying to install it manually..."
        curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
        python3 get-pip.py
        rm get-pip.py
    fi
}

# Configure locale
configure_locale() {
    print_msg "Configuring Hungarian locale..."
    apt-get install -y locales
    sed -i 's/# hu_HU.UTF-8 UTF-8/hu_HU.UTF-8 UTF-8/' /etc/locale.gen
    locale-gen
    print_success "Hungarian locale configured."
}

# Create Python virtual environment
create_virtual_env() {
    print_msg "Creating Python virtual environment..."
    if [ -d "/home/pi/epaper_env" ]; then
        print_warning "Virtual environment already exists. Removing and recreating..."
        rm -rf /home/pi/epaper_env
    fi
    
    # Create a new virtual environment
    python3 -m venv /home/pi/epaper_env || {
        print_error "Failed to create virtual environment with venv. Trying virtualenv..."
        pip3 install virtualenv
        python3 -m virtualenv /home/pi/epaper_env || {
            print_error "Failed to create virtual environment. Proceeding without it..."
            VIRTUAL_ENV_FAILED=true
            return 1
        }
    }
    
    print_success "Virtual environment created."
    return 0
}

# Install Python dependencies
install_python_dependencies() {
    print_msg "Installing Python dependencies..."
    
    if [ "$VIRTUAL_ENV_FAILED" = true ]; then
        # Install globally if virtual environment failed
        pip_cmd="pip3"
    else
        # Use the virtual environment
        pip_cmd="/home/pi/epaper_env/bin/pip"
    fi
    
    # Try installing dependencies with pip
    $pip_cmd install --upgrade pip || print_warning "Failed to upgrade pip, continuing..."
    
    # Install all required Python packages
    $pip_cmd install RPi.GPIO spidev pillow numpy feedparser requests pyephem || {
        print_error "Failed to install Python dependencies together. Trying one by one..."
        
        packages=("RPi.GPIO" "spidev" "pillow" "numpy" "feedparser" "requests" "pyephem")
        
        for package in "${packages[@]}"; do
            $pip_cmd install "$package" || print_warning "Failed to install $package, continuing..."
        done
    }
    
    print_success "Python dependencies installed."
}

# Download and install Waveshare e-Paper library
install_waveshare_lib() {
    print_msg "Installing Waveshare e-Paper library..."
    
    # Clone the repository
    cd /tmp
    if [ -d "/tmp/e-Paper" ]; then
        rm -rf /tmp/e-Paper
    fi
    
    # Try multiple sources for the Waveshare library
    git clone https://github.com/waveshare/e-Paper.git || 
    git clone https://github.com/soonuse/epd-library-python.git e-Paper || {
        print_error "Failed to download Waveshare e-Paper library from GitHub."
        print_msg "Attempting alternative download method..."
        
        # If git fails, try wget
        wget -q https://files.waveshare.com/upload/e/ef/E-Paper.zip -O e-Paper.zip || {
            print_error "Failed to download Waveshare e-Paper library."
            print_msg "Please download the Waveshare e-Paper library manually and install it."
            exit 1
        }
        
        unzip e-Paper.zip
        mv e-Paper-master e-Paper
    }
    
    # Copy the necessary files
    if [ -d "/tmp/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd" ]; then
        mkdir -p /home/pi/lib/waveshare_epd
        cp -R /tmp/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd/* /home/pi/lib/waveshare_epd/
    elif [ -d "/tmp/e-Paper/lib/waveshare_epd" ]; then
        mkdir -p /home/pi/lib/waveshare_epd
        cp -R /tmp/e-Paper/lib/waveshare_epd/* /home/pi/lib/waveshare_epd/
    else
        print_error "Could not find Waveshare e-Paper library in the expected location."
        print_msg "Please install the Waveshare e-Paper library manually."
        exit 1
    fi
    
    print_success "Waveshare e-Paper library installed."
}

# Copy application files
copy_application_files() {
    print_msg "Copying application files..."
    
    # Create the application directory
    mkdir -p /home/pi/epaper_calendar
    
    # Copy the Python script
    cp "$(dirname "$0")/epaper_calendar.py" /home/pi/epaper_calendar/ || {
        print_error "Failed to copy epaper_calendar.py. Make sure the file exists in the same directory as this script."
        exit 1
    }
    
    # Make the script executable
    chmod +x /home/pi/epaper_calendar/epaper_calendar.py
    
    print_success "Application files copied."
}

# Create systemd service
create_service() {
    print_msg "Creating systemd service for automatic startup..."

    if [ "$VIRTUAL_ENV_FAILED" = true ]; then
        python_exec="/usr/bin/python3"
    else
        python_exec="/home/pi/epaper_env/bin/python3"
    fi
    
    # Create the service file
    cat > /etc/systemd/system/epaper-calendar.service << EOF
[Unit]
Description=E-paper Calendar Display
After=network.target

[Service]
User=pi
WorkingDirectory=/home/pi/epaper_calendar
ExecStart=$python_exec /home/pi/epaper_calendar/epaper_calendar.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd, enable and start the service
    systemctl daemon-reload
    systemctl enable epaper-calendar.service
    systemctl start epaper-calendar.service || print_warning "Failed to start service. You may need to reboot first."
    
    print_success "Systemd service created and enabled."
}

# Setup cron job to restart the display daily (to avoid e-paper burn-in)
setup_cron() {
    print_msg "Setting up daily restart to prevent display burn-in..."
    
    # Add a cron job to restart the service at 3 AM
    (crontab -l 2>/dev/null; echo "0 3 * * * sudo systemctl restart epaper-calendar.service") | crontab -
    
    print_success "Daily restart cron job set up."
}

# Main installation process
main() {
    print_msg "Starting e-Paper Calendar Display installation..."
    
    REBOOT_REQUIRED=false
    VIRTUAL_ENV_FAILED=false
    
    check_raspberry_pi_model
    update_system
    enable_spi
    install_system_dependencies
    configure_locale
    create_virtual_env
    install_python_dependencies
    install_waveshare_lib
    copy_application_files
    create_service
    setup_cron
    
    print_success "Installation completed successfully!"
    
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
    else
        print_msg "No reboot required. The e-paper calendar should be running now."
        print_msg "You can check its status with: sudo systemctl status epaper-calendar"
    fi
}

# Run the main installation process
main
