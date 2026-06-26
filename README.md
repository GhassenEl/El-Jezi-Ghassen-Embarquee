# 10 — Smart Meteo (station meteo IoT)

Station meteo connectee : temperature, humidite, pression, vent, pluie, UV — ESP32, dashboard web, moniteur et app mobile.

```
ESP32 Smart Meteo ──MQTT──► Mosquitto (05-iot-mqtt)
        │                         │
        │                         ├── meteo-dashboard (:5080)
        │                         ├── meteo-monitor (CLI)
        │                         └── smart_meteo (Flutter)
```

## Composants

| Dossier | Role |
|---------|------|
| `esp32-smart-meteo/` | Station ESP32 WiFi + capteurs simules |
| `meteo-dashboard/` | Dashboard Flask temps reel (port **5080**) |
| `meteo-monitor/` | Moniteur Python + alertes meteo |
| `../04-mobile-flutter/smart_meteo/` | **App mobile Flutter** |

## Topics MQTT

| Topic | Direction | Exemple |
|-------|-----------|---------|
| `eljezi/meteo/telemetry` | ESP32 -> broker | `STATION=jardin,T=24.0,H=62.0,P=1013.2,W=15.0,R=0.45,UV=5` |
| `eljezi/meteo/command` | broker -> ESP32 | `STATUS`, `RESET_RAIN`, `MODE_AUTO` |
| `eljezi/meteo/status` | ESP32 -> broker | `STATION=jardin,ONLINE=1,MODE=AUTO` |
| `eljezi/meteo/alert` | ESP32 -> broker | `STATION=jardin,ALERT=WIND_HIGH,W=42.0` |

## Commandes

| Commande | Action |
|----------|--------|
| `STATUS` | Force publication telemetrie + status |
| `RESET_RAIN` | Remise a zero pluviometre |
| `MODE_AUTO` / `MODE_MANUAL` | Simulation pluie auto ou manuelle |

## Alertes automatiques

| Alerte | Condition |
|--------|-----------|
| `WIND_HIGH` | Vent > 40 km/h |
| `RAIN_HEAVY` | Pluie cumulee > 5 mm |
| `HEAT_WAVE` | Temperature > 35 °C |
| `UV_HIGH` | Indice UV >= 8 |

## App mobile

Projet Flutter dédié : **`04-mobile-flutter/smart_meteo`**

| Écran | Données MQTT |
|-------|----------------|
| Température / HR | `eljezi/meteo/telemetry` |
| Vent / pluie / UV | `eljezi/meteo/telemetry` |
| Alertes | `eljezi/meteo/alert` |
| Contrôles | `eljezi/meteo/command` |

```bash
cd ../../04-mobile-flutter/smart_meteo
flutter pub get && flutter run
# → IP broker = PC Mosquitto (même réseau WiFi que le téléphone)
```

## Demarrage

```bash
# 1. Broker
cd ../05-iot-mqtt/mosquitto && docker compose up -d

# 2. ESP32
cd ../../10-smart-meteo/esp32-smart-meteo/include
copy secrets.h.example secrets.h   # Windows
cd .. && pio run -t upload

# 3. Dashboard
cd ../meteo-dashboard && pip install -r requirements.txt
python app.py --broker localhost --web-port 5080

# 4. Moniteur
cd ../meteo-monitor && pip install -r requirements.txt
python monitor.py --broker localhost

# 5. Mobile
cd ../../04-mobile-flutter/smart_meteo
flutter pub get && flutter run
```

Ouvrir **http://127.0.0.1:5080**

## FreeRTOS

| Tache | Role |
|-------|------|
| `task_sensor` | Simulation capteurs -> `telemetryQueue` |
| `task_alerts` | Detection seuils -> `alertQueue` |
| `task_actuator` | Commandes MQTT |
| `task_comms` | Publish MQTT |
| `task_mqtt` | Boucle broker |

## Branche GitHub

```bash
git clone -b project/10-smart-meteo --single-branch \
  https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git
```
