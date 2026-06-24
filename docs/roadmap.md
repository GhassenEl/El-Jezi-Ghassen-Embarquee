# Feuille de route

## Niveau 1 (actuel)

- [x] RTOS — 2 tâches FreeRTOS (LED + capteur simulé)
- [x] Linux — export GPIO via sysfs
- [x] Affichage — courbes temps réel (simulation ou série)

## Niveau 1b — Mobile Flutter (actuel)

- [x] `sensor_dashboard` — graphiques capteurs **BLE live ESP32**
- [x] `ble_scanner` — scan périphériques BLE (ESP32, capteurs)
- [x] `iot_remote` — télécommande LED / relais / PWM **BLE réel ESP32**

## Niveau 2 — IoT MQTT (actuel)

- [x] Broker Mosquitto local (Docker)
- [x] ESP32 WiFi — publish telemetry + subscribe commandes
- [x] Moniteur Python avec alertes seuil

## Niveau 2c — Dashboard web IoT (actuel)

- [x] Flask — télémétrie temps réel (SSE)
- [x] Contrôles LED / relais / PWM via MQTT
- [x] Courbe température + alertes seuil

## Niveau 2b (à venir)

- [ ] RTOS — file de messages entre tâches (queue)
- [ ] Linux — driver character device minimal
- [ ] Affichage — écran OLED SSD1306 (I2C) sur ESP32

## Niveau 3

- [ ] Intégration complète : capteur → RTOS → Linux → dashboard
- [ ] OTA firmware ESP32
- [x] Interface web locale (Flask) sur PC / Raspberry Pi — voir `06-iot-web-dashboard`
