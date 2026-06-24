#!/usr/bin/env python3
"""
El Jezi Ghassen Embarquée — Affichage data
Dashboard temps réel : température, humidité, tension.
"""
from __future__ import annotations

import argparse
import math
import random
import re
import sys
import time
from collections import deque

import matplotlib.pyplot as plt
import matplotlib.animation as animation

try:
    import serial
except ImportError:
    serial = None  # type: ignore

SAMPLE_RE = re.compile(
    r"T\s*=\s*(?P<t>[-\d.]+)\s*,\s*H\s*=\s*(?P<h>[-\d.]+)\s*,\s*V\s*=\s*(?P<v>[-\d.]+)",
    re.I,
)

WINDOW = 60
INTERVAL_MS = 500


class SimulatedSource:
    """Capteurs simulés (sans matériel)."""

    def __init__(self) -> None:
        self._t0 = time.time()

    def read(self) -> tuple[float, float, float]:
        t = time.time() - self._t0
        temp = 24.0 + 2.0 * math.sin(t / 8.0) + random.uniform(-0.2, 0.2)
        hum = 55.0 + 5.0 * math.cos(t / 10.0) + random.uniform(-0.5, 0.5)
        volt = 3.30 + 0.05 * math.sin(t / 5.0)
        return round(temp, 2), round(hum, 2), round(volt, 3)


class SerialSource:
    """Lecture UART — lignes T=...,H=...,V=..."""

    def __init__(self, port: str, baud: int = 115200) -> None:
        if serial is None:
            raise RuntimeError("Installez pyserial : pip install pyserial")
        self._ser = serial.Serial(port, baud, timeout=0.1)
        self._last = (24.0, 55.0, 3.3)

    def read(self) -> tuple[float, float, float]:
        line = self._ser.readline().decode(errors="ignore").strip()
        m = SAMPLE_RE.search(line)
        if m:
            self._last = (
                float(m.group("t")),
                float(m.group("h")),
                float(m.group("v")),
            )
        return self._last

    def close(self) -> None:
        self._ser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Dashboard capteurs El Jezi Ghassen")
    parser.add_argument("--port", help="Port série (ex. COM3, /dev/ttyUSB0)")
    parser.add_argument("--baud", type=int, default=115200)
    args = parser.parse_args()

    if args.port:
        source = SerialSource(args.port, args.baud)
        title = f"Embarquée — série {args.port}"
    else:
        source = SimulatedSource()
        title = "Embarquée — simulation capteurs"

    times: deque[float] = deque(maxlen=WINDOW)
    temps: deque[float] = deque(maxlen=WINDOW)
    hums: deque[float] = deque(maxlen=WINDOW)
    volts: deque[float] = deque(maxlen=WINDOW)
    t0 = time.time()

    fig, axes = plt.subplots(3, 1, figsize=(9, 7), sharex=True)
    fig.suptitle(title, fontsize=13, fontweight="bold")

    lines = []
    labels = ("Température (°C)", "Humidité (%)", "Tension (V)")
    colors = ("#e11d48", "#2563eb", "#059669")
    data_refs = (temps, hums, volts)

    for ax, label, color, data in zip(axes, labels, colors, data_refs):
        (ln,) = ax.plot([], [], color=color, linewidth=2)
        ax.set_ylabel(label)
        ax.grid(True, alpha=0.3)
        lines.append(ln)

    axes[-1].set_xlabel("Temps (s)")
    status = fig.text(0.02, 0.01, "", fontsize=9, color="#64748b")

    def update(_frame: int):
        temp, hum, volt = source.read()
        elapsed = time.time() - t0
        times.append(elapsed)
        temps.append(temp)
        hums.append(hum)
        volts.append(volt)

        for ln, data in zip(lines, data_refs):
            ln.set_data(list(times), list(data))

        for ax in axes:
            ax.relim()
            ax.autoscale_view()

        status.set_text(f"Dernier échantillon : T={temp}°C  H={hum}%  V={volt}V")
        return lines

    ani = animation.FuncAnimation(fig, update, interval=INTERVAL_MS, blit=False)

    try:
        plt.tight_layout()
        plt.show()
    finally:
        if hasattr(source, "close"):
            source.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
