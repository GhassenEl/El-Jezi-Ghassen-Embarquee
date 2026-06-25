"""
Moteur IA Smart Farm — analyse, prédiction sol, recommandations irrigation.

Utilise l'historique SQLite (régression linéaire, détection d'anomalies).
Sans dépendance ML lourde — numpy/statistics uniquement.
"""
from __future__ import annotations

import statistics
from dataclasses import asdict, dataclass
from datetime import datetime
from typing import Any


@dataclass
class FarmAiInsights:
  zone: str
  risk_level: str
  health_score: int
  soil_trend: str
  predicted_soil_6h: float | None
  hours_until_dry: float | None
  irrigation_score: int
  anomalies: list[str]
  recommendations: list[str]
  suggested_threshold: int
  auto_irrigate_recommended: bool

  def to_dict(self) -> dict[str, Any]:
    return asdict(self)


def _parse_ts(value: str | None) -> datetime | None:
  if not value:
    return None
  try:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))
  except ValueError:
    return None


def _linear_slope(values: list[float], hours: list[float]) -> float:
  """Pente humidité sol (%/heure)."""
  n = len(values)
  if n < 2:
    return 0.0
  x_mean = statistics.mean(hours)
  y_mean = statistics.mean(values)
  num = sum((hours[i] - x_mean) * (values[i] - y_mean) for i in range(n))
  den = sum((hours[i] - x_mean) ** 2 for i in range(n))
  if den == 0:
    return 0.0
  return num / den


def _detect_anomalies(soils: list[float]) -> list[str]:
  anomalies: list[str] = []
  if len(soils) < 4:
    return anomalies
  deltas = [soils[i] - soils[i - 1] for i in range(1, len(soils))]
  if not deltas:
    return anomalies
  mean_d = statistics.mean(deltas)
  stdev_d = statistics.pstdev(deltas) if len(deltas) > 1 else 0.0
  if stdev_d > 0 and abs(deltas[-1] - mean_d) > 2.5 * stdev_d:
    if deltas[-1] < mean_d:
      anomalies.append("Chute brutale humidité sol détectée")
    else:
      anomalies.append("Hausse anormale humidité sol (irrigation ?)")
  if soils[-1] < 15:
    anomalies.append("Sol très sec — stress hydrique probable")
  if soils[-1] > 80:
    anomalies.append("Sol saturé — risque de sur-irrigation")
  return anomalies


def analyze_farm(
    history: list[dict[str, Any]],
    *,
    soil_threshold: int = 30,
) -> FarmAiInsights | None:
  if not history:
    return None

  latest = history[-1]
  zone = str(latest.get("zone", "parcelle-a"))
  soils = [float(h["soil_moist"]) for h in history if h.get("soil_moist") is not None]
  if not soils:
    return None

  current = soils[-1]
  pump_on = bool(latest.get("pump_on"))
  mode = str(latest.get("mode", "AUTO")).upper()

  # Temps relatif en heures depuis le premier point
  t0 = _parse_ts(history[0].get("recorded_at"))
  hours: list[float] = []
  for h in history:
    ts = _parse_ts(h.get("recorded_at"))
    if t0 and ts:
      hours.append((ts - t0).total_seconds() / 3600.0)
    else:
      hours.append(float(len(hours)) * (3 / 3600))  # ~3 s entre échantillons ESP32

  slope = _linear_slope(soils, hours)
  if slope < -0.3:
    trend = "declining"
  elif slope > 0.3:
    trend = "rising"
  else:
    trend = "stable"

  predicted_6h = round(current + slope * 6, 1) if len(soils) >= 3 else None

  hours_until_dry: float | None = None
  if slope < -0.05 and current > soil_threshold:
    hours_until_dry = round((current - soil_threshold) / abs(slope), 1)

  anomalies = _detect_anomalies(soils)
  recommendations: list[str] = []

  # Score santé parcelle 0–100
  health = 100
  health -= max(0, int((soil_threshold - current) * 2)) if current < soil_threshold else 0
  health -= 10 if trend == "declining" else 0
  health -= 5 * len(anomalies)
  health = max(0, min(100, health))

  irrigation_score = 0
  if current < soil_threshold:
    irrigation_score = min(100, int(60 + (soil_threshold - current) * 2))
  elif predicted_6h is not None and predicted_6h < soil_threshold:
    irrigation_score = 45

  risk = "low"
  if current < soil_threshold * 0.7 or (predicted_6h is not None and predicted_6h < soil_threshold * 0.8):
    risk = "critical"
  elif current < soil_threshold or irrigation_score >= 50:
    risk = "high"
  elif trend == "declining" or anomalies:
    risk = "medium"

  suggested_thresh = soil_threshold
  if trend == "declining" and current < 40:
    suggested_thresh = min(45, soil_threshold + 5)
    recommendations.append(f"Envisager seuil {suggested_thresh}% (sol se dessèche vite)")
  if mode == "MANUAL" and risk in ("high", "critical"):
    recommendations.append("Passer en MODE_AUTO pour irrigation assistée")
  if risk == "critical" and not pump_on:
    recommendations.append("Irrigation urgente recommandée")
  elif risk == "high" and not pump_on:
    recommendations.append("Planifier irrigation dans les prochaines heures")
  if trend == "rising" and current > 70:
    recommendations.append("Réduire la fréquence d'irrigation")
  if not recommendations:
    recommendations.append("Parcelle stable — poursuivre la surveillance")

  auto_irrigate = (
      risk == "critical"
      and not pump_on
      and mode == "AUTO"
      and current < soil_threshold
  )

  return FarmAiInsights(
      zone=zone,
      risk_level=risk,
      health_score=health,
      soil_trend=trend,
      predicted_soil_6h=predicted_6h,
      hours_until_dry=hours_until_dry,
      irrigation_score=irrigation_score,
      anomalies=anomalies,
      recommendations=recommendations,
      suggested_threshold=suggested_thresh,
      auto_irrigate_recommended=auto_irrigate,
  )


def predict_soil_at(history: list[dict[str, Any]], hours: float, soil_threshold: int = 30) -> float | None:
  """Extrapole l'humidité sol à +N heures."""
  insights = analyze_farm(history, soil_threshold=soil_threshold)
  if not insights or insights.predicted_soil_6h is None or hours <= 0:
    return None
  soils = [float(h["soil_moist"]) for h in history if h.get("soil_moist") is not None]
  if not soils:
    return None
  current = soils[-1]
  slope = (insights.predicted_soil_6h - current) / 6.0
  return round(current + slope * hours, 1)
