# 13 — Smart Home (maison connectee)

Domotique IoT : temperature, luminosite, mouvement, porte, eclairage, chauffage et securite — ESP32, dashboard web et moniteur MQTT.

```
ESP32 Smart Home ──MQTT──► Mosquitto (05-iot-mqtt)
        │                         │
        │                         ├── home-dashboard (:8100)
        │                         └── home-monitor (CLI)
```

## Composants

| Dossier | Role |
|---------|------|
| `esp32-smart-home/` | Module ESP32 WiFi + capteurs simules |
| `home-dashboard/` | Dashboard Flask temps reel (port **8100**) |
| `home-monitor/` | Moniteur Python + alertes securite |

## Topics MQTT

| Topic | Exemple payload |
|-------|-----------------|
| `eljezi/home/telemetry` | `ZONE=salon,T=22.5,H=48,LUX=420,MOTION=1,DOOR=0,LIGHT=1,HEAT=0,PWR=380` |
| `eljezi/home/command` | `STATUS`, `LIGHT_ON`, `MODE_AWAY`, `LOCK_ON` |
| `eljezi/home/status` | `ZONE=salon,ONLINE=1,MODE=HOME,TARGET_T=22,ALARM=1,LOCK=1` |
| `eljezi/home/alert` | `ZONE=salon,ALERT=MOTION_AWAY` |

## Commandes

| Commande | Action |
|----------|--------|
| `STATUS` | Publication telemetrie + status |
| `LIGHT_ON` / `LIGHT_OFF` | Eclairage salon |
| `HEAT_ON` / `HEAT_OFF` | Chauffage |
| `MODE_HOME` / `MODE_AWAY` / `MODE_SLEEP` | Profil domotique |
| `LOCK_ON` / `LOCK_OFF` | Verrouillage porte |
| `SET_TEMP_22` | Consigne temperature (°C) |
| `ALARM_OFF` / `ALARM_ON` | Couper / reactiver alarmes |

## Alertes

| Alerte | Condition |
|--------|-----------|
| `MOTION_AWAY` | Mouvement detecte en mode AWAY |
| `DOOR_OPEN` | Porte ouverte > 45 s |
| `INTRUSION` | Porte + mouvement en mode AWAY |
| `TEMP_HIGH` | Temperature > 30°C |

## Demarrage

```bash
cd ../05-iot-mqtt/mosquitto && docker compose up -d
cd ../../05-iot-mqtt/demo-publisher && python simulator.py
cd ../../13-smart-home/esp32-smart-home/include && copy secrets.h.example secrets.h
cd .. && pio run -t upload
cd ../home-dashboard && pip install -r requirements.txt && python app.py --web-port 8100
```

**Dashboard :** http://127.0.0.1:8100

## Branche GitHub

```bash
git clone -b project/13-smart-home --single-branch \
  https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git
```
