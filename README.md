# E-paper Calendar Display for Raspberry Pi Zero 2W

A Python-based calendar display system for the Raspberry Pi Zero 2W with a Waveshare 4.01 inch HAT (F) 7-color e-paper display (640x400 pixels). This system displays the following information:

- Current date and day (in red if it's a holiday)
- Hungarian holidays (including movable holidays like Easter and Pentecost)
- Hungarian name days
- Notable days
- Sunrise and sunset times
- Moonrise and moonset times
- Moon phase (percentage and text description)
- Meteor shower information when applicable
- RSS news feed from Telex.hu (latest 3 items)

The display automatically refreshes every 10 minutes and uses all 7 colors available on the e-paper display for a visually appealing presentation.

## Hardware Requirements

- Raspberry Pi Zero 2W (512MB RAM)
- Waveshare 4.01 inch HAT (F) 7-color e-paper display (640x400 pixels)
- MicroSD card with Raspberry Pi OS Desktop (32-bit)
- Power supply for the Raspberry Pi

## Installation

### Automatic Installation

1. Copy all files from this repository to your Raspberry Pi
2. Make the installation script executable:
   ```bash
   chmod +x install.sh
   ```
3. Run the installation script as root:
   ```bash
   sudo ./install.sh
   ```
4. The script will install all required dependencies, configure the system, and set up the e-paper calendar to run automatically at startup.
5. If prompted, restart your Raspberry Pi.

### Manual Installation

If the automatic installation fails, you can follow these steps to install the system manually:

1. Update your system:
   ```bash
   sudo apt-get update
   sudo apt-get upgrade -y
   ```

2. Enable SPI interface:
   ```bash
   # Add the following line to /boot/config.txt if not already present
   dtparam=spi=on
   ```

3. Install system dependencies:
   ```bash
   sudo apt-get install -y python3-pip python3-pil python3-numpy git libopenjp2-7 libtiff5 python3-venv libatlas-base-dev libopenblas-dev wiringpi i2c-tools libfreetype6-dev
   ```

4. Install Python dependencies:
   ```bash
   pip3 install RPi.GPIO spidev pillow numpy feedparser requests pyephem
   ```

5. Install Waveshare e-Paper library:
   ```bash
   git clone https://github.com/waveshare/e-Paper.git
   mkdir -p ~/lib/waveshare_epd
   cp -R e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd/* ~/lib/waveshare_epd/
   ```

6. Configure Hungarian locale:
   ```bash
   sudo apt-get install -y locales
   sudo sed -i 's/# hu_HU.UTF-8 UTF-8/hu_HU.UTF-8 UTF-8/' /etc/locale.gen
   sudo locale-gen
   ```

7. Create a systemd service:
   ```bash
   sudo nano /etc/systemd/system/epaper-calendar.service
   ```
   
   Add the following content:
   ```
   [Unit]
   Description=E-paper Calendar Display
   After=network.target

   [Service]
   User=pi
   WorkingDirectory=/home/pi/epaper_calendar
   ExecStart=/usr/bin/python3 /home/pi/epaper_calendar/epaper_calendar.py
   Restart=always
   RestartSec=10

   [Install]
   WantedBy=multi-user.target
   ```

8. Enable and start the service:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable epaper-calendar.service
   sudo systemctl start epaper-calendar.service
   ```

## Uninstallation

If you want to remove the e-paper calendar system, run the uninstall script:

```bash
sudo ./uninstall.sh
```

This will remove all components installed by the installation script, stop and disable the service, and optionally remove Python packages and disable the SPI interface.

## Troubleshooting

### Display Issues

If the display doesn't show anything or shows incorrect information:

1. Check if the service is running:
   ```bash
   sudo systemctl status epaper-calendar
   ```

2. Check the log file for errors:
   ```bash
   cat /home/pi/epaper_calendar.log
   ```

3. Make sure SPI is enabled:
   ```bash
   lsmod | grep spi
   ```
   You should see `spi_bcm2835` in the output.

4. Check SPI connections:
   ```bash
   ls /dev/spi*
   ```
   You should see `/dev/spidev0.0` and `/dev/spidev0.1`.

### Python Issues

If you encounter Python-related errors:

1. Make sure all dependencies are installed:
   ```bash
   pip3 list | grep -E 'RPi.GPIO|spidev|pillow|numpy|feedparser|requests|pyephem'
   ```

2. Try reinstalling the Python packages:
   ```bash
   pip3 install --upgrade RPi.GPIO spidev pillow numpy feedparser requests pyephem
   ```

3. Check the waveshare library:
   ```bash
   ls -la ~/lib/waveshare_epd
   ```
   Make sure the directory contains the e-paper display drivers.

### Waveshare Library Issues

If the Waveshare library is causing problems:

1. Try downloading from an alternative source:
   ```bash
   git clone https://github.com/soonuse/epd-library-python.git
   mkdir -p ~/lib/waveshare_epd
   cp -R epd-library-python/lib/waveshare_epd/* ~/lib/waveshare_epd/
   ```

2. Or download directly from Waveshare's website:
   ```bash
   wget https://files.waveshare.com/upload/e/ef/E-Paper.zip
   unzip E-Paper.zip
   mkdir -p ~/lib/waveshare_epd
   cp -R e-Paper-master/RaspberryPi_JetsonNano/python/lib/waveshare_epd/* ~/lib/waveshare_epd/
   ```

## Customization

You can customize the e-paper calendar display by modifying the Python script:

- To adjust the refresh interval, change the `time.sleep(600)` value in the `run()` method (600 seconds = 10 minutes).
- To add more name days, update the `name_days` dictionary in the `get_name_days()` method.
- To add more holidays, update the `fixed_holidays` dictionary in the `is_holiday()` method.
- To add more notable days, update the `notable_days` dictionary in the `is_notable_day()` method.
- To change the RSS feed source, modify the URL in the `get_rss_news()` method.

## License

This project is open-source and free to use and modify for personal and educational purposes.

## Credits

- Waveshare for the e-paper display and library
- PyEphem for astronomical calculations
- Feedparser for RSS feed parsing
