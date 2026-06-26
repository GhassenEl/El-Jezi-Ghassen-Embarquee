"""
Moteur IA Smart Home — confort, securite, energie, recommandations.
Heuristiques domotique sans ML lourd.
"""
from __future__ import annotations

import statistics
from dataclasses import asdict, dataclass
from typing import Any


@dataclass
class HomeAiInsights:
  zone: str
  security_risk: str
  comfort_score: int
  energy_score: int
  temp_trend: str
  predicted_temp_c: float | None
  power_w_avg: int | None
  anomalies: list[str]
  recommendations: list[str]
  auto_mode_recommended: str | None
  source: str = "cloud"

  def to_dict(self) -> dict[str, Any]:
    return asdict(self)


def _temp_trend(temps: list[float]) -> str:
  if len(temps) < 2:
    return "stable"
  delta = temps[-1] - temps[0]
  if delta > 1.5:
    return "hausse"
  if delta < -1.5:
    return "baisse"
  return "stable"


def _predict_temp(temps: list[float], current: float) -> float | None:
  if len(temps) < 2:
    return current
  slope = max(-2.0, min(2.0, temps[-1] - temps[-2]))
  return round(max(10.0, min(35.0, current + slope * 3)), 1)


def _security_risk(
    *,
    mode: str,
    motion: bool,
    door_open: bool,
    alarm_on: bool,
    zone: str,
) -> str:
  if mode == "AWAY" and motion and door_open:
    return "high"
  if mode == "AWAY" and motion:
    return "high"
  if door_open and zone in ("garage", "cuisine"):
    return "medium"
  if mode == "AWAY" and not alarm_on:
    return "medium"
  return "low"


def _comfort_score(temp_c: float, humidity: float, lux: int, target: float = 22.0) -> int:
  temp_penalty = abs(temp_c - target) * 8
  hum_penalty = max(0, abs(humidity - 50) - 10) * 0.5
  lux_bonus = 5 if 200 <= lux <= 600 else 0
  return int(max(0, min(100, 100 - temp_penalty - hum_penalty + lux_bonus)))


def _energy_score(power_w: int, light_on: bool, heat_on: bool, mode: str) -> int:
  base = 100 - min(90, power_w // 15)
  if mode == "AWAY" and (light_on or heat_on):
    base -= 25
  if heat_on and power_w > 500:
    base -= 15
  return int(max(0, min(100, base)))


def analyze_zone(
    history: list[dict[str, Any]],
    *,
    zone: str,
    mode: str = "HOME",
    alarm_on: bool = True,
    target_temp: float = 22.0,
    latest_by_zone: dict[str, dict[str, Any]] | None = None,
) -> HomeAiInsights:
  """Analyse une zone a partir de l'historique SQLite."""
  latest_by_zone = latest_by_zone or {}
  rows = [r for r in history if r.get("zone") == zone]
  if not rows:
    return HomeAiInsights(
        zone=zone,
        security_risk="unknown",
        comfort_score=0,
        energy_score=0,
        temp_trend="stable",
        predicted_temp_c=None,
        power_w_avg=None,
        anomalies=["Pas d'historique pour cette zone"],
        recommendations=["Lancez le simulateur MQTT ou connectez l'ESP32"],
        auto_mode_recommended=None,
    )

  current = rows[-1]
  temps = [float(r["temp_c"]) for r in rows[-20:]]
  powers = [int(r["power_w"]) for r in rows[-10:]]
  temp = float(current.get("temp_c", 22))
  humidity = float(current.get("humidity", 50))
  lux = int(current.get("lux", 300))
  motion = bool(current.get("motion"))
  door_open = bool(current.get("door_open"))
  light_on = bool(current.get("light_on"))
  heat_on = bool(current.get("heat_on"))
  power_w = int(current.get("power_w", 0))

  trend = _temp_trend(temps)
  predicted = _predict_temp(temps, temp)
  security = _security_risk(
      mode=mode, motion=motion, door_open=door_open, alarm_on=alarm_on, zone=zone,
  )
  comfort = _comfort_score(temp, humidity, lux, target_temp)
  energy = _energy_score(power_w, light_on, heat_on, mode)
  power_avg = int(statistics.mean(powers)) if powers else power_w

  anomalies: list[str] = []
  if temp > 30:
    anomalies.append(f"Temperature elevee {temp:.1f}°C")
  if humidity > 75:
    anomalies.append(f"Humidite elevee {humidity:.0f}%")
  if mode == "AWAY" and motion:
    anomalies.append("Mouvement detecte en mode AWAY")
  if door_open:
    anomalies.append(f"Porte ouverte — zone {zone}")
  if mode == "AWAY" and (light_on or heat_on):
    anomalies.append("Consommation inutile en mode absent")
  if power_w > 900:
    anomalies.append(f"Pic de puissance {power_w} W")

  recommendations: list[str] = []
  auto_mode: str | None = None

  if security == "high":
    recommendations.append("Verifier immediatement — risque intrusion")
    auto_mode = "AWAY"
  if mode == "AWAY" and light_on:
    recommendations.append("Eteindre les lumieres (MODE AWAY)")
  if mode == "AWAY" and heat_on:
    recommendations.append("Couper le chauffage en absence")
  if comfort < 45 and heat_on:
    recommendations.append("Ajuster la consigne temperature")
  if lux < 80 and not light_on and mode == "HOME":
    recommendations.append("Activer l'eclairage — luminosite faible")
  if trend == "hausse" and temp > 26:
    recommendations.append("Ventiler ou activer climatisation")
  if mode == "HOME" and not motion and lux < 100 and tick_safe_hour():
    auto_mode = "SLEEP"
    recommendations.append("Mode SLEEP recommande (absence mouvement)")
  if not recommendations:
    recommendations.append("Maison en equilibre — aucune action urgente")

  return HomeAiInsights(
      zone=zone,
      security_risk=security,
      comfort_score=comfort,
      energy_score=energy,
      temp_trend=trend,
      predicted_temp_c=predicted,
      power_w_avg=power_avg,
      anomalies=anomalies,
      recommendations=recommendations,
      auto_mode_recommended=auto_mode,
  )


def tick_safe_hour() -> bool:
  """Heuristique soiree pour mode SLEEP (toujours vrai en demo)."""
  return True


def home_overview(latest_by_zone: dict[str, dict[str, Any]]) -> dict[str, Any]:
  if not latest_by_zone:
    return {"zones": 0, "global_security": "unknown", "total_power_w": 0}
  total_pwr = sum(int(v.get("power_w", 0)) for v in latest_by_zone.values())
  any_motion_away = any(bool(v.get("motion")) for v in latest_by_zone.values())
  any_door = any(bool(v.get("door_open")) for v in latest_by_zone.values())
  risk = "high" if any_motion_away and any_door else "medium" if any_door else "low"
  busiest = max(latest_by_zone.items(), key=lambda x: int(x[1].get("power_w", 0)))
  return {
      "zones": len(latest_by_zone),
      "total_power_w": total_pwr,
      "global_security": risk,
      "busiest_zone": busiest[0],
      "busiest_power_w": int(busiest[1].get("power_w", 0)),
  }
