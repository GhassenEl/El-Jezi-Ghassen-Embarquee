# 08 — ESP32 unifié (BLE + MQTT + OLED)

Un **seul firmware** qui combine les trois stacks embarquées du dépôt.

```
                    ┌─────────────┐
  Flutter BLE ─────►│             │
  Flutter MQTT ────►│   ESP32     │────► OLED SSD1306 (I2C)
  Dashboard web ───►│  Unified    │
  Moniteur Python ─►│             │────► GPIO LED / Relais / PWM
                    └─────────────┘
```

## Fonctionnalités

| Canal | Protocole | Usage |
|-------|-----------|--------|
| **BLE** | `ElJezi-ESP32` + UUIDs El Jezi | `iot_remote`, `sensor_dashboard` |
| **MQTT** | `eljezi/esp32/*` | `mqtt_remote`, dashboard Flask, `monitor.py` |
| **OLED** | I2C 128×64 | Affichage local T/H/V + états connexion |
| **Série** | USB 115200 | Debug + commandes manuelles |

## Câblage

| Composant | Brochage |
|-----------|----------|
| OLED SDA | GPIO **21** |
| OLED SCL | GPIO **22** |
| LED | GPIO **2** |
| Relais | GPIO **4** |
| PWM | GPIO **5** |

## Configuration

```bash
cd esp32-all-in-one/include
copy secrets.h.example secrets.h
# WIFI_SSID, WIFI_PASS, MQTT_BROKER
pio run -t upload
pio device monitor
```

> Sans WiFi valide, **BLE et OLED restent actifs** ; MQTT est désactivé.

## Tâches FreeRTOS + queues

```
BLE / MQTT / USB ──► cmdQueue ──► task_actuator ──► GPIO
task_sensor ──► telemetryQueue ──► task_comms ──► BLE notify + MQTT
task_display ◄── état partagé (mutex)
task_mqtt ──► boucle broker
```

| Tâche | Rôle | Queue |
|-------|------|-------|
| `task_sensor` | Capteurs simulés (producteur) | → `telemetryQueue` |
| `task_actuator` | Commandes GPIO (consommateur) | ← `cmdQueue` |
| `task_comms` | Publication BLE/MQTT (consommateur) | ← `telemetryQueue` |
| `task_mqtt` | Reconnexion + `mqtt.loop()` | — |
| `task_display` | OLED + profondeur queues `Q` | — |
| `task_serial` | Saisie USB (producteur) | → `cmdQueue` |

| File | Taille | Contenu |
|------|--------|---------|
| `cmdQueue` | 8 | `LED_ON`, `PWM_128`, `STATUS`… |
| `telemetryQueue` | 6 | `T/H/V` |

## Branche GitHub dédiée

```bash
git clone -b project/08-esp32-unified --single-branch https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git
```

Voir [docs/BRANCHES.md](../docs/BRANCHES.md) pour toutes les branches projet.
