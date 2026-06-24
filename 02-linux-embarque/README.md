# 02 — Linux embarqué

## Projet : `gpio-sysfs`

Programme C minimal qui contrôle une GPIO via **sysfs** (interface classique sur Raspberry Pi et boards Linux).

### Matériel

- Raspberry Pi (ou autre SBC Linux avec GPIO sysfs)
- LED + résistance sur la broche choisie (défaut : **GPIO 17** = broche 11)

### Compilation sur la cible

```bash
cd gpio-sysfs
make
sudo ./build/gpio-blink 17
```

### Arguments

```text
./gpio-blink <numero_gpio>   # ex. 17
```

### Notes

- Sur les kernels récents, sysfs GPIO est déprécié au profit de **libgpiod** (`gpioset`). Ce projet reste pédagogique pour comprendre l'export `/sys/class/gpio`.
- Nécessite les droits root ou groupe `gpio`.
