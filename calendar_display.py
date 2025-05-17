#!/usr/bin/python3
# -*- coding:utf-8 -*-

import os
import sys
import time
from datetime import datetime, timedelta
import calendar
import locale
import json
import feedparser
import traceback
import logging
from PIL import Image, ImageDraw, ImageFont
import requests

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Add the lib directory to the path
lib_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'lib')
sys.path.append(lib_dir)

# Import Waveshare library
try:
    from waveshare_epd import epd4in01f
    logger.info("Waveshare e-Paper library imported successfully")
except ImportError:
    logger.error("Failed to import Waveshare e-Paper library")
    print("ERROR: Waveshare e-Paper library not found")
    print(f"Check if the library exists at: {lib_dir}/waveshare_epd")
    print("Make sure the install.sh script has been run successfully")
    
    # Try to import from alternative locations
    try:
        # Try to import from Python path
        sys.path.append('/home/palszilard/e-paper-calendar/lib')
        from waveshare_epd import epd4in01f
        logger.info("Waveshare e-Paper library imported from alternative location")
    except ImportError:
        print("ERROR: Could not find Waveshare library. Please check installation.")
        sys.exit(1)

# Try to import ephem for astronomical calculations
try:
    import ephem
except ImportError:
    print("WARNING: ephem module not found, trying to install it...")
    try:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "ephem"])
        import ephem
        print("Successfully installed and imported ephem")
    except Exception as e:
        print(f"ERROR: Could not install ephem: {str(e)}")
        print("Some astronomical features will be disabled")
        ephem = None

# Try to set Hungarian locale
try:
    locale.setlocale(locale.LC_TIME, 'hu_HU.UTF-8')
    logger.info("Locale set to Hungarian")
except locale.Error:
    try:
        locale.setlocale(locale.LC_TIME, 'hu_HU.utf8')
        logger.info("Locale set to Hungarian (alternate format)")
    except locale.Error:
        logger.warning("Failed to set Hungarian locale, using default")
        try:
            # Try to install Hungarian locale if not available
            os.system('sudo apt-get install -y locales')
            os.system('sudo locale-gen hu_HU.UTF-8')
            locale.setlocale(locale.LC_TIME, 'hu_HU.UTF-8')
            logger.info("Hungarian locale installed and set")
        except:
            logger.error("Failed to install Hungarian locale")

# Configuration
CONFIG_FILE = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'config.json')

# Default configuration
DEFAULT_CONFIG = {
    'location': {
        'city': 'Budapest',
        'latitude': 47.4979,
        'longitude': 19.0402,
        'elevation': 105
    },
    'refresh_interval': 600,  # 10 minutes
    'rss_feed_url': 'https://telex.hu/rss',
    'max_news_items': 3,
    'font_sizes': {
        'date': 46,
        'main': 26,
        'secondary': 20,
        'news_title': 18,
        'news_description': 16
    }
}

# Load configuration
def load_config():
    try:
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        else:
            # Create default config file
            with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
                json.dump(DEFAULT_CONFIG, f, indent=4, ensure_ascii=False)
            return DEFAULT_CONFIG
    except Exception as e:
        logger.error(f"Error loading configuration: {e}")
        return DEFAULT_CONFIG

# Hungarian holidays (fixed)
FIXED_HOLIDAYS = {
    (1, 1): "Újév",
    (3, 15): "Az 1848-as forradalom ünnepe",
    (5, 1): "A munka ünnepe",
    (8, 20): "Az államalapítás ünnepe",
    (10, 23): "Az 1956-os forradalom ünnepe",
    (11, 1): "Mindenszentek",
    (12, 24): "Szenteste",
    (12, 25): "Karácsony",
    (12, 26): "Karácsony másnapja",
    (12, 31): "Szilveszter"
}

# Notable days
NOTABLE_DAYS = {
    (1, 22): "A magyar kultúra napja",
    (2, 14): "Valentin-nap",
    (3, 8): "Nemzetközi nőnap",
    (4, 11): "A költészet napja",
    (4, 22): "A Föld napja",
    (5, 10): "Madarak és fák napja",
    (6, 5): "Környezetvédelmi világnap",
    (10, 1): "Zene világnapja",
    (10, 31): "Halloween",
    (11, 11): "Márton-nap",
    (12, 6): "Mikulás"
}

# Major meteor showers
METEOR_SHOWERS = [
    {"name": "Quadrantidák", "start_date": (1, 1), "end_date": (1, 5), "peak": (1, 3)},
    {"name": "Lyridák", "start_date": (4, 16), "end_date": (4, 25), "peak": (4, 22)},
    {"name": "Eta Aquaridák", "start_date": (4, 19), "end_date": (5, 28), "peak": (5, 5)},
    {"name": "Delta Aquaridák", "start_date": (7, 12), "end_date": (8, 23), "peak": (7, 30)},
    {"name": "Perseidák", "start_date": (7, 17), "end_date": (8, 24), "peak": (8, 12)},
    {"name": "Orionidák", "start_date": (10, 2), "end_date": (11, 7), "peak": (10, 21)},
    {"name": "Leonidák", "start_date": (11, 6), "end_date": (11, 30), "peak": (11, 17)},
    {"name": "Geminidák", "start_date": (12, 4), "end_date": (12, 17), "peak": (12, 14)}
]

# Hungarian name days dictionary (month, day): [names]
# This is a simplified version with the most common names
NAMEDAYS = {
    (1, 1): ["Fruzsina"],
    (1, 2): ["Ábel"],
    (1, 3): ["Benjámin", "Genovéva"],
    (1, 4): ["Leona", "Titusz"],
    (1, 5): ["Simon"],
    (1, 6): ["Boldizsár"],
    (1, 7): ["Attila", "Ramóna"],
    (1, 8): ["Gyöngyvér"],
    (1, 9): ["Marcell"],
    (1, 10): ["Melánia"],
    (1, 11): ["Ágota"],
    (1, 12): ["Ernő"],
    (1, 13): ["Veronika"],
    (1, 14): ["Bódog"],
    (1, 15): ["Lóránt", "Loránd"],
    (1, 16): ["Gusztáv"],
    (1, 17): ["Antal", "Antónia"],
    (1, 18): ["Piroska"],
    (1, 19): ["Sára", "Márió"],
    (1, 20): ["Fábián", "Sebestyén"],
    (1, 21): ["Ágnes"],
    (1, 22): ["Vince", "Artúr"],
    (1, 23): ["Zelma", "Rajmund"],
    (1, 24): ["Timót"],
    (1, 25): ["Pál"],
    (1, 26): ["Vanda", "Paula"],
    (1, 27): ["Angelika"],
    (1, 28): ["Károly", "Karola"],
    (1, 29): ["Adél"],
    (1, 30): ["Martina", "Gerda"],
    (1, 31): ["Marcella"],
    
    (2, 1): ["Ignác"],
    (2, 2): ["Karolina", "Aida"],
    (2, 3): ["Balázs"],
    (2, 4): ["Ráhel", "Csenge"],
    (2, 5): ["Ágota", "Ingrid"],
    (2, 6): ["Dóra", "Dorottya"],
    (2, 7): ["Rómeó", "Tódor"],
    (2, 8): ["Aranka"],
    (2, 9): ["Abigél", "Alex"],
    (2, 10): ["Elvira"],
    (2, 11): ["Bertold", "Marietta"],
    (2, 12): ["Lívia", "Lídia"],
    (2, 13): ["Ella", "Linda"],
    (2, 14): ["Bálint", "Valentin"],
    (2, 15): ["Kolos", "Georgina"],

    (3, 8): ["Zoltán"],
    (3, 15): ["Kristóf"],
    
    (4, 11): ["Leó", "Szaniszló"],
    (4, 21): ["Konrád"],
    
    (5, 1): ["Fülöp", "Jakab"],
    (5, 10): ["Ármin", "Pálma"],
    
    (6, 5): ["Fatime"],
    (6, 24): ["Iván"],
    
    (7, 26): ["Anna", "Anikó"],
    
    (8, 20): ["István", "Vajk"],
    
    (9, 29): ["Mihály"],
    
    (10, 23): ["Gyöngyi"],
    
    (11, 1): ["Marianna"],
    (11, 11): ["Márton"],
    
    (12, 6): ["Miklós"],
    (12, 24): ["Ádám", "Éva"],
    (12, 25): ["Eugénia"],
    (12, 31): ["Szilveszter"]
}

# Calculate movable holidays (Easter and related)
def calculate_easter(year):
    a = year % 19
    b = year // 100
    c = year % 100
    d = b // 4
    e = b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i = c // 4
    k = c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    day = ((h + l - 7 * m + 114) % 31) + 1
    return datetime(year, month, day)

def get_movable_holidays(year):
    easter = calculate_easter(year)
    
    # Calculate related holidays
    good_friday = easter - timedelta(days=2)
    easter_monday = easter + timedelta(days=1)
    ascension = easter + timedelta(days=39)
    pentecost = easter + timedelta(days=49)
    pentecost_monday = pentecost + timedelta(days=1)
    corpus_christi = easter + timedelta(days=60)
    
    return {
        (easter.month, easter.day): "Húsvét",
        (easter_monday.month, easter_monday.day): "Húsvét hétfő",
        (good_friday.month, good_friday.day): "Nagypéntek",
        (pentecost.month, pentecost.day): "Pünkösd",
        (pentecost_monday.month, pentecost_monday.day): "Pünkösd hétfő"
    }

def is_holiday(date):
    # Check fixed holidays
    if (date.month, date.day) in FIXED_HOLIDAYS:
        return True, FIXED_HOLIDAYS[(date.month, date.day)]
    
    # Check movable holidays
    movable_holidays = get_movable_holidays(date.year)
    if (date.month, date.day) in movable_holidays:
        return True, movable_holidays[(date.month, date.day)]
    
    return False, ""

def get_nameday(date):
    if (date.month, date.day) in NAMEDAYS:
        return ", ".join(NAMEDAYS[(date.month, date.day)])
    return "Ismeretlen névnap"

def get_notable_day(date):
    if (date.month, date.day) in NOTABLE_DAYS:
        return NOTABLE_DAYS[(date.month, date.day)]
    return ""

def get_meteor_shower(date):
    for shower in METEOR_SHOWERS:
        start_month, start_day = shower["start_date"]
        end_month, end_day = shower["end_date"]
        peak_month, peak_day = shower["peak"]
        
        start_date = datetime(date.year, start_month, start_day)
        end_date = datetime(date.year, end_month, end_day)
        peak_date = datetime(date.year, peak_month, peak_day)
        
        if start_date <= date <= end_date:
            days_to_peak = (peak_date - date).days
            
            if days_to_peak == 0:
                return f"{shower['name']} meteorraj (csúcsnap)"
            elif days_to_peak > 0:
                return f"{shower['name']} meteorraj ({days_to_peak} nap a csúcsig)"
            else:
                return f"{shower['name']} meteorraj (csúcs után {abs(days_to_peak)} nappal)"
    
    return ""

def get_astronomical_info(date, config):
    if ephem is None:
        # Return dummy data if ephem is not available
        return {
            'sunrise': '06:00',
            'sunset': '20:00',
            'moonrise': '18:00',
            'moonset': '06:00',
            'moon_phase_pct': 50,
            'moon_phase_text': 'Félhold'
        }
    
    latitude = config['location']['latitude']
    longitude = config['location']['longitude']
    elevation = config['location']['elevation']
    
    # Create observer
    observer = ephem.Observer()
    observer.lat = str(latitude)
    observer.lon = str(longitude)
    observer.elevation = elevation
    observer.date = date.strftime('%Y/%m/%d')
    
    # Sun calculations
    sun = ephem.Sun()
    sun.compute(observer)
    
    # Format sunrise and sunset times
    try:
        sunrise = ephem.localtime(observer.next_rising(sun)).strftime('%H:%M')
    except (ephem.AlwaysUpError, ephem.NeverUpError):
        sunrise = "Nincs"
        
    try:
        sunset = ephem.localtime(observer.next_setting(sun)).strftime('%H:%M')
    except (ephem.AlwaysUpError, ephem.NeverUpError):
        sunset = "Nincs"
    
    # Moon calculations
    moon = ephem.Moon()
    moon.compute(observer)
    
    # Moon phase calculation
    moon_phase_pct = round(moon.phase)
    
    # Moon phase text
    if moon_phase_pct < 5:
        moon_phase_text = "Újhold"
    elif moon_phase_pct < 45:
        moon_phase_text = "Növekvő hold"
    elif moon_phase_pct < 55:
        moon_phase_text = "Telihold"
    elif moon_phase_pct < 95:
        moon_phase_text = "Fogyó hold"
    else:
        moon_phase_text = "Újhold előtt"
    
    # Moonrise and moonset times (handle cases when moon doesn't rise or set)
    try:
        moonrise = ephem.localtime(observer.next_rising(moon)).strftime('%H:%M')
    except (ephem.AlwaysUpError, ephem.NeverUpError):
        moonrise = "Nincs"
    
    try:
        moonset = ephem.localtime(observer.next_setting(moon)).strftime('%H:%M')
    except (ephem.AlwaysUpError, ephem.NeverUpError):
        moonset = "Nincs"
    
    return {
        'sunrise': sunrise,
        'sunset': sunset,
        'moonrise': moonrise,
        'moonset': moonset,
        'moon_phase_pct': moon_phase_pct,
        'moon_phase_text': moon_phase_text
    }

def get_rss_news(feed_url, max_items=3):
    try:
        feed = feedparser.parse(feed_url)
        
        if not feed.entries:
            return [{"title": "Nem sikerült betölteni a híreket", "description": ""}]
        
        news = []
        for entry in feed.entries[:max_items]:
            # Clean up HTML tags from description
            description = entry.description if hasattr(entry, 'description') else ""
            # Very simple HTML tag removal (a proper implementation would use a library)
            description = ' '.join(description.split('<')[0].split())
            
            news.append({
                "title": entry.title,
                "description": description[:100] + "..." if len(description) > 100 else description,
                "published": entry.published if hasattr(entry, 'published') else ""
            })
        
        return news
    except Exception as e:
        logger.error(f"Error fetching RSS feed: {e}")
        return [{"title": "Hiba a hírek betöltésekor", "description": str(e)}]

# Color definitions for 7-color e-Paper
black = 0
white = 1
green = 2
blue = 3
red = 4
yellow = 5
orange = 6

def format_date_with_suffix(date):
    day = date.day
    return f"{date.year}. {date.strftime('%B')} {day}."

def draw_colored_text(draw, colored_image, x, y, text, font, color):
    # Draw text in black as background
    draw.text((x, y), text, font=font, fill=black)
    # Draw colored pixels according to the specified color
    colored_image.paste(color, (x, y, x + font.getsize(text)[0], y + font.getsize(text)[1]))

def main():
    try:
        config = load_config()
        
        # Initialize e-Paper display
        try:
            epd = epd4in01f.EPD()
            epd.init()
        except Exception as e:
            logger.error(f"Error initializing e-Paper display: {e}")
            print(f"Error initializing e-Paper display: {e}")
            print("Make sure the display is properly connected and SPI is enabled")
            sys.exit(1)
        
        while True:
            try:
                logger.info("Updating display...")
                
                # Get current date and time
                now = datetime.now()
                
                # Get holiday information
                is_holiday_today, holiday_name = is_holiday(now)
                
                # Get name day
                nameday = get_nameday(now)
                
                # Get notable day
                notable_day = get_notable_day(now)
                
                # Get meteor shower information
                meteor_shower = get_meteor_shower(now)
                
                # Get astronomical information
                astro_info = get_astronomical_info(now, config)
                
                # Get RSS news
                news = get_rss_news(config['rss_feed_url'], config['max_news_items'])
                
                # Create a new image with white background
                image = Image.new('L', (epd.width, epd.height), white)
                draw = ImageDraw.Draw(image)
                
                # Create a colored image
                colored_image = Image.new('L', (epd.width, epd.height), white)
                
                # Load fonts
                try:
                    font_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'fonts')
                    date_font = ImageFont.truetype(os.path.join(font_dir, 'FreeSansBold.ttf'), config['font_sizes']['date'])
                    main_font = ImageFont.truetype(os.path.join(font_dir, 'FreeSansBold.ttf'), config['font_sizes']['main'])
                    secondary_font = ImageFont.truetype(os.path.join(font_dir, 'FreeSans.ttf'), config['font_sizes']['secondary'])
                    news_title_font = ImageFont.truetype(os.path.join(font_dir, 'FreeSansBold.ttf'), config['font_sizes']['news_title'])
                    news_desc_font = ImageFont.truetype(os.path.join(font_dir, 'FreeSans.ttf'), config['font_sizes']['news_description'])
                except IOError as e:
                    logger.warning(f"Some fonts not found: {e}, using default font")
                    date_font = ImageFont.load_default()
                    main_font = ImageFont.load_default()
                    secondary_font = ImageFont.load_default()
                    news_title_font = ImageFont.load_default()
                    news_desc_font = ImageFont.load_default()
                
                # Define layout
                margin = 10
                line_height = config['font_sizes']['main'] + 5
                
                # Display date at the top (using color based on holiday status)
                date_text = format_date_with_suffix(now)
                date_day = now.strftime("%A").capitalize()
                
                # Draw date with appropriate color for holidays
                if is_holiday_today:
                    draw_colored_text(draw, colored_image, margin, margin, date_text, date_font, red)
                    draw_colored_text(draw, colored_image, margin, margin + 60, date_day, main_font, red)
                else:
                    draw_colored_text(draw, colored_image, margin, margin, date_text, date_font, black)
                    draw_colored_text(draw, colored_image, margin, margin + 60, date_day, main_font, black)
                
                y_position = margin + 100
                
                # Display holiday name if it's a holiday
                if is_holiday_today:
                    draw_colored_text(draw, colored_image, margin, y_position, f"Ünnep: {holiday_name}", main_font, red)
                    y_position += line_height
                
                # Display name day
                draw_colored_text(draw, colored_image, margin, y_position, f"Névnap: {nameday}", main_font, blue)
                y_position += line_height
                
                # Display notable day if any
                if notable_day:
                    draw_colored_text(draw, colored_image, margin, y_position, notable_day, main_font, green)
                    y_position += line_height
                
                # Display astronomical information
                draw_colored_text(draw, colored_image, margin, y_position, f"Napkelte: {astro_info['sunrise']} - Napnyugta: {astro_info['sunset']}", main_font, orange)
                y_position += line_height
                
                draw_colored_text(draw, colored_image, margin, y_position, f"Holdkelte: {astro_info['moonrise']} - Holdnyugta: {astro_info['moonset']}", main_font, blue)
                y_position += line_height
                
                draw_colored_text(draw, colored_image, margin, y_position, f"Hold fázis: {astro_info['moon_phase_text']} ({astro_info['moon_phase_pct']}%)", main_font, blue)
                y_position += line_height
                
                # Display meteor shower information if any
                if meteor_shower:
                    draw_colored_text(draw, colored_image, margin, y_position, meteor_shower, main_font, yellow)
                    y_position += line_height
                
                # Draw a separator line
                draw.line((margin, y_position, epd.width - margin, y_position), fill=0)
                y_position += 15
                
                # Display RSS news
                draw_colored_text(draw, colored_image, margin, y_position, "Telex.hu hírek:", main_font, orange)
                y_position += line_height
                
                for i, item in enumerate(news):
                    # News title
                    draw_colored_text(draw, colored_image, margin, y_position, f"{i+1}. {item['title']}", news_title_font, green)
                    y_position += config['font_sizes']['news_title'] + 2
                    
                    # News description if available
                    if item['description']:
                        draw_colored_text(draw, colored_image, margin + 10, y_position, item['description'], news_desc_font, black)
                        y_position += config['font_sizes']['news_description'] + 10
                    else:
                        y_position += 5
                
                # Display the image on the e-paper display
                try:
                    epd.display(epd.getbuffer(image), epd.getbuffer(colored_image))
                    logger.info("Display refreshed successfully")
                except Exception as e:
                    logger.error(f"Error refreshing display: {e}")
                
                # Wait for the refresh interval
                time.sleep(config['refresh_interval'])
                
            except KeyboardInterrupt:
                logger.info("Keyboard interrupt detected, exiting...")
                break
            except Exception as e:
                logger.error(f"Error in main loop: {e}")
                logger.error(traceback.format_exc())
                time.sleep(60)  # Wait a minute before retrying
        
        # Clean up and go to sleep
        epd.sleep()
        
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        logger.error(traceback.format_exc())
        print(f"Fatal error: {e}")
        print("Check the log for details")
        sys.exit(1)

if __name__ == '__main__':
    main()
