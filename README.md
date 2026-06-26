# 18 — Smart Energy IoT

Gestion energie connectee Grand Tunis : solaire, reseau STEG, batteries, pics.

```
Simulateur / ESP32 ──MQTT──► Mosquitto
        │                         ├── energy-api (:5170) — IA optimisation
        │                         └── smart_energy (Flutter)
```

| Dossier | Role |
|---------|------|
| `data/sites.json` | 5 sites energie Grand Tunis |
| `energy-api/` | API FastAPI IA (port **5170**) |
| `../04-mobile-flutter/smart_energy/` | **App mobile Flutter** (4 onglets dont IA) |

## Topics MQTT

| Topic | Exemple |
|-------|---------|
| `eljezi/energy/telemetry` | `SITE=lac-solar,LOAD=185.0,SOLAR=142.0,GRID=43.0,BATT=78,COST=18.5,PEAK=0,T=31,H=45` |
| `eljezi/energy/command` | `STATUS`, `MODE_ECO`, `MODE_AUTO`, `BATT_CHARGE` |
| `eljezi/energy/status` | `SITE=lac-solar,ONLINE=1,MODE=AUTO,GRID=1` |
| `eljezi/energy/alert` | `SITE=medina-grid,ALERT=PEAK_HIGH` |

## Demarrage

```bash
cd 05-iot-mqtt/demo-publisher && python simulator.py
cd ../../18-smart-energy/energy-api && pip install -r requirements.txt && uvicorn main:app --host 0.0.0.0 --port 5170
cd ../../04-mobile-flutter/smart_energy && flutter pub get && flutter run
```
