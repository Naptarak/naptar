#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import time
import logging
import locale
import feedparser
import datetime
import ephem
import requests
import json
from PIL import Image, ImageDraw, ImageFont
import traceback
from concurrent.futures import ThreadPoolExecutor

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/home/pi/epaper_calendar.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Set locale to Hungarian
try:
    locale.setlocale(locale.LC_TIME, 'hu_HU.UTF-8')
except locale.Error:
    try:
        locale.setlocale(locale.LC_TIME, 'hu_HU.utf8')
    except locale.Error:
        logger.warning("Hungarian locale not available, using default")

# Try to import the Waveshare e-paper library
# This is in a try/except block to handle different directory structures
try:
    from waveshare_epd import epd4in01f
except ImportError:
    try:
        sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), 'lib'))
        from waveshare_epd import epd4in01f
    except ImportError:
        logger.error("Cannot import Waveshare e-paper library. Please make sure it's installed correctly.")
        sys.exit(1)

# Define colors for the 7-color display
# Values are (r, g, b) tuples
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
RED = (255, 0, 0)
YELLOW = (255, 255, 0)
ORANGE = (255, 128, 0)
GREEN = (0, 255, 0)
BLUE = (0, 0, 255)

# Path for fonts
FONT_PATH = "/usr/share/fonts/truetype/dejavu/"

class EpaperCalendar:
    def __init__(self):
        logger.info("Initializing e-paper calendar")
        self.epd = epd4in01f.EPD()
        self.width = 640
        self.height = 400
        self.location = ephem.Observer()
        # Budapest, Hungary coordinates
        self.location.lat = '47.4979'
        self.location.lon = '19.0402'
        self.location.elevation = 105  # meters
        
        # Initialize fonts
        try:
            self.title_font = ImageFont.truetype(os.path.join(FONT_PATH, 'DejaVuSans-Bold.ttf'), 36)
            self.large_font = ImageFont.truetype(os.path.join(FONT_PATH, 'DejaVuSans-Bold.ttf'), 28)
            self.medium_font = ImageFont.truetype(os.path.join(FONT_PATH, 'DejaVuSans.ttf'), 20)
            self.small_font = ImageFont.truetype(os.path.join(FONT_PATH, 'DejaVuSans.ttf'), 16)
        except IOError:
            # Fallback to default font if DejaVu not available
            logger.warning("DejaVu fonts not found, using default font")
            self.title_font = ImageFont.load_default()
            self.large_font = ImageFont.load_default()
            self.medium_font = ImageFont.load_default()
            self.small_font = ImageFont.load_default()
    
    def initialize_display(self):
        """Initialize the e-paper display"""
        try:
            logger.info("Initializing display")
            self.epd.init()
            self.epd.Clear()
            return True
        except Exception as e:
            logger.error(f"Error initializing display: {str(e)}")
            logger.error(traceback.format_exc())
            return False
    
    def sleep(self):
        """Put the display to sleep to save power"""
        try:
            self.epd.sleep()
        except Exception as e:
            logger.error(f"Error putting display to sleep: {str(e)}")
    
    def get_name_days(self, date):
        """Get Hungarian name days for the given date"""
        # Hungarian name days database (month, day): [names]
        # This is a simplified version, a more complete database should be used
        name_days = {
            (1, 1): ["Fruzsina", "Újév"],
            (1, 2): ["Ábel", "Alpár"],
            (1, 3): ["Benjámin", "Genovéva"],
            # More name days would go here...
            (5, 17): ["Paszkál", "Szolón"],
            (5, 18): ["Alexandra", "Erik"],
            (12, 24): ["Ádám", "Éva"],
            (12, 25): ["Karácsony", "Eugénia"],
            (12, 26): ["István", "Előd"],
            (12, 31): ["Szilveszter", "Óévbúcsú"]
        }
        
        # If we don't have the name day in our database, return Unknown
        return name_days.get((date.month, date.day), ["Ismeretlen névnap"])
    
    def is_holiday(self, date):
        """Check if the given date is a holiday in Hungary"""
        # Fixed holidays
        fixed_holidays = {
            (1, 1): "Újév",
            (3, 15): "1848-as forradalom és szabadságharc emléknapja",
            (5, 1): "A munka ünnepe",
            (8, 20): "Szent István ünnepe",
            (10, 23): "1956-os forradalom emléknapja",
            (11, 1): "Mindenszentek",
            (12, 25): "Karácsony",
            (12, 26): "Karácsony másnapja"
        }
        
        # Check fixed holidays
        holiday_name = fixed_holidays.get((date.month, date.day))
        if holiday_name:
            return True, holiday_name
        
        # Calculate Easter (Húsvét) using the ephem library
        year = date.year
        easter = ephem.next_easter(datetime.date(year, 1, 1))
        easter_date = easter.datetime().date()
        
        # Moving holidays based on Easter
        if date == easter_date:
            return True, "Húsvét vasárnap"
        elif date == easter_date + datetime.timedelta(days=1):
            return True, "Húsvét hétfő"
        elif date == easter_date - datetime.timedelta(days=2):
            return True, "Nagypéntek"
        elif date == easter_date + datetime.timedelta(days=49):
            return True, "Pünkösd vasárnap"
        elif date == easter_date + datetime.timedelta(days=50):
            return True, "Pünkösd hétfő"
        
        return False, None
    
    def is_notable_day(self, date):
        """Check if the given date is a notable day"""
        notable_days = {
            (1, 22): "A magyar kultúra napja",
            (2, 14): "Valentin-nap",
            (3, 8): "Nemzetközi nőnap",
            (4, 22): "A Föld napja",
            (5, 1): "A munka ünnepe",
            (5, 31): "Nemdohányzó világnap",
            (6, 5): "Környezetvédelmi világnap",
            (10, 1): "Zene világnapja",
            (10, 6): "Aradi vértanúk emléknapja",
            (12, 6): "Mikulás"
        }
        
        return notable_days.get((date.month, date.day))
    
    def get_sun_times(self, date):
        """Get sunrise and sunset times for Budapest"""
        self.location.date = date
        sun = ephem.Sun()
        
        # Get next sunrise and sunset
        sunrise = self.location.next_rising(sun)
        sunset = self.location.next_setting(sun)
        
        # Convert to local time
        sunrise_time = sunrise.datetime().replace(tzinfo=datetime.timezone.utc).astimezone().strftime('%H:%M')
        sunset_time = sunset.datetime().replace(tzinfo=datetime.timezone.utc).astimezone().strftime('%H:%M')
        
        return sunrise_time, sunset_time
    
    def get_moon_times(self, date):
        """Get moonrise and moonset times and phase"""
        self.location.date = date
        moon = ephem.Moon()
        
        # Try to get next moonrise and moonset
        try:
            moonrise = self.location.next_rising(moon)
            moonrise_time = moonrise.datetime().replace(tzinfo=datetime.timezone.utc).astimezone().strftime('%H:%M')
        except (ephem.AlwaysUpError, ephem.NeverUpError):
            moonrise_time = "Nincs holdkelte"
        
        try:
            moonset = self.location.next_setting(moon)
            moonset_time = moonset.datetime().replace(tzinfo=datetime.timezone.utc).astimezone().strftime('%H:%M')
        except (ephem.AlwaysUpError, ephem.NeverUpError):
            moonset_time = "Nincs holdnyugta"
        
        # Calculate moon phase
        moon.compute(date)
        # Moon phase is a value from 0 to 1 indicating the percentage illuminated
        phase_percent = int(moon.phase)
        
        # Determine the phase name based on percentage
        if phase_percent < 2:
            phase_name = "Újhold"
        elif phase_percent < 48:
            phase_name = "Növekvő hold"
        elif phase_percent < 52:
            phase_name = "Telihold"
        elif phase_percent < 98:
            phase_name = "Fogyó hold"
        else:
            phase_name = "Újhold"
            
        return moonrise_time, moonset_time, phase_percent, phase_name
    
    def get_meteor_showers(self, date):
        """Check if there are any active meteor showers on the given date"""
        # Major meteor showers data: (start_date, peak_date, end_date, name)
        meteor_showers = [
            ((1, 1), (1, 4), (1, 5), "Quadrantidák"),
            ((4, 19), (4, 22), (4, 25), "Lyridák"),
            ((5, 5), (5, 6), (5, 7), "Eta Aquaridák"),
            ((7, 23), (7, 30), (8, 20), "Delta Aquaridák"),
            ((8, 11), (8, 12), (8, 13), "Perseidák"),
            ((10, 20), (10, 21), (10, 22), "Orionidák"),
            ((11, 16), (11, 17), (11, 18), "Leonidák"),
            ((12, 13), (12, 14), (12, 15), "Geminidák")
        ]
        
        active_showers = []
        month, day = date.month, date.day
        
        for start, peak, end, name in meteor_showers:
            # Check if the date is within the shower period
            if self._is_date_between((month, day), start, end):
                # Check if it's the peak day
                if (month, day) == peak:
                    active_showers.append(f"{name} (csúcs)")
                else:
                    active_showers.append(name)
        
        return active_showers
    
    def _is_date_between(self, date, start, end):
        """Helper function to check if a date is between start and end dates"""
        month, day = date
        start_month, start_day = start
        end_month, end_day = end
        
        if start_month == end_month:
            return start_month == month and start_day <= day <= end_day
        
        if month == start_month:
            return day >= start_day
        
        if month == end_month:
            return day <= end_day
        
        if start_month < end_month:
            return start_month < month < end_month
        
        # Handle year boundary (December to January)
        return month < end_month or month > start_month
    
    def get_rss_news(self, url="https://telex.hu/rss"):
        """Get the first 3 news items from Telex RSS feed"""
        try:
            feed = feedparser.parse(url)
            news_items = []
            
            for i, entry in enumerate(feed.entries[:3]):
                title = entry.title
                news_items.append(title)
            
            return news_items
        except Exception as e:
            logger.error(f"Error fetching RSS feed: {str(e)}")
            return ["RSS feed betöltése sikertelen"]
    
    def draw_display(self):
        """Create and update the display image"""
        try:
            # Create blank image with white background
            image = Image.new('RGB', (self.width, self.height), WHITE)
            draw = ImageDraw.Draw(image)
            
            # Get current date and time
            now = datetime.datetime.now()
            today = now.date()
            
            # Check if today is a holiday
            is_holiday, holiday_name = self.is_holiday(today)
            
            # Get name day
            name_days = self.get_name_days(today)
            name_day_text = ', '.join(name_days)
            
            # Get sun and moon information
            sunrise_time, sunset_time = self.get_sun_times(today)
            moonrise_time, moonset_time, moon_phase, moon_phase_name = self.get_moon_times(today)
            
            # Get meteor shower information
            meteor_showers = self.get_meteor_showers(today)
            
            # Get notable day information
            notable_day = self.is_notable_day(today)
            
            # Get RSS news
            news_items = self.get_rss_news()
            
            # Draw header with date
            date_color = RED if is_holiday else BLUE
            date_text = today.strftime("%Y. %B %d. %A")
            draw.text((20, 10), date_text, date_color, font=self.title_font)
            
            # Draw horizontal line
            draw.line([(20, 55), (self.width - 20, 55)], BLACK, width=2)
            
            # Display holiday information if applicable
            y_pos = 65
            if is_holiday:
                draw.text((20, y_pos), f"Ünnepnap: {holiday_name}", RED, font=self.large_font)
                y_pos += 40
            
            # Display notable day if applicable
            if notable_day:
                draw.text((20, y_pos), f"Jeles nap: {notable_day}", ORANGE, font=self.medium_font)
                y_pos += 30
            
            # Display name day
            draw.text((20, y_pos), f"Névnap: {name_day_text}", BLACK, font=self.medium_font)
            y_pos += 30
            
            # Display sun information
            draw.text((20, y_pos), f"Napkelte: {sunrise_time} | Napnyugta: {sunset_time}", ORANGE, font=self.medium_font)
            y_pos += 30
            
            # Display moon information
            draw.text((20, y_pos), f"Holdkelte: {moonrise_time} | Holdnyugta: {moonset_time}", BLUE, font=self.medium_font)
            y_pos += 30
            draw.text((20, y_pos), f"Hold fázis: {moon_phase}% - {moon_phase_name}", BLUE, font=self.medium_font)
            y_pos += 30
            
            # Display meteor shower information if applicable
            if meteor_showers:
                meteor_text = "Meteorraj: " + ", ".join(meteor_showers)
                draw.text((20, y_pos), meteor_text, GREEN, font=self.medium_font)
                y_pos += 30
            
            # Draw horizontal line above news section
            draw.line([(20, self.height - 110), (self.width - 20, self.height - 110)], BLACK, width=2)
            
            # Display RSS feed news
            draw.text((20, self.height - 100), "Hírek (Telex.hu):", BLACK, font=self.medium_font)
            for i, news in enumerate(news_items):
                draw.text((20, self.height - 70 + i * 25), f"• {news}", BLACK, font=self.small_font)
            
            # Display update timestamp in the bottom right corner
            update_time = now.strftime("%H:%M")
            draw.text((self.width - 100, self.height - 20), f"Frissítve: {update_time}", BLACK, font=self.small_font)
            
            # Convert the image to the format required by the display
            self.epd.display(self.epd.getbuffer(image))
            logger.info("Display updated successfully")
            
        except Exception as e:
            logger.error(f"Error drawing display: {str(e)}")
            logger.error(traceback.format_exc())
    
    def run(self):
        """Main loop to update the display"""
        if not self.initialize_display():
            logger.error("Failed to initialize display. Exiting.")
            return
        
        try:
            while True:
                logger.info("Updating display")
                self.draw_display()
                
                # Sleep for 10 minutes
                logger.info("Sleeping for 10 minutes")
                time.sleep(600)
                
        except KeyboardInterrupt:
            logger.info("Keyboard interrupt received. Exiting.")
            self.sleep()
        except Exception as e:
            logger.error(f"Unexpected error: {str(e)}")
            logger.error(traceback.format_exc())
            self.sleep()

# Main function
def main():
    calendar = EpaperCalendar()
    calendar.run()

if __name__ == "__main__":
    main()
