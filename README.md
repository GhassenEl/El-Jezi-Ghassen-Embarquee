# El Jezi Ghassen — Embarquée

Espace de projets simples autour du **système embarqué** : RTOS, Linux, affichage data, mobile Flutter et **IoT MQTT**.

## Structure

| Dossier | Thème | Projet | Cible |
|---------|--------|--------|--------|
| `01-rtos/` | Temps réel | `esp32-freertos-blinky` | ESP32 + FreeRTOS + BLE |
| `02-linux-embarque/` | Linux embarqué | `gpio-sysfs`, `gpio-libgpiod`, `eljezi-gpio-kmod`, `pi-mqtt-gateway` | Raspberry Pi |
| `03-affichage-data/` | Affichage data | `dashboard-capteurs` | PC Python |
| `04-mobile-flutter/` | Mobile IoT | `sensor_dashboard`, `ble_scanner`, `iot_remote`, `mqtt_remote`, `smart_farm`, `smart_meteo`, `smart_frigo` | Flutter |
| `05-iot-mqtt/` | IoT cloud local | `mosquitto`, `esp32-mqtt-sensors`, `mqtt-monitor` | WiFi + MQTT |
| `06-iot-web-dashboard/` | Dashboard web IoT | Flask + SSE + REST | PC / Raspberry Pi |
| `07-oled-ssd1306/` | Affichage embarqué | `esp32-oled-sensors` | ESP32 + OLED I2C |
| `08-esp32-unified/` | **Firmware unifié** | `esp32-all-in-one` | BLE + MQTT + OLED |
| `09-smart-farm/` | **Smart Farm** | `esp32-smart-farm`, `farm-dashboard` | Agriculture IoT |
| `10-smart-meteo/` | **Smart Meteo** | `esp32-smart-meteo`, `meteo-dashboard` | Station meteo IoT |
| `11-smart-frigo/` | **Smart Frigo** | `esp32-smart-frigo`, `frigo-dashboard` | Refrigerateur IoT |
| `12-sql-films/` | **SQL Films** | `sql/`, `films-web` | Base de donnees + catalogue |
| `13-smart-home/` | **Smart Home** | `esp32-smart-home`, `home-dashboard` | Domotique salon |
| `14-smart-city/` | **Smart City** | `esp32-smart-city`, `city-dashboard` | Ville connectee |
| `15-smart-station/` | **Smart Station** | `station-monitor`, `smart_station` | Transport public |

## Branches GitHub (un projet = une branche)

Chaque dossier est aussi publié sur une branche dédiée `project/*` pour cloner un seul projet :

```bash
git clone -b project/08-esp32-unified --single-branch \
  https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git
```

Voir [docs/BRANCHES.md](docs/BRANCHES.md).

## Prérequis globaux

- **RTOS / MQTT ESP32** : [PlatformIO](https://platformio.org/) + ESP32
- **Linux** : `gcc` sur Raspberry Pi
- **Affichage / MQTT monitor** : Python 3.10+
- **Flutter** : [Flutter SDK](https://docs.flutter.dev/get-started/install)
- **Broker MQTT** : [Docker](https://www.docker.com/) (optionnel)

## Démarrage rapide

```bash
# RTOS + BLE
cd 01-rtos/esp32-freertos-blinky && pio run -t upload

# Linux embarque (sur Raspberry Pi)
cd 02-linux-embarque/gpio-libgpiod && make && sudo ./build/gpio-blink 17
cd ../pi-mqtt-gateway && pip install -r requirements.txt && python gateway.py

# IoT MQTT
cd 05-iot-mqtt/mosquitto && docker compose up -d
cd ../esp32-mqtt-sensors && pio run -t upload
cd ../mqtt-monitor && pip install -r requirements.txt && python monitor.py

# Dashboard web IoT
cd 06-iot-web-dashboard && pip install -r requirements.txt && python app.py

# Mobile Flutter
cd 04-mobile-flutter/mqtt_remote && flutter run

# OLED SSD1306
cd 07-oled-ssd1306/esp32-oled-sensors && pio run -t upload

# Smart Farm
cd 05-iot-mqtt/mosquitto && docker compose up -d
cd ../../09-smart-farm/esp32-smart-farm && pio run -t upload
cd ../farm-dashboard && pip install -r requirements.txt && python app.py --web-port 8060

# Smart Meteo
cd 05-iot-mqtt/mosquitto && docker compose up -d
cd ../../10-smart-meteo/esp32-smart-meteo && pio run -t upload
cd ../meteo-dashboard && pip install -r requirements.txt && python app.py --web-port 5080

# Smart Frigo
cd 05-iot-mqtt/mosquitto && docker compose up -d
cd ../../11-smart-frigo/esp32-smart-frigo && pio run -t upload
cd ../frigo-dashboard && pip install -r requirements.txt && python app.py --web-port 5090

# SQL Films
cd 12-sql-films && python scripts/init_db.py --reset
cd films-web && pip install -r requirements.txt && python app.py --web-port 8070

# Smart Home
cd ../13-smart-home/home-dashboard && pip install -r requirements.txt && python app.py --web-port 8100

# Smart City
cd ../../14-smart-city/city-dashboard && pip install -r requirements.txt && python app.py --web-port 8110

# Smart Station (app mobile)
cd ../../04-mobile-flutter/smart_station && flutter pub get && flutter run
```

## Auteur

**Ghassen El Jezi** — projets pédagogiques embarqué (RTOS, Linux, IoT, Flutter).
