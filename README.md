# 06 — Dashboard web IoT (Flask)

Interface web locale pour visualiser la télémétrie MQTT et piloter l'ESP32 (LED, relais, PWM).

```
ESP32 ──MQTT──► Mosquitto ◄──MQTT── Flask (SSE + REST)
                                      │
                                      └── navigateur http://127.0.0.1:5050
```

## Prérequis

- Python 3.10+
- Broker Mosquitto (`05-iot-mqtt/mosquitto`)
- ESP32 flashé avec `05-iot-mqtt/esp32-mqtt-sensors` (optionnel pour tests)

## Installation

```bash
pip install -r requirements.txt
```

## Lancement

```bash
# Terminal 1 — broker
cd ../05-iot-mqtt/mosquitto && docker compose up -d

# Terminal 2 — dashboard
python app.py --broker localhost --web-port 5050
```

Ouvrir **http://127.0.0.1:5050**

## API

| Route | Méthode | Description |
|-------|---------|-------------|
| `/api/state` | GET | État courant (MQTT, capteurs, historique) |
| `/api/command` | POST | `{"command":"LED_ON"}` |
| `/api/stream` | GET (SSE) | Flux temps réel |

## Topics (identiques à `05-iot-mqtt`)

- `eljezi/esp32/telemetry`
- `eljezi/esp32/command`
- `eljezi/esp32/status`

## Lien avec les autres projets

- Complète le moniteur CLI `mqtt-monitor`
- Même protocole que BLE / Flutter (`LED_ON`, `T=…,H=…,V=…`)
- Déployable sur Raspberry Pi (Niveau 3 roadmap)
