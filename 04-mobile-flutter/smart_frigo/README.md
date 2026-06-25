# smart_frigo — App mobile Smart Réfrigérateur

Application Flutter pour surveiller et piloter **11-smart-frigo** via MQTT.

## Connexion

1. Mosquitto : `05-iot-mqtt/mosquitto`
2. ESP32 : `11-smart-frigo/esp32-smart-frigo`
3. App → IP broker `192.168.1.100:1883`

Topics : `eljezi/frigo/*`

## Lancer

```bash
flutter pub get && flutter run
```

Voir [11-smart-frigo/README.md](../../11-smart-frigo/README.md).
