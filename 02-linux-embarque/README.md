# 02 — Linux embarqué

Projets **C / noyau / Python** pour Raspberry Pi et SBC Linux, intégrés à l'écosystème IoT El Jezi.

```
Capteurs / GPIO (Pi) ──► pi-mqtt-gateway ──MQTT──► Mosquitto (05-iot-mqtt)
                              │                         │
                              │                         ▼
                        gpio-libgpiod              06-iot-web-dashboard
                        eljezi-gpio-kmod           mqtt-monitor
```

## Composants

| Dossier | Rôle | Cible |
|---------|------|--------|
| `gpio-sysfs/` | LED via **sysfs** `/sys/class/gpio` (classique) | Raspberry Pi |
| `gpio-libgpiod/` | LED via **libgpiod** (API moderne) | Raspberry Pi OS |
| `eljezi-gpio-kmod/` | **Driver noyau** — `/dev/eljezi_gpio` | Raspberry Pi (headers kernel) |
| `pi-mqtt-gateway/` | Passerelle **MQTT** capteurs + GPIO | Pi / PC (simulation) |

## Topics MQTT (`pi-mqtt-gateway`)

| Topic | Direction | Exemple payload |
|-------|-----------|-----------------|
| `eljezi/rpi/telemetry` | Pi → broker | `T=24.0,H=55.0,GPIO=0,UP=120` |
| `eljezi/rpi/command` | broker → Pi | `LED_ON`, `LED_OFF`, `STATUS` |
| `eljezi/rpi/status` | Pi → broker | `GPIO=0,LINE=17,MODE=HW` |
| `eljezi/rpi/alert` | Pi → broker | `ZONE=rpi,ALERT=TEMP_HIGH,T=36.2` |

## Démarrage rapide

### 1. GPIO sysfs (pédagogique)

```bash
cd gpio-sysfs
make
sudo ./build/gpio-blink 17
```

### 2. GPIO libgpiod (recommandé)

```bash
sudo apt install -y libgpiod-dev gpiod
cd gpio-libgpiod
make
sudo ./build/gpio-blink 17
```

### 3. Driver noyau minimal

Sur la Raspberry Pi avec headers :

```bash
sudo apt install -y raspberrypi-kernel-headers build-essential
cd eljezi-gpio-kmod
make
sudo insmod eljezi_gpio.ko
ls -l /dev/eljezi_gpio

cd userspace && make
./build/test-eljezi-gpio
sudo rmmod eljezi_gpio
```

### 4. Passerelle MQTT

```bash
# Broker (depuis monorepo)
cd ../../05-iot-mqtt/mosquitto && docker compose up -d

cd ../../02-linux-embarque/pi-mqtt-gateway
pip install -r requirements.txt

# Sur PC (simulation)
python gateway.py --broker localhost --simulate

# Sur Pi (GPIO 17 + capteurs)
python gateway.py --broker localhost --gpio 17
```

### 5. Service systemd (optionnel)

```bash
sudo cp eljezi-rpi.service.example /etc/systemd/system/eljezi-rpi.service
sudo systemctl enable --now eljezi-rpi
```

## Matériel

| Élément | Brochage |
|---------|----------|
| LED + résistance | GPIO **17** (broche 11) |
| Relais irrigation | GPIO **17** ou **27** |
| DS18B20 (optionnel) | 1-Wire — détecté automatiquement |

## Chaîne complète IoT

```bash
# Terminal 1 — Mosquitto
cd 05-iot-mqtt/mosquitto && docker compose up -d

# Terminal 2 — Passerelle Pi
cd 02-linux-embarque/pi-mqtt-gateway && python gateway.py

# Terminal 3 — Moniteur ou dashboard
cd 05-iot-mqtt/mqtt-monitor && python monitor.py   # ESP32
cd 06-iot-web-dashboard && python app.py           # web SSE
```

## Branche GitHub

```bash
git clone -b project/02-linux-embarque --single-branch \
  https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git
```

## Notes

- **sysfs GPIO** est déprécié sur les kernels récents → préférer `gpio-libgpiod`.
- Le module `eljezi_gpio.ko` est **pédagogique** (état LED en RAM) ; une version matérielle utiliserait `gpiod` dans le noyau.
- `pi-mqtt-gateway` fonctionne en **simulation** sur Windows/macOS pour développer sans Pi.
