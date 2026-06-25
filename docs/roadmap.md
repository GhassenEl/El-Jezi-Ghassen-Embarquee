# Feuille de route

## Niveau 1 (actuel)

- [x] RTOS — 2 tâches FreeRTOS (LED + capteur simulé)
- [x] Linux — export GPIO via sysfs
- [x] Linux — libgpiod + driver character device minimal
- [x] Linux — passerelle MQTT Raspberry Pi (`pi-mqtt-gateway`)
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
- [ ] Linux — driver character device avec GPIO materiel reel

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
- [x] **IA ferme** — prédiction sol, score santé, irrigation assistée (`farm-ai` + cloud-api)
- [x] Panneau IA dans l'app mobile `smart_farm`

## Niveau 5 — Smart Meteo (actuel)

- [x] ESP32 — station meteo simulee (T, HR, P, vent, pluie, UV)
- [x] Alertes MQTT vent / pluie / chaleur / UV
- [x] Dashboard web Flask SSE (port 5080)
- [x] Moniteur CLI meteo
- [x] App mobile Flutter `smart_meteo`

## Niveau 6 — Smart Frigo (actuel)

- [x] ESP32 — frigo/congelateur, porte, compresseur, consommation
- [x] Alertes porte ouverte, temperature, surconsommation
- [x] Dashboard web Flask SSE (port 5090)
- [x] Moniteur CLI frigo
- [x] App mobile Flutter `smart_frigo`

## Niveau 8 — Smart Home (actuel)

- [x] ESP32 salon : temperature, lux, mouvement, porte
- [x] Eclairage, chauffage, modes HOME/AWAY/SLEEP
- [x] Dashboard Flask port 8100 + alertes securite
- [x] Simulateur MQTT integre

## Niveau 7 — SQL Films

- [x] Schema relationnel films / acteurs / realisateurs / genres
- [x] Donnees seed + requetes JOIN / GROUP BY / HAVING
- [x] Base SQLite + scripts Python
- [x] Catalogue web Flask (port 8070)

## Niveau 3

- [x] Intégration firmware : BLE + MQTT + OLED (`08-esp32-unified`)
- [ ] Intégration chaîne complète : capteur → RTOS → Linux → dashboard
- [ ] OTA firmware ESP32
- [x] Interface web locale (Flask) sur PC / Raspberry Pi — voir `06-iot-web-dashboard`
