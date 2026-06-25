# Feuille de route

## Niveau 1 (actuel)

- [x] RTOS — 2 tâches FreeRTOS (LED + capteur simulé)
- [x] Linux — export GPIO via sysfs
- [x] Affichage — courbes temps réel (simulation ou série)

## Niveau 1b — Mobile Flutter (actuel)

- [x] `sensor_dashboard` — graphiques capteurs **BLE live ESP32**
- [x] `ble_scanner` — scan périphériques BLE (ESP32, capteurs)
- [x] `iot_remote` — télécommande LED / relais / PWM **BLE réel ESP32**
- [x] `mqtt_remote` — télécommande **MQTT WiFi** via Mosquitto

## Niveau 2 — IoT MQTT (actuel)

- [x] Broker Mosquitto local (Docker)
- [x] ESP32 WiFi — publish telemetry + subscribe commandes
- [x] Moniteur Python avec alertes seuil

## Niveau 2c — Dashboard web IoT (actuel)

- [x] Flask — télémétrie temps réel (SSE)
- [x] Contrôles LED / relais / PWM via MQTT
- [x] Courbe température + alertes seuil

## Niveau 2b — Affichage OLED (actuel)

- [x] Écran OLED SSD1306 (I2C) sur ESP32 — capteurs + GPIO
- [x] RTOS — files de messages entre tâches (`xQueueCreate`)
- [ ] Linux — driver character device minimal

## Niveau 2d — Firmware unifié (actuel)

- [x] `08-esp32-unified` — BLE + MQTT + OLED sur un seul ESP32
- [x] Branches GitHub `project/*` — un projet par branche

## Niveau 4 — Smart Farm (actuel)

- [x] ESP32 — capteurs sol / air / lumière (simulation)
- [x] Irrigation AUTO/MANUAL + alertes MQTT
- [x] Dashboard web ferme (Flask SSE)
- [x] Moniteur CLI alertes sol sec
- [x] App mobile Flutter `smart_farm`
- [x] Couche cloud — Mosquitto cloud + API REST + historique SQLite

## Niveau 3

- [x] Intégration firmware : BLE + MQTT + OLED (`08-esp32-unified`)
- [ ] Intégration chaîne complète : capteur → RTOS → Linux → dashboard
- [ ] OTA firmware ESP32
- [x] Interface web locale (Flask) sur PC / Raspberry Pi — voir `06-iot-web-dashboard`
