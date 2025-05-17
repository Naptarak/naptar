#!/bin/bash

# install.sh (v2 - javított)
# Telepítő szkript az e-Paper naptár kijelzőhöz Raspberry Pi Zero 2W-n
# Kijelző: Waveshare 4.01 inch e-Paper HAT (F) (7 színű, 640x400)

# Színek a kimenethez
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Alkalmazás könyvtára és egyéb beállítások
APP_NAME="epaper_calendar"
APP_DIR="/opt/$APP_NAME"
VENV_DIR="$APP_DIR/venv"
PYTHON_SCRIPT_NAME="display_calendar.py"
RUN_SCRIPT_NAME="run_display.sh"
LOG_FILE="/tmp/${APP_NAME}.log"
CRON_COMMENT="ePaper Calendar Update"

# Ellenőrizzük, hogy a szkript rootként fut-e
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${YELLOW}Ezt a szkriptet root jogosultságokkal (sudo) kell futtatni.${NC}"
  exit 1
fi

echo -e "${GREEN}E-Paper Naptár Telepítő Indítása (v2)...${NC}"

# --- 1. Rendszer frissítése és alapvető csomagok telepítése ---
echo -e "${GREEN}Rendszer frissítése és alapvető csomagok telepítése...${NC}"
apt-get update && apt-get upgrade -y

# Frissített csomaglista: wiringpi eltávolítva, libtiff5 -> libtiff6, python3-rpi.gpio és python3-spidev hozzáadva
REQUIRED_PACKAGES="git python3 python3-pip python3-venv python3-pil python3-numpy libopenjp2-7 libtiff6 python3-rpi.gpio python3-spidev ttf-dejavu"

echo "Szükséges APT csomagok telepítése: $REQUIRED_PACKAGES"
if ! apt-get install -y $REQUIRED_PACKAGES; then
    echo -e "${RED}HIBA: Nem sikerült telepíteni az alapvető rendszerfüggőségeket.${NC}"
    echo -e "${YELLOW}Lehetséges probléma a 'libtiff6'-tal. Ha ez a hiba, próbáld meg a 'libtiff5'-öt, ha régebbi rendszered van.${NC}"
    echo -e "${YELLOW}Futtasd manuálisan: sudo apt-get install <csomagnév> hogy lásd a pontos hibát.${NC}"
    echo -e "${YELLOW}Ellenőrizd az internetkapcsolatot és az apt forrásokat (pl. /etc/apt/sources.list).${NC}"
    exit 1
fi

# Ellenőrizzük a python3-pip telepítését expliciten
if ! command -v pip3 &> /dev/null; then
    echo -e "${RED}HIBA: A pip3 telepítése sikertelen volt. Próbáld meg manuálisan: sudo apt-get install python3-pip${NC}"
    exit 1
fi

# --- 2. SPI interfész engedélyezésének ellenőrzése (emlékeztető) ---
echo -e "${YELLOW}FIGYELEM: Győződj meg róla, hogy az SPI interfész engedélyezve van a 'sudo raspi-config' segítségével.${NC}"
echo -e "${YELLOW}Interfacing Options -> SPI -> Yes. Ha most engedélyezted, indítsd újra a Pi-t a telepítés folytatása előtt.${NC}"
# Megpróbáljuk non-interaktívan engedélyezni, de a manuális ellenőrzés a biztos.
if command -v raspi-config &> /dev/null; then
    raspi-config nonint get_spi | grep -q "0" # 0 means enabled
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Az SPI nincs engedélyezve. Megpróbálom engedélyezni...${NC}"
        raspi-config nonint do_spi 0
        echo -e "${YELLOW}Az SPI engedélyezve. Javasolt egy újraindítás a folytatás előtt.${NC}"
        read -p "Szeretnéd most újraindítani? (i/n): " REBOOT_CHOICE
        if [[ "$REBOOT_CHOICE" == "i" || "$REBOOT_CHOICE" == "I" ]]; then
            echo "Újraindítás..."
            reboot
            exit 0
        fi
    fi
else
    echo -e "${YELLOW}A 'raspi-config' parancs nem található. Kérlek, manuálisan ellenőrizd az SPI beállításokat.${NC}"
fi


# --- 3. Waveshare e-Paper Python illesztőprogram letöltése és másolása ---
echo -e "${GREEN}Waveshare e-Paper Python könyvtár letöltése és előkészítése...${NC}"
if [ -d "/tmp/e-Paper" ]; then
    rm -rf /tmp/e-Paper
fi
# Csak a Python részt töltjük le, sekély klónozással
git clone --depth 1 --filter=blob:none --sparse https://github.com/waveshare/e-Paper.git /tmp/e-Paper
if [ $? -ne 0 ]; then
    echo -e "${RED}HIBA: Nem sikerült letölteni a Waveshare e-Paper repository-t. Ellenőrizd a git telepítését és az internetkapcsolatot.${NC}"
    exit 1
fi
cd /tmp/e-Paper
git sparse-checkout set RaspberryPi_JetsonNano/python/lib/waveshare_epd
if [ $? -ne 0 ]; then
    echo -e "${RED}HIBA: Nem sikerült beállítani a sparse-checkout-ot a Waveshare e-Paper repository-ban.${NC}"
    cd -
    exit 1
fi
cd - # Vissza az eredeti könyvtárba

# --- 4. Alkalmazás könyvtár és virtuális környezet létrehozása ---
echo -e "${GREEN}Alkalmazás könyvtár létrehozása: $APP_DIR ${NC}"
mkdir -p "$APP_DIR/lib"
if [ $? -ne 0 ]; then
    echo -e "${RED}HIBA: Nem sikerült létrehozni az alkalmazás könyvtárát: $APP_DIR ${NC}"
    exit 1
fi

# Waveshare Python lib másolása az alkalmazásunk mappájába
echo -e "${GREEN}Waveshare Python könyvtár másolása ide: $APP_DIR/lib/ ${NC}"
if [ -d "/tmp/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd" ]; then
    cp -R /tmp/e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd "$APP_DIR/lib/"
    if [ $? -ne 0 ]; then
        echo -e "${RED}HIBA: Nem sikerült átmásolni a Waveshare Python könyvtárat ide: $APP_DIR/lib/waveshare_epd ${NC}"
        exit 1
    fi
else
    echo -e "${RED}HIBA: A letöltött Waveshare könyvtár struktúrája nem megfelelő, a RaspberryPi_JetsonNano/python/lib/waveshare_epd nem található.${NC}"
    exit 1
fi

echo -e "${GREEN}Python virtuális környezet létrehozása: $VENV_DIR ${NC}"
python3 -m venv "$VENV_DIR"
if [ $? -ne 0 ]; then
    echo -e "${RED}HIBA: Nem sikerült létrehozni a Python virtuális környezetet.${NC}"
    exit 1
fi

# --- 5. Python függőségek telepítése a virtuális környezetbe ---
echo -e "${GREEN}Python függőségek telepítése...${NC}"
# Aktiváljuk a venv-et a pip parancsokhoz
source "$VENV_DIR/bin/activate"

# A hunnameday helyett a hunkal csomagot használjuk
PIP_PACKAGES="Pillow holidays astral feedparser requests hunkal"
echo "Telepítendő PIP csomagok: $PIP_PACKAGES"
if ! pip3 install $PIP_PACKAGES; then
    echo -e "${RED}HIBA: Nem sikerült telepíteni a Python függőségeket ($PIP_PACKAGES).${NC}"
    echo -e "${YELLOW}Ellenőrizd az internetkapcsolatot és a pip működését.${NC}"
    echo -e "${YELLOW}Próbáld meg manuálisan a venv aktiválása után: pip3 install $PIP_PACKAGES ${NC}"
    deactivate
    exit 1
fi
deactivate

# --- 6. Python alkalmazás létrehozása ---
echo -e "${GREEN}Python alkalmazás létrehozása ($APP_DIR/$PYTHON_SCRIPT_NAME)...${NC}"
# A Python szkript tartalma itt következik (változatlan, kivéve a sys.path javítást)
# A sys.path javítás:
# Régi: sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), 'lib'))
# Új: sys.path.append(os.path.join(os.path.dirname(os.path.realpath(__file__)), 'lib'))
# Ez a javítás a Python scriptben lesz implementálva.

cat << EOF > "$APP_DIR/$PYTHON_SCRIPT_NAME"
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import datetime
import time
import sys
import os
import logging

# Helyi Waveshare könyvtár hozzáadása a Python útvonalhoz
# Az APP_DIR a szkriptet és a 'lib' alkönyvtárat tartalmazó mappa.
# Pl. /opt/epaper_calendar/display_calendar.py és /opt/epaper_calendar/lib/waveshare_epd
# A sys.path.append javítva:
APP_SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
LIB_PATH = os.path.join(APP_SCRIPT_DIR, 'lib')
sys.path.append(LIB_PATH)

try:
    from waveshare_epd import epd4in01f
except ImportError as e:
    # Logolás beállítása korán, hogy ez is naplózva legyen
    LOG_PATH_FOR_IMPORT_ERROR = "$LOG_FILE" 
    logging.basicConfig(filename=LOG_PATH_FOR_IMPORT_ERROR, level=logging.INFO, format='%(asctime)s %(levelname)s: %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
    logging.error(f"HIBA: Waveshare EPD könyvtár nem található itt: {LIB_PATH}. Hiba: {e}")
    logging.error(f"Sys.path tartalma: {sys.path}")
    sys.exit(f"Kérlek telepítsd a Waveshare illesztőprogramot megfelelően, vagy ellenőrizd a LIB_PATH (${LIB_PATH}) tartalmát.")


from PIL import Image, ImageDraw, ImageFont
import holidays
import astral
import astral.sun
import astral.moon
import feedparser
import requests
from hunkal import HungarianCalendar, HolidayType # hunkal használata

# --- Konfiguráció ---
CITY_NAME = "Pecs"
COUNTRY_NAME = "Hungary"
TIMEZONE = "Europe/Budapest"
LATITUDE = 46.0724
LONGITUDE = 18.2284
EPD_WIDTH = 640
EPD_HEIGHT = 400
RSS_URL = "https://telex.hu/rss"
LOG_PATH = "$LOG_FILE"

# --- Betűtípusok ---
FONT_BOLD_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_REGULAR_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_SMALL_REGULAR_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

# --- Színek (RGB tuple-ök a Pillow számára) ---
COLOR_BLACK = (0, 0, 0)
COLOR_WHITE = (255, 255, 255)
COLOR_GREEN = (0, 255, 0)
COLOR_BLUE = (0, 0, 255)
COLOR_RED = (255, 0, 0)
COLOR_YELLOW = (255, 255, 0)
COLOR_ORANGE = (255, 128, 0)

# --- Logging beállítása ---
log_dir = os.path.dirname(LOG_PATH)
if not os.path.exists(log_dir):
    os.makedirs(log_dir, exist_ok=True)

logging.basicConfig(filename=LOG_PATH,
                    level=logging.INFO,
                    format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%Y-%m-%d %H:%M:%S')

# --- Adatlekérő Funkciók (változatlanok, lásd előző válasz) ---
def get_calendar_data(target_date):
    cal = HungarianCalendar(target_date.year)
    data = {
        "holiday_name": None,
        "is_holiday": False,
        "name_days": [],
        "memorial_days": [],
        "other_events": []
    }
    day_info = cal.get_day(target_date.month, target_date.day)
    if day_info:
        for event in day_info:
            if event.type == HolidayType.PUBLIC_HOLIDAY or event.type == HolidayType.RELIGIOUS_HOLIDAY_WITH_WORKDAY_SWAP:
                data["is_holiday"] = True
                data["holiday_name"] = event.name
            elif event.type == HolidayType.NAME_DAY:
                data["name_days"].append(event.name)
            elif event.type == HolidayType.MEMORIAL_DAY or event.type == HolidayType.IMPORTANT_DAY:
                data["memorial_days"].append(event.name)
            else:
                data["other_events"].append(event.name)
    return data

def get_astro_data(city_info, target_date):
    try:
        sun_info = astral.sun.sun(city_info.observer, date=target_date, tzinfo=city_info.timezone)
        moon_phase_val = astral.moon.phase(target_date)
        try:
            moonrise_utc = astral.moon.moonrise(city_info.observer, date=target_date)
            moonrise_local = moonrise_utc.astimezone(city_info.timezone) if moonrise_utc else None
        except ValueError:
            moonrise_local = None
        try:
            moonset_utc = astral.moon.moonset(city_info.observer, date=target_date)
            moonset_local = moonset_utc.astimezone(city_info.timezone) if moonset_utc else None
        except ValueError:
            moonset_local = None

        if 0 <= moon_phase_val < 1.0 or moon_phase_val >= 27.0: phase_text = "Újhold"
        elif 1.0 <= moon_phase_val < 6.5: phase_text = "Növekvő sarló"
        elif 6.5 <= moon_phase_val < 7.5: phase_text = "Első negyed"
        elif 7.5 <= moon_phase_val < 13.0: phase_text = "Növekvő hold"
        elif 13.0 <= moon_phase_val < 14.5: phase_text = "Telihold"
        elif 14.5 <= moon_phase_val < 20.0: phase_text = "Fogyó hold"
        elif 20.0 <= moon_phase_val < 21.5: phase_text = "Utolsó negyed"
        else: phase_text = "Fogyó sarló"

        return {
            "sunrise": sun_info["sunrise"].strftime("%H:%M") if sun_info["sunrise"] else "N/A",
            "sunset": sun_info["sunset"].strftime("%H:%M") if sun_info["sunset"] else "N/A",
            "moonrise": moonrise_local.strftime("%H:%M") if moonrise_local else "N/A",
            "moonset": moonset_local.strftime("%H:%M") if moonset_local else "N/A",
            "moon_phase_percent": f"{((moon_phase_val / 27.99) * 100):.0f}%",
            "moon_phase_text": phase_text
        }
    except Exception as e:
        logging.error(f"Hiba az asztrológiai adatok lekérésekor: {e}")
        return {}

def get_meteor_showers(target_date):
    showers = {
        "Quadrantidák": {"start_month": 12, "start_day": 28, "peak_month": 1, "peak_day": 3, "end_month": 1, "end_day": 12},
        "Lyridák": {"start_month": 4, "start_day": 16, "peak_month": 4, "peak_day": 22, "end_month": 4, "end_day": 25},
        "Eta Aquaridák": {"start_month": 4, "start_day": 19, "peak_month": 5, "peak_day": 6, "end_month": 5, "end_day": 28},
        "Déli Delta Aquaridák": {"start_month": 7, "start_day": 12, "peak_month": 7, "peak_day": 30, "end_month": 8, "end_day": 23},
        "Perseidák": {"start_month": 7, "start_day": 17, "peak_month": 8, "peak_day": 12, "end_month": 8, "end_day": 24},
        "Drakonidák": {"start_month": 10, "start_day": 6, "peak_month": 10, "peak_day": 8, "end_month": 10, "end_day": 10},
        "Orionidák": {"start_month": 10, "start_day": 2, "peak_month": 10, "peak_day": 21, "end_month": 11, "end_day": 7},
        "Leonidák": {"start_month": 11, "start_day": 6, "peak_month": 11, "peak_day": 17, "end_month": 11, "end_day": 30},
        "Geminidák": {"start_month": 12, "start_day": 4, "peak_month": 12, "peak_day": 14, "end_month": 12, "end_day": 17},
        "Ursidák": {"start_month": 12, "start_day": 17, "peak_month": 12, "peak_day": 22, "end_month": 12, "end_day": 26},
    }
    active_showers_info = []
    year = target_date.year
    for name, data in showers.items():
        try:
            start_dt_year = year if data["start_month"] <= data["end_month"] else (year -1 if target_date.month <= data["end_month"] else year)
            end_dt_year = year if data["start_month"] <= data["end_month"] else (year +1 if target_date.month >= data["start_month"] else year)
            
            start_dt = datetime.date(start_dt_year, data["start_month"], data["start_day"])
            end_dt = datetime.date(end_dt_year, data["end_month"], data["end_day"])
            peak_dt = datetime.date(year, data["peak_month"], data["peak_day"])

            if name == "Quadrantidák":
                if target_date.month == 12:
                    peak_dt = datetime.date(year + 1, data["peak_month"], data["peak_day"])
                    end_dt = datetime.date(year + 1, data["end_month"], data["end_day"])
                elif target_date.month == 1:
                     start_dt = datetime.date(year - 1, data["start_month"], data["start_day"])
            
            current_period_start = start_dt
            current_period_end = end_dt
            
            # Handle year-spanning showers for matching
            if start_dt.year < target_date.year and end_dt.year < target_date.year and name == "Quadrantidák" and target_date.month == 1 : # Check previous year's Quadrantids end period
                 current_period_start = datetime.date(target_date.year -1, data["start_month"], data["start_day"])
                 current_period_end = datetime.date(target_date.year, data["end_month"], data["end_day"])


            if current_period_start <= target_date <= current_period_end:
                info = name
                if abs((target_date - peak_dt).days) <= 2: # Peak activity window
                    info += f" (Csúcs: {data['peak_month']}.{data['peak_day']}.)"
                active_showers_info.append(info)
        except ValueError:
            logging.warning(f"Érvénytelen dátum a(z) {name} meteorrajhoz: {data}")
            continue
    return active_showers_info

def get_rss_feed(url, count=3):
    try:
        headers = {'User-Agent': 'RaspberryPiEPaperCalendar/1.0'}
        feed = feedparser.parse(url, agent=headers, request_timeout=10) # Timeout hozzáadva
        return [entry.title for entry in feed.entries[:count]]
    except Exception as e:
        logging.error(f"Hiba az RSS feed lekérésekor ({url}): {e}")
        return ["Hírforrás nem elérhető"] * count

# --- Fő Rajzolási Logika (változatlan, lásd előző válasz) ---
def main():
    logging.info("E-Paper frissítés indítása.")
    epd = None
    try:
        epd = epd4in01f.EPD()
        logging.info("EPD inicializálása...")
        epd.Init()
        
        image = Image.new('RGB', (EPD_WIDTH, EPD_HEIGHT), COLOR_WHITE)
        draw = ImageDraw.Draw(image)

        try:
            font_date = ImageFont.truetype(FONT_BOLD_PATH, 32)
            font_holiday = ImageFont.truetype(FONT_BOLD_PATH, 26)
            font_nameday = ImageFont.truetype(FONT_REGULAR_PATH, 24)
            font_memorial = ImageFont.truetype(FONT_REGULAR_PATH, 20)
            font_astro_label = ImageFont.truetype(FONT_BOLD_PATH, 20)
            font_astro_value = ImageFont.truetype(FONT_REGULAR_PATH, 20)
            font_meteor = ImageFont.truetype(FONT_SMALL_REGULAR_PATH, 18)
            font_week = ImageFont.truetype(FONT_SMALL_REGULAR_PATH, 18)
            font_rss = ImageFont.truetype(FONT_SMALL_REGULAR_PATH, 16)
        except IOError as e:
            logging.error(f"Betűtípusok nem találhatóak: {e}. Alapértelmezett betűtípus használata.")
            font_date = font_holiday = font_nameday = font_memorial = ImageFont.load_default()
            font_astro_label = font_astro_value = font_meteor = font_week = font_rss = ImageFont.load_default()

        import pytz # Időzóna kezeléshez
        tz = pytz.timezone(TIMEZONE)
        now = datetime.datetime.now(tz)
        today_date_obj = now.date()

        city_info = astral.LocationInfo(CITY_NAME, COUNTRY_NAME, TIMEZONE, LATITUDE, LONGITUDE)

        hun_months = ["január", "február", "március", "április", "május", "június", "július", "augusztus", "szeptember", "október", "november", "december"]
        hun_days = ["hétfő", "kedd", "szerda", "csütörtök", "péntek", "szombat", "vasárnap"]
        current_date_str_hu = f"{now.year}. {hun_months[now.month-1]} {now.day}., {hun_days[now.weekday()]}"

        calendar_data = get_calendar_data(today_date_obj)
        astro_data = get_astro_data(city_info, today_date_obj)
        meteor_showers = get_meteor_showers(today_date_obj)
        rss_titles = get_rss_feed(RSS_URL)
        week_number = today_date_obj.isocalendar()[1]

        y_pos = 10
        padding = 10
        line_spacing_large = 8
        line_spacing_medium = 6
        line_spacing_small = 4

        date_color = COLOR_RED if calendar_data["is_holiday"] else COLOR_BLACK
        draw.text((padding, y_pos), current_date_str_hu.upper(), font=font_date, fill=date_color)
        y_pos += font_date.getbbox(current_date_str_hu.upper())[3] + line_spacing_large

        if calendar_data["is_holiday"] and calendar_data["holiday_name"]:
            draw.text((padding, y_pos), calendar_data["holiday_name"], font=font_holiday, fill=COLOR_RED)
            y_pos += font_holiday.getbbox(calendar_data["holiday_name"])[3] + line_spacing_medium
        
        if calendar_data["name_days"]:
            nameday_str = "Névnap: " + ", ".join(calendar_data["name_days"])
            draw.text((padding, y_pos), nameday_str, font=font_nameday, fill=COLOR_BLUE)
            y_pos += font_nameday.getbbox(nameday_str)[3] + line_spacing_medium
        
        significant_days = calendar_data["memorial_days"] + calendar_data["other_events"]
        if significant_days:
            for day_event in significant_days:
                if day_event != calendar_data["holiday_name"]: # Ne írjuk ki újra, ha már ünnepként szerepel
                    event_text_width = draw.textlength(day_event, font=font_memorial)
                    if event_text_width > (EPD_WIDTH - 2 * padding): # Egyszerű tördelés, ha túl hosszú
                        # TODO: Jobb tördelési logika kellene ide
                        day_event_short = day_event[:int(len(day_event) * (EPD_WIDTH - 2*padding)/event_text_width)-3] + "..."
                        draw.text((padding, y_pos), day_event_short, font=font_memorial, fill=COLOR_GREEN)
                        y_pos += font_memorial.getbbox(day_event_short)[3] + line_spacing_small
                    else:
                        draw.text((padding, y_pos), day_event, font=font_memorial, fill=COLOR_GREEN)
                        y_pos += font_memorial.getbbox(day_event)[3] + line_spacing_small
            y_pos += line_spacing_medium - line_spacing_small

        y_pos = max(y_pos, 130) 

        col1_x = padding
        col2_x = EPD_WIDTH // 2 
        astro_y_start = y_pos

        if astro_data:
            draw.text((col1_x, astro_y_start), "Napkelte:", font=font_astro_label, fill=COLOR_ORANGE)
            draw.text((col1_x + 110, astro_y_start), astro_data.get('sunrise', 'N/A'), font=font_astro_value, fill=COLOR_BLACK)
            
            astro_y_start_col2 = astro_y_start
            draw.text((col2_x, astro_y_start_col2), "Napnyugta:", font=font_astro_label, fill=COLOR_ORANGE)
            draw.text((col2_x + 120, astro_y_start_col2), astro_data.get('sunset', 'N/A'), font=font_astro_value, fill=COLOR_BLACK)
            
            current_astro_y = astro_y_start + font_astro_label.getbbox("N")[3] + line_spacing_small # "N" magassága kb.
            current_astro_y_col2 = astro_y_start_col2 + font_astro_label.getbbox("N")[3] + line_spacing_small

            draw.text((col1_x, current_astro_y), "Holdkelte:", font=font_astro_label, fill=COLOR_BLUE)
            draw.text((col1_x + 110, current_astro_y), astro_data.get('moonrise', 'N/A'), font=font_astro_value, fill=COLOR_BLACK)

            draw.text((col2_x, current_astro_y_col2), "Holdnyugta:", font=font_astro_label, fill=COLOR_BLUE)
            draw.text((col2_x + 120, current_astro_y_col2), astro_data.get('moonset', 'N/A'), font=font_astro_value, fill=COLOR_BLACK)
            
            current_astro_y += font_astro_label.getbbox("N")[3] + line_spacing_small
            current_astro_y_col2 += font_astro_label.getbbox("N")[3] + line_spacing_small

            moon_phase_str = f"{astro_data.get('moon_phase_text','N/A')} ({astro_data.get('moon_phase_percent','N/A')})"
            y_pos = max(current_astro_y, current_astro_y_col2)
            draw.text((col1_x, y_pos), "Holdfázis:", font=font_astro_label, fill=COLOR_BLUE)
            y_pos += font_astro_label.getbbox("N")[3] + line_spacing_small # Következő sorba a szöveg
            draw.text((col1_x + padding, y_pos), moon_phase_str, font=font_astro_value, fill=COLOR_BLACK)
            y_pos += font_astro_value.getbbox("N")[3] + line_spacing_medium
        
        if meteor_showers:
            meteor_title = "Meteorraj:"
            draw.text((padding, y_pos), meteor_title, font=font_meteor, fill=COLOR_GREEN)
            y_pos += font_meteor.getbbox("N")[3] + line_spacing_small
            for shower_name in meteor_showers:
                # Egyszerűsített kiírás, ha túl sok van, lehet nem fér ki mind
                draw.text((padding + 15, y_pos), shower_name, font=font_meteor, fill=COLOR_GREEN)
                y_pos += font_meteor.getbbox("N")[3] + line_spacing_small
            y_pos += line_spacing_medium - line_spacing_small


        week_str = f"{week_number}. hét"
        # Jobb alsó sarokba (vagy valahova, ahol van hely)
        week_text_width = draw.textlength(week_str, font=font_week)
        draw.text((EPD_WIDTH - week_text_width - padding, EPD_HEIGHT - (font_rss.getbbox("N")[3] * 4) - padding*2), week_str, font=font_week, fill=COLOR_BLACK)
        # y_pos += font_week.getbbox("N")[3] + line_spacing_large # Ezt a sort ki kell venni, ha máshova kerül a hét


        rss_y_start = EPD_HEIGHT - (3 * (font_rss.getbbox("N")[3] + line_spacing_small)) - padding 
        draw.line([(0, rss_y_start - line_spacing_small), (EPD_WIDTH, rss_y_start - line_spacing_small)], fill=COLOR_BLACK, width=1)

        if rss_titles:
            for i, title in enumerate(rss_titles):
                if i >= 3: break 
                max_rss_len = (EPD_WIDTH - padding * 2 - draw.textlength("• ", font=font_rss) ) / (font_rss.getbbox("A")[3] / 2 + 0.5) # Karakterek becslése
                display_title = (title[:int(max_rss_len)-3] + "...") if len(title) > int(max_rss_len) else title
                
                draw.text((padding, rss_y_start + (i * (font_rss.getbbox("N")[3] + line_spacing_small))),
                          f"• {display_title}", font=font_rss, fill=COLOR_BLACK)
        
        logging.info("Kép előkészítve, megjelenítés...")
        epd.display(image)
        logging.info("Kijelző alvó módba helyezése.")
        epd.sleep()

    except IOError as e:
        logging.error(f"IO Hiba (valószínűleg betűtípus vagy fájl): {e}")
    except ImportError as e: # Ez a blokk már lehet nem is kell, ha a script elején van a check
        logging.error(f"Importálási hiba a main-ben: {e}.")
    except Exception as e:
        logging.exception(f"Váratlan hiba történt a Python szkriptben:")
    finally:
        if epd:
            logging.info("Modul erőforrásainak felszabadítása (GPIO).")
            # epd.sleep() már megtörtént a try blokkban, ha sikeres volt
            # A module_exit fontos, hogy a GPIO lábakat felszabadítsa
            epd4in01f.epdconfig.module_exit(cleanup=True)
        logging.info("E-Paper frissítés befejezve.")

if __name__ == '__main__':
    main()
EOF
chmod +x "$APP_DIR/$PYTHON_SCRIPT_NAME"

# --- 7. Futtató szkript létrehozása ---
echo -e "${GREEN}Futtató szkript létrehozása ($APP_DIR/$RUN_SCRIPT_NAME)...${NC}"
cat << EOF > "$APP_DIR/$RUN_SCRIPT_NAME"
#!/bin/bash
APP_DIR="$APP_DIR"
VENV_DIR="$VENV_DIR"
PYTHON_SCRIPT="$APP_DIR/$PYTHON_SCRIPT_NAME"
LOG_FILE="$LOG_FILE"

# Győződjünk meg róla, hogy a log fájl írható
mkdir -p "$(dirname "\$LOG_FILE")" # Log könyvtár létrehozása, ha nem létezik
touch "\$LOG_FILE"
chmod 666 "\$LOG_FILE"

echo "Indítás: \$(date)" >> "\$LOG_FILE"
# Virtuális környezet aktiválása
source "\$VENV_DIR/bin/activate"

# Futtatás
python3 "\$PYTHON_SCRIPT" >> "\$LOG_FILE" 2>&1
PY_EXIT_CODE=\$?

if [ \$PY_EXIT_CODE -ne 0 ]; then
    echo "HIBA a Python szkript futtatása során (Kilépési kód: \$PY_EXIT_CODE). Részletek: \$LOG_FILE" >> "\$LOG_FILE"
fi

# Deaktiválás
deactivate
echo "Befejezés: \$(date)" >> "\$LOG_FILE"
echo "--------------------------------------" >> "\$LOG_FILE"
EOF
chmod +x "$APP_DIR/$RUN_SCRIPT_NAME"

# --- 8. Cron job beállítása ---
echo -e "${GREEN}Cron job beállítása 10 percenkénti frissítéshez...${NC}"
(crontab -l 2>/dev/null | grep -v -F "$CRON_COMMENT") | crontab -
(crontab -l 2>/dev/null; echo "*/10 * * * * $APP_DIR/$RUN_SCRIPT_NAME # $CRON_COMMENT") | crontab -
if [ $? -ne 0 ]; then
    echo -e "${RED}HIBA: Nem sikerült beállítani a cron jobot.${NC}"
    echo -e "${YELLOW}Próbáld meg manuálisan: crontab -e, majd add hozzá: */10 * * * * $APP_DIR/$RUN_SCRIPT_NAME # $CRON_COMMENT ${NC}"
else
    echo -e "${GREEN}Cron job sikeresen beállítva.${NC}"
fi

# --- 9. Befejezés és takarítás ---
echo -e "${GREEN}Takarítás...${NC}"
rm -rf /tmp/e-Paper

echo -e "${GREEN}A TELEPÍTÉS BEFEJEZŐDÖTT!${NC}"
echo -e "Az alkalmazás a következő helyre települt: ${YELLOW}$APP_DIR${NC}"
echo -e "A naplófájl itt található: ${YELLOW}$LOG_FILE${NC}"
echo -e "Az első frissítés kb. 10 percen belül várható, vagy futtasd manuálisan: ${YELLOW}sudo $APP_DIR/$RUN_SCRIPT_NAME${NC} (vagy felhasználóként, ha a log írási jogok engedik)"
echo -e "${YELLOW}FONTOS: Ha még nem tetted meg, és a szkript nem indította újra a Pi-t, egy újraindítás javasolt az SPI driverek megfelelő betöltődéséhez.${NC}"

exit 0
