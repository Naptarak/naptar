# E-Paper Calendar Display for Raspberry Pi Zero 2W

Ez a projekt egy teljes naptár megjelenítő rendszert hoz létre Raspberry Pi Zero 2W számára, Waveshare 4.01 inch HAT (F) 7-színű e-paper kijelzővel.

## Funkciók

A naptár az alábbi információkat jeleníti meg:
- Aktuális dátum (pirossal jelölve, ha ünnepnap)
- Magyar ünnepnapok (beleértve a mozgó ünnepeket is)
- Magyar névnapok
- Jeles napok
- Napkelte és napnyugta időpontok
- Holdkelte és holdnyugta időpontok
- A hold fázisa (százalékban és szövegesen)
- Aktuális meteorrajok adatai
- Telex.hu RSS hírcsatorna első 3 híre

## Rendszerkövetelmények

- Raspberry Pi Zero 2W (512 MB RAM)
- Waveshare 4.01 inch HAT (F) 7-színű e-paper kijelző (640x400 pixel)
- Raspberry Pi OS Desktop (32-bit)
- Internet kapcsolat a hírek és egyéb adatok frissítéséhez

## Telepítés

1. Csatlakoztassa a Waveshare e-paper HAT-et a Raspberry Pi-hez
2. Töltse le ezt a repository-t a Raspberry Pi-re
3. Futtassa a telepítő scriptet:

```bash
sudo chmod +x install.sh
sudo ./install.sh
```

A telepítő script:
- Telepíti a szükséges rendszerfüggőségeket
- Beállítja az SPI interfészt
- Letölti és telepíti a Waveshare e-paper könyvtárat
- Létrehoz egy Python virtuális környezetet
- Telepíti a szükséges Python csomagokat
- Beállít egy systemd szolgáltatást, hogy a program automatikusan induljon rendszerindításkor

## Eltávolítás

Ha el szeretné távolítani a programot, használja az uninstall.sh scriptet:

```bash
sudo chmod +x uninstall.sh
sudo ./uninstall.sh
```

## Hibaelhárítás

### SPI Interfész problémák

Ha problémák vannak az SPI interfész engedélyezésével:

1. Manuálisan engedélyezze a raspi-config segítségével:
   ```
   sudo raspi-config
   ```
   Majd navigáljon: Interfacing Options > SPI > Yes

2. Vagy szerkessze közvetlenül a /boot/config.txt fájlt:
   ```
   sudo nano /boot/config.txt
   ```
   És adja hozzá a következő sort: `dtparam=spi=on`

### Python csomagok telepítési problémái

Ha problémák merülnek fel a Python csomagok telepítésekor:

1. Próbálja manuálisan telepíteni a csomagokat:
   ```
   pip3 install feedparser astral ephem requests pillow RPi.GPIO spidev
   ```

2. Ha a virtuális környezettel van probléma, próbálja meg a rendszer Python-ját használni:
   ```
   sudo apt-get install python3-feedparser python3-pil python3-numpy python3-requests
   ```

### Waveshare könyvtár problémák

Ha a Waveshare könyvtár nem töltődik be megfelelően:

1. Manuálisan töltse le és telepítse:
   ```
   git clone https://github.com/waveshare/e-Paper.git
   ```

2. Majd másolja át a megfelelő könyvtárat:
   ```
   cp -r e-Paper/RaspberryPi_JetsonNano/python/lib/waveshare_epd /home/pi/e-paper-calendar/lib/
   ```

## Testreszabás

A konfigurációs fájl (`config.json`) lehetővé teszi, hogy testre szabja a működést:

- `location`: földrajzi helyzet a csillagászati számításokhoz
- `refresh_interval`: a kijelző frissítésének gyakorisága másodpercben
- `rss_feed_url`: az RSS feed URL-je
- `max_news_items`: a megjelenítendő hírek száma
- `font_sizes`: betűméretek a különböző elemekhez

## Licenc

Ez a projekt szabadon felhasználható, módosítható és terjeszthető.
