# 05 — IoT MQTT

Chaîne IoT complète **publish/subscribe** : capteurs ESP32 → broker MQTT → moniteur Python (+ alertes).

```
ESP32 (WiFi)  ──publish──►  Mosquitto  ──subscribe──►  mqtt-monitor (PC)
                ◄──command──               ◄──publish────  (LED_ON, STATUS…)
```

## Composants

| Dossier | Rôle |
|---------|------|
| `mosquitto/` | Broker MQTT local (Docker) |
| `esp32-mqtt-sensors/` | ESP32 publie T/H/V + reçoit commandes |
| `mqtt-monitor/` | Abonné Python, logs + alertes seuil |

## Topics El Jezi

| Topic | Direction | Payload exemple |
|-------|-----------|-----------------|
| `eljezi/esp32/telemetry` | ESP32 → broker | `T=24.5,H=55.0,V=3.30` |
| `eljezi/esp32/command` | broker → ESP32 | `LED_ON`, `LED_OFF`, `STATUS` |
| `eljezi/esp32/status` | ESP32 → broker | `LED=1,RELAY=0,PWM=128` |

## Démarrage rapide

### 1. Broker MQTT (PC)

```bash
cd mosquitto
docker compose up -d
# Broker : mqtt://localhost:1883
```

### 2. Configurer le WiFi ESP32

```bash
cd esp32-mqtt-sensors/include
copy secrets.h.example secrets.h
# Éditer WIFI_SSID, WIFI_PASS, MQTT_BROKER
pio run -t upload
```

### 3. Moniteur Python

```bash
cd mqtt-monitor
pip install -r requirements.txt
python monitor.py --broker localhost
```

## Lien avec les autres projets

- Même format capteurs que **BLE** (`01-rtos`, `04-mobile-flutter`)
- Peut remplacer ou compléter BLE pour portée WiFi / cloud
- Prochaine étape : bridge MQTT → dashboard Flutter ou Raspberry Pi
