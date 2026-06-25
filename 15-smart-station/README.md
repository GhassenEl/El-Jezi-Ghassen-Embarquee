# 15 — Smart Station (transport public)

Station connectee pour **moyens de transport publics** : metro, bus, TGM — horaires temps reel, affluence et alertes via MQTT + **app mobile Flutter**.

```
Simulateur / ESP32 ──MQTT──► Mosquitto (05-iot-mqtt)
        │                         │
        │                         └── smart_station (Flutter)
```

## Composants

| Dossier | Role |
|---------|------|
| `data/stations.json` | Lignes et stations Grand Tunis |
| `station-monitor/` | Moniteur MQTT CLI |
| `../04-mobile-flutter/smart_station/` | **App mobile Flutter** |

## Topics MQTT

| Topic | Exemple payload |
|-------|-----------------|
| `eljezi/station/telemetry` | `STATION=metro-lac,LINE=M4,VEHICLE=METRO,DIR=Ariana,ETA=4,OCC=65,VALIDATORS=3,T=25,H=50,CROWD=2` |
| `eljezi/station/command` | `STATUS`, `REFRESH_ETA`, `MODE_NORMAL` |
| `eljezi/station/status` | `STATION=metro-lac,ONLINE=1,MODE=NORMAL,LINES=4,SERVICES=6` |
| `eljezi/station/alert` | `STATION=metro-lac,ALERT=DELAY_HIGH` |

## Metriques

| Champ | Description |
|-------|-------------|
| `LINE` | Identifiant ligne (M4, L5, TGM…) |
| `VEHICLE` | METRO, BUS, TRAIN, TRAM |
| `DIR` | Direction / terminus |
| `ETA` | Prochain passage (minutes) |
| `OCC` | Taux occupation % |
| `VALIDATORS` | Validateurs actifs |
| `CROWD` | Densite quai (1–5) |

## 5 stations

metro-lac · metro-republique · bus-bab-bhar · tgm-carthage · metro-ariana

## Demarrage

```bash
# 1. Broker MQTT
cd ../05-iot-mqtt/mosquitto && docker compose up -d

# 2. Simulateur (inclut stations)
cd ../demo-publisher && python simulator.py

# 3. App mobile
cd ../../04-mobile-flutter/smart_station
flutter pub get
flutter run
```

**Moniteur :** `python station-monitor/monitor.py`

## Branche GitHub

```bash
git clone -b project/15-smart-station --single-branch \
  https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git
```
