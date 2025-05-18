#!/usr/bin/env bash
# Telepítő Raspberry Pi Zero 2 W + Waveshare 4.01" (F) 7-színű e-paperhez
set -euo pipefail
trap 'echo -e "\e[31m[HIBA]\e[0m A(z) ${BASH_SOURCE[0]} ${LINENO}. sorában leálltunk ($?)."' ERR

APP_DIR="/opt/calendar_display"
VENV_DIR="$APP_DIR/venv"
EPD_DIR="/opt/waveshare_epd"
SERVICE_NAME="calendar_display"

echo -e "\e[34m[INFO]\e[0m Telepítés indul…"

if [[ $EUID -ne 0 ]]; then
  echo -e "\e[31m[HIBA]\e[0m Kérlek futtasd sudo-val!"
  exit 1
fi

echo -e "\e[34m[INFO]\e[0m APT frissítés és alapcsomagok…"
apt-get update -y
apt-get install -y --no-install-recommends \
    git python3 python3-venv python3-pip python3-dev \
    libopenjp2-7 libjpeg-dev zlib1g-dev libfreetype6-dev \
    libatlas-base-dev libharfbuzz-dev libfribidi-dev

# --- wiringPi (ha hiányzik) -----------------------------
if ! command -v gpio &>/dev/null; then
  echo -e "\e[33m[FIGYELMEZTETÉS]\e[0m wiringPi nincs, próbálom telepíteni…"
  if apt-get install -y wiringpi; then
     echo -e "\e[32m[OK]\e[0m wiringPi APT-ből felment."
  else
     echo -e "\e[33m[INFO]\e[0m APT nem találta, forrásból építünk…"
     apt-get install -y build-essential
     git clone https://github.com/WiringPi/WiringPi.git /tmp/WiringPi
     (cd /tmp/WiringPi && ./build)
  fi
fi

# --- libtiff5 fallback (Bookwormon már libtiff6 létezik) --
if ! dpkg -s libtiff5 &>/dev/null; then
  echo -e "\e[33m[FIGYELMEZTETÉS]\e[0m libtiff5 nem található, megpróbálom feltenni…"
  apt-get install -y libtiff5 || true  # ha nincs repo-ban, a python pillow build-el linkel libtiff6-tal
fi

# --- Waveshare e-paper Python-meghajtó -------------------
echo -e "\e[34m[INFO]\e[0m Waveshare meghajtó telepítése…"
if [[ ! -d "$EPD_DIR" ]]; then
  git clone https://github.com/waveshareteam/e-Paper.git "$EPD_DIR"  # :contentReference[oaicite:0]{index=0}
fi
# szimbolikus link a python-példák könyvtárára, hogy importálható legyen
ln -sf "$EPD_DIR"/RaspberryPi_JetsonNano/python/lib/waveshare_epd /usr/local/lib/python3.*/dist-packages/ || true

# --- Saját alkalmazás könyvtár ---------------------------
mkdir -p "$APP_DIR"
chown -R "$SUDO_USER":"$SUDO_USER" "$APP_DIR"

# --- Python virtuális környezet --------------------------
echo -e "\e[34m[INFO]\e[0m Virtuális környezet létrehozása…"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

pip install --upgrade pip
pip install pillow numpy feedparser holidays astral==3.* skyfield skyfield-data pytz # :contentReference[oaicite:1]{index=1}

# --- Python alkalmazás fájl ------------------------------
cat > "$APP_DIR/calendar_display.py" << 'PY'
#!/usr/bin/env python3
"""
Raspberry Pi Zero 2 W + Waveshare 4.01" (F) 7-színű e-paper naptár-kijelző.
10 percenként frissíti:
  • Dátum, ünnep, névnap, jeles nap
  • Nap-/hold-kelte/nyugta, holdfázis
  • Aktuális meteor-raj (ha van)
  • Telex RSS 3 legfrissebb hír
Színeket a kijelző 7 palettájához igazítva állítja be.
"""
import os, sys, datetime as dt, time, math, json, textwrap, traceback, feedparser
import holidays, pytz
from astral import LocationInfo
from astral.sun import sun
from astral.moon import moon_phase, moon_rise, moon_set
from skyfield.api import load
from PIL import Image, ImageDraw, ImageFont

try:
    from waveshare_epd import epd7in3f as epd  # a 4.01" (F) 640×400 7-szín panel illesztője
except ImportError:
    print("Nem találom a waveshare_epd modult – ellenőrizd a telepítést!", file=sys.stderr)
    sys.exit(1)

# --- Beállítások ---------------------------------------------------
T_ZONE      = pytz.timezone("Europe/Budapest")
LAT, LON    = 47.4979, 19.0402      # Budapest
RSS_URL     = "https://telex.hu/rss"
NAMEFILE    = os.path.join(os.path.dirname(__file__), "nevnapok.json")
METEORFILE  = os.path.join(os.path.dirname(__file__), "meteorrajok.json")
FONT_BOLD   = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_REG    = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

COLORS = {            # 7-színű paletta
    "black": 0,       # fekete
    "white": 1,
    "green": 2,
    "blue": 3,
    "red": 4,
    "yellow": 5,
    "orange": 6,
}

# --- Segédfüggvények -----------------------------------------------
def get_nameday(today):
    with open(NAMEFILE, encoding="utf8") as f:
        data = json.load(f)
    return ", ".join(data.get(today.strftime("%m-%d"), []))

def get_special_day(today):
    # Példa: március 15., augusztus 20., október 23. stb.
    specials = {
        "03-15": "Nemzeti ünnep",
        "08-20": "Államalapítás",
        "10-23": "’56-os forradalom",
    }
    return specials.get(today.strftime("%m-%d"))

def get_meteor_shower(today):
    with open(METEORFILE, encoding="utf8") as f:
        showers = json.load(f)
    for item in showers:
        start = dt.datetime.strptime(f"{today.year}-{item['start']}", "%Y-%m-%d").date()
        end   = dt.datetime.strptime(f"{today.year}-{item['end']}", "%Y-%m-%d").date()
        if start <= today <= end:
            return item["name"]
    return None

def moon_phase_text(phase):
    names = ["Újhold", "Első negyed", "Telihold", "Utolsó negyed"]
    index = int((phase + 3.75) // 7.4) % 4
    return names[index]

# --- Fő logika ------------------------------------------------------
def main():
    today   = dt.datetime.now(T_ZONE).date()
    now_dt  = dt.datetime.now(T_ZONE)

    hu_holidays = holidays.country_holidays("HU", years=today.year)  # :contentReference[oaicite:2]{index=2}
    is_holiday  = today in hu_holidays
    holiday_nm  = hu_holidays.get(today) if is_holiday else None

    sunrise_sunset = sun(LocationInfo(latitude=LAT, longitude=LON), date=today, tzinfo=T_ZONE)  # :contentReference[oaicite:3]{index=3}
    moonrise = moon_rise(LocationInfo(latitude=LAT, longitude=LON), date=today, tzinfo=T_ZONE)
    moonset  = moon_set(LocationInfo(latitude=LAT, longitude=LON), date=today, tzinfo=T_ZONE)
    m_phase  = moon_phase(today)  # 0–29
    m_pct    = int(100 * m_phase / 29.53)

    meteor   = get_meteor_shower(today)
    nameday  = get_nameday(today)
    special  = get_special_day(today)

    # --- Kép felépítése --------------------------------------------
    img  = Image.new("P", (640, 400), COLORS["white"])
    draw = ImageDraw.Draw(img)
    font_h = ImageFont.truetype(FONT_BOLD, 60)
    font_m = ImageFont.truetype(FONT_BOLD, 28)
    font_s = ImageFont.truetype(FONT_REG, 20)

    # Dátum
    date_color = COLORS["red"] if is_holiday else COLORS["black"]
    draw.text((10, 10), today.strftime("%Y. %m. %d. %a"), font=font_h, fill=date_color)

    y = 90
    if holiday_nm:
        draw.text((10, y), holiday_nm, font=font_m, fill=COLORS["red"]);  y += 35
    if special:
        draw.text((10, y), f"Jeles nap: {special}", font=font_m, fill=COLORS["blue"]); y += 35
    draw.text((10, y), f"Névnap: {nameday}", font=font_m, fill=COLORS["green"]);    y += 35

    draw.text((10, y), f"Napkelte:  {sunrise_sunset['sunrise'].time():%H:%M}", font=font_s, fill=COLORS["black"]); y += 22
    draw.text((10, y), f"Napnyugta: {sunrise_sunset['sunset'].time():%H:%M}",  font=font_s, fill=COLORS["black"]); y += 22
    draw.text((10, y), f"Holdkelte: {moonrise.time() if moonrise else '--:--'}", font=font_s, fill=COLORS["black"]); y += 22
    draw.text((10, y), f"Holdnyugta: {moonset.time()  if moonset  else '--:--'}", font=font_s, fill=COLORS["black"]); y += 22
    draw.text((10, y), f"Holdfázis: {m_pct}% – {moon_phase_text(m_phase)}", font=font_s, fill=COLORS["black"]); y += 25
    if meteor:
        draw.text((10, y), f"Meteorraj: {meteor}", font=font_s, fill=COLORS["orange"]); y += 22

    # RSS hírek
    feed = feedparser.parse(RSS_URL)  # :contentReference[oaicite:4]{index=4}
    news_y = 350
    draw.rectangle((0, news_y-2, 639, 399), fill=COLORS["yellow"])
    for i, entry in enumerate(feed.entries[:3]):
        title = textwrap.shorten(entry.title, 70)
        draw.text((4, news_y + i*16), f"• {title}", font=font_s, fill=COLORS["black"])

    # --- Kijelző frissítés -----------------------------------------
    epd.init()
    epd.display(epd.getbuffer(img))
    epd.sleep()

if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(2)
PY
chmod +x "$APP_DIR/calendar_display.py"

# --- Névnap- és meteor-adatfájlok ----------------------------------
cat > "$APP_DIR/nevnapok.json" << 'NAMES'
{
  "01-01": ["Fruzsina", "Alpár"],
  "01-02": ["Ábel"],
  "01-03": ["Genovéva", "Benjámin"],
  "03-15": ["Kristóf", "Kristina"],
  "08-20": ["István"],
  "12-24": ["Ádám", "Éva"]
  /* … folytasd igény szerint … */
}
NAMES

cat > "$APP_DIR/meteorrajok.json" << 'METEORS'
[
  {"name": "Quadrantidák",       "start": "01-01", "end": "01-05"},
  {"name": "Perseidák",          "start": "08-10", "end": "08-14"},
  {"name": "Geminidák",          "start": "12-12", "end": "12-15"}
]
METEORS

# --- systemd szolgáltatás + timer ----------------------------------
cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Waveshare e-paper naptár megjelenítő
After=network.target

[Service]
Type=oneshot
User=$SUDO_USER
Environment="PYTHONUNBUFFERED=1"
ExecStart=$VENV_DIR/bin/python $APP_DIR/calendar_display.py
WorkingDirectory=$APP_DIR
EOF

cat > "/etc/systemd/system/${SERVICE_NAME}.timer" << EOF
[Unit]
Description=10 percenkénti frissítés a naptár kijelzőhöz

[Timer]
OnBootSec=30
OnUnitActiveSec=10min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now ${SERVICE_NAME}.timer

echo -e "\e[32m[SIKERES]\e[0m Telepítés befejezve – a kijelző 10 percenként frissül."
