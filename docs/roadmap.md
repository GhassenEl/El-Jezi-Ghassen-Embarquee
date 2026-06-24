# Feuille de route

## Niveau 1 (actuel)

- [x] RTOS — 2 tâches FreeRTOS (LED + capteur simulé)
- [x] Linux — export GPIO via sysfs
- [x] Affichage — courbes temps réel (simulation ou série)

## Niveau 1b — Mobile Flutter (actuel)

- [x] `sensor_dashboard` — KPI + graphiques capteurs (fl_chart)
- [x] `ble_scanner` — scan périphériques BLE (ESP32, capteurs)
- [x] `iot_remote` — télécommande LED / relais / PWM **BLE réel ESP32**

## Niveau 2 (à venir)

- [ ] RTOS — file de messages entre tâches (queue)
- [ ] Linux — driver character device minimal
- [ ] Affichage — écran OLED SSD1306 (I2C) sur ESP32

## Niveau 3

- [ ] Intégration complète : capteur → RTOS → Linux → dashboard
- [ ] OTA firmware ESP32
- [ ] Interface web locale (Flask) sur Raspberry Pi
