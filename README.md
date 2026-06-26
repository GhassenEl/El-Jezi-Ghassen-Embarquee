# 14 — Smart City (ville connectee)

Plateforme IoT urbaine : qualite de l'air, trafic, parking, eclairage public, bruit et energie — ESP32 gateway, dashboard web et moniteur MQTT.

```
ESP32 Smart City ──MQTT──► Mosquitto (05-iot-mqtt)
        │                         │
        │                         ├── city-dashboard (:8110)
        │                         └── city-monitor (CLI)
```

## Composants

| Dossier | Role |
|---------|------|
| `esp32-smart-city/` | Passerelle ESP32 + capteurs urbains simules |
| `city-dashboard/` | Dashboard Flask temps reel (port **8110**) |
| `city-monitor/` | Moniteur Python + alertes ville |

## Topics MQTT

| Topic | Exemple payload |
|-------|-----------------|
| `eljezi/city/telemetry` | `ZONE=medina,AQI=68,PM25=22,...,ENERGY=1200,BUS=5,WIFI=90,CROWD=3` |
| `eljezi/city/command` | `STATUS`, `LIGHT_ECO`, `MODE_EVENT`, `TRAFFIC_SYNC` |
| `eljezi/city/status` | `ZONE=centre-ville,ONLINE=1,MODE=NORMAL,ALERT_LVL=0,SERVICES=4` |
| `eljezi/city/alert` | `ZONE=centre-ville,ALERT=TRAFFIC_JAM` |

## Metriques

| Champ | Description |
|-------|-------------|
| `AQI` | Indice qualite de l'air (0–500) |
| `PM25` | Particules fines µg/m³ |
| `CO2` | Dioxyde de carbone ppm |
| `NOISE` | Niveau sonore dB |
| `TRAFFIC` | 1=fluide … 4=bloque |
| `PARK` | Places parking disponibles |
| `LIGHT` | Eclairage public actif |
| `ENERGY` | Consommation zone (W) |
| `BUS` | Retard bus moyen (min) |
| `WIFI` | Utilisateurs WiFi public |
| `CROWD` | Densite foule (1–5) |

**5 zones** : centre-ville, medina, lac, ariana, carthage — profils dans `data/zones_profile.json`.

## Commandes

| Commande | Action |
|----------|--------|
| `STATUS` | Publication telemetrie + status |
| `LIGHT_ON` / `LIGHT_ECO` / `LIGHT_OFF` | Eclairage public |
| `MODE_NORMAL` / `MODE_EVENT` / `MODE_ALERT` | Profil ville |
| `TRAFFIC_SYNC` | Synchronisation feux trafic |
| `ALARM_OFF` / `ALARM_ON` | Alertes citoyennes |

## Alertes

| Alerte | Condition |
|--------|-----------|
| `AIR_QUALITY_BAD` | AQI > 100 |
| `TRAFFIC_JAM` | Trafic niveau 4 |
| `NOISE_HIGH` | Bruit > 75 dB |
| `PARKING_FULL` | Places < 5 |

## Demarrage

```bash
cd ../05-iot-mqtt/mosquitto && docker compose up -d
cd ../demo-publisher && python simulator.py
cd ../../14-smart-city/city-dashboard && pip install -r requirements.txt && python app.py --web-port 8110
```

**Dashboard :** http://127.0.0.1:8110

## Branche GitHub

```bash
git clone -b project/14-smart-city --single-branch \
  https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git
```
