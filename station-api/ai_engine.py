"""
Moteur IA Smart Station — prediction retards, confort, recommandations.
Sans ML lourd : regression lineaire + heuristiques transport.
"""
from __future__ import annotations

import statistics
from dataclasses import asdict, dataclass
from typing import Any


@dataclass
class StationAiInsights:
  station_id: str
  delay_risk: str
  comfort_score: int
  service_score: int
  eta_trend: str
  predicted_eta_min: int | None
  best_alternative_station: str | None
  anomalies: list[str]
  recommendations: list[str]
  leave_now_recommended: bool
  source: str = "cloud"

  def to_dict(self) -> dict[str, Any]:
    return asdict(self)


def _eta_trend(etas: list[float]) -> str:
  if len(etas) < 2:
    return "stable"
  delta = etas[-1] - etas[0]
  if delta > 3:
    return "hausse"
  if delta < -2:
    return "baisse"
  return "stable"


def _predict_eta(etas: list[float], current: int) -> int | None:
  if len(etas) < 2:
    return current
  slope = max(-5.0, min(5.0, etas[-1] - etas[-2]))
  return int(max(1, min(30, round(current + slope * 2))))


def _delay_risk(eta: int, trend: str, predicted: int | None) -> str:
  if eta > 15 or (predicted is not None and predicted > 18):
    return "high"
  if eta > 8 or trend == "hausse":
    return "medium"
  return "low"


def _best_alternative(
    station_id: str,
    vehicle: str,
    occ: int,
    crowd: int,
    latest_by_station: dict[str, dict[str, Any]],
) -> str | None:
  best: str | None = None
  best_score = occ + crowd * 10
  for sid, row in latest_by_station.items():
    if sid == station_id:
      continue
    if row.get("vehicle") != vehicle:
      continue
    score = int(row.get("occ", 50)) + int(row.get("crowd", 2)) * 10
    if score < best_score - 15:
      best_score = score
      best = sid
  return best


def analyze_station(
    history: list[dict[str, Any]],
    *,
    station_id: str,
    latest_by_station: dict[str, dict[str, Any]] | None = None,
) -> StationAiInsights:
  """Analyse a partir de l'historique SQLite (lignes telemetry)."""
  latest_by_station = latest_by_station or {}
  rows = [r for r in history if r.get("station_id") == station_id]
  if not rows:
    return StationAiInsights(
        station_id=station_id,
        delay_risk="unknown",
        comfort_score=0,
        service_score=0,
        eta_trend="stable",
        predicted_eta_min=None,
        best_alternative_station=None,
        anomalies=["Pas d'historique pour cette station"],
        recommendations=["Lancez le simulateur MQTT"],
        leave_now_recommended=False,
    )

  current = rows[-1]
  etas = [float(r["eta_min"]) for r in rows[-20:]]
  eta = int(current.get("eta_min", 0))
  occ = int(current.get("occ", 50))
  crowd = int(current.get("crowd", 2))
  validators = int(current.get("validators", 2))
  vehicle = str(current.get("vehicle", "METRO"))

  trend = _eta_trend(etas)
  predicted = _predict_eta(etas, eta)
  delay_risk = _delay_risk(eta, trend, predicted)
  comfort = max(0, min(100, 100 - occ - crowd * 8))
  service = max(0, min(100, int(comfort + validators * 5)))

  anomalies: list[str] = []
  if occ > 85:
    anomalies.append(f"Affluence critique {occ}%")
  if eta > 12:
    anomalies.append(f"Retard ETA {eta} min")
  if len(etas) >= 3 and etas[-1] - etas[-2] > 4:
    anomalies.append("Hausse brutale du temps d'attente")
  if crowd >= 4:
    anomalies.append(f"Quai tres charge ({crowd}/5)")

  best_alt = _best_alternative(station_id, vehicle, occ, crowd, latest_by_station)

  recommendations: list[str] = []
  if delay_risk == "high":
    recommendations.append("Privilegier une ligne alternative ou partir plus tot")
  if comfort < 40:
    recommendations.append("Attendre le prochain passage (affluence elevee)")
  if best_alt:
    recommendations.append(f"Station alternative moins chargee : {best_alt}")
  if eta <= 4 and comfort >= 50:
    recommendations.append("Bon moment pour monter")
  if not recommendations:
    recommendations.append("Trafic normal — suivez l'affichage temps reel")

  leave_now = eta <= 5 and comfort >= 45 and delay_risk != "high"

  return StationAiInsights(
      station_id=station_id,
      delay_risk=delay_risk,
      comfort_score=comfort,
      service_score=service,
      eta_trend=trend,
      predicted_eta_min=predicted,
      best_alternative_station=best_alt,
      anomalies=anomalies,
      recommendations=recommendations,
      leave_now_recommended=leave_now,
  )


def network_overview(latest_by_station: dict[str, dict[str, Any]]) -> dict[str, Any]:
  """Vue reseau : station la plus chargee, risque global."""
  if not latest_by_station:
    return {"stations": 0, "global_risk": "unknown"}
  occs = [int(v.get("occ", 0)) for v in latest_by_station.values()]
  worst = max(latest_by_station.items(), key=lambda x: int(x[1].get("occ", 0)))
  avg_occ = round(statistics.mean(occs), 1) if occs else 0
  global_risk = "high" if avg_occ > 75 else "medium" if avg_occ > 55 else "low"
  return {
      "stations": len(latest_by_station),
      "avg_occupancy": avg_occ,
      "global_risk": global_risk,
      "busiest_station": worst[0],
      "busiest_occ": int(worst[1].get("occ", 0)),
  }
