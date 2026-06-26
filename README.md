# 07 — OLED SSD1306 (I2C)

Affichage local des capteurs simulés sur écran **128×64** branché en I2C sur ESP32.

```
Capteurs simulés ──FreeRTOS──► OLED SSD1306
                    │
                    └── série USB (commandes LED/RELAY/PWM)
```

## Câblage

| OLED | ESP32 |
|------|-------|
| SDA | GPIO **21** |
| SCL | GPIO **22** |
| VCC | **3.3 V** |
| GND | GND |

Adresse I2C par défaut : **0x3C**

## Flash

```bash
cd esp32-oled-sensors
pio run -t upload
pio device monitor
```

## Commandes série (115200 baud)

Même protocole que BLE / MQTT :

| Commande | Action |
|----------|--------|
| `LED_ON` / `LED_OFF` | GPIO 2 |
| `RELAY_ON` / `RELAY_OFF` | GPIO 4 |
| `PWM_0` … `PWM_255` | GPIO 5 |
| `STATUS` | `LED=1,RELAY=0,PWM=128` |

Télémétrie série : `T=24.5,H=55.0,V=3.30` (toutes les 2 s)

## Tâches FreeRTOS

| Tâche | Rôle | Période |
|-------|------|---------|
| `task_sensor` | Lit capteurs simulés | 2 s |
| `task_display` | Rafraîchit l'écran | 500 ms |
| `task_serial` | Commandes USB | 50 ms |

## Lien avec les autres projets

- Format `T/H/V` identique à `01-rtos`, `05-iot-mqtt`, Flutter
- Peut être combiné plus tard avec BLE ou MQTT sur le même ESP32
