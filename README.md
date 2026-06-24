# El Jezi Ghassen — Embarquée

Espace de projets simples autour du **système embarqué** : RTOS, Linux, affichage data, mobile Flutter et **IoT MQTT**.

## Structure

| Dossier | Thème | Projet | Cible |
|---------|--------|--------|--------|
| `01-rtos/` | Temps réel | `esp32-freertos-blinky` | ESP32 + FreeRTOS + BLE |
| `02-linux-embarque/` | Linux embarqué | `gpio-sysfs` | Raspberry Pi (sysfs GPIO) |
| `03-affichage-data/` | Affichage data | `dashboard-capteurs` | PC Python |
| `04-mobile-flutter/` | Mobile IoT | `sensor_dashboard`, `ble_scanner`, `iot_remote` | Flutter |
| `05-iot-mqtt/` | IoT cloud local | `mosquitto`, `esp32-mqtt-sensors`, `mqtt-monitor` | WiFi + MQTT |
| `06-iot-web-dashboard/` | Dashboard web IoT | Flask + SSE + REST | PC / Raspberry Pi |

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

# IoT MQTT
cd 05-iot-mqtt/mosquitto && docker compose up -d
cd ../esp32-mqtt-sensors && pio run -t upload
cd ../mqtt-monitor && pip install -r requirements.txt && python monitor.py

# Dashboard web IoT
cd 06-iot-web-dashboard && pip install -r requirements.txt && python app.py

# Mobile Flutter
cd 04-mobile-flutter/sensor_dashboard && flutter run
```

## Auteur

**Ghassen El Jezi** — projets pédagogiques embarqué (RTOS, Linux, IoT, Flutter).
