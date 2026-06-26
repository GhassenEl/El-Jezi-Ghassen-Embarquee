"""Moteur IA Smart Energy — optimisation consommation, pics, solaire."""
from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any


@dataclass
class EnergyAiInsights:
  site_id: str
  efficiency_score: int
  cost_risk: str
  load_trend: str
  predicted_load_2h: float | None
  solar_coverage_pct: int | None
  anomalies: list[str]
  recommendations: list[str]
  eco_mode_recommended: bool
  source: str = "cloud"

  def to_dict(self) -> dict[str, Any]:
    return asdict(self)


def _trend(vals: list[float]) -> str:
  if len(vals) < 2:
    return "stable"
  d = vals[-1] - vals[0]
  if d > 15:
    return "hausse"
  if d < -10:
    return "baisse"
  return "stable"


def analyze_site(history: list[dict], *, site_id: str, latest_by_site: dict | None = None) -> EnergyAiInsights:
  rows = [r for r in history if r.get("site_id") == site_id]
  if not rows:
    return EnergyAiInsights(
        site_id=site_id, efficiency_score=0, cost_risk="unknown", load_trend="stable",
        predicted_load_2h=None, solar_coverage_pct=None,
        anomalies=["Pas d'historique"], recommendations=["Lancez le simulateur MQTT"],
        eco_mode_recommended=False,
    )

  loads = [float(r.get("load_kw", 0)) for r in rows[-15:]]
  current_load = loads[-1]
  trend = _trend(loads)
  slope = (loads[-1] - loads[-2]) if len(loads) >= 2 else 0
  predicted = round(max(0, current_load + slope * 3), 1)

  row = rows[-1]
  solar = float(row.get("solar_kw", 0))
  grid = float(row.get("grid_kw", 0))
  batt = int(row.get("battery_pct", 0))
  cost = float(row.get("cost_tnd_h", 0))
  peak = bool(row.get("peak", grid > current_load * 0.7))

  coverage = int(min(100, (solar / current_load * 100) if current_load > 0 else 0))
  efficiency = min(100, coverage + (20 if batt > 50 else 0) - (15 if peak else 0))
  cost_risk = "high" if cost > 50 or peak else "medium" if cost > 20 else "low"

  anomalies = []
  if peak:
    anomalies.append("Pic consommation actif")
  if grid > current_load * 0.8:
    anomalies.append(f"Dependance reseau elevee {grid:.0f} kW")
  if batt < 25 and batt > 0:
    anomalies.append(f"Batterie faible {batt}%")
  if coverage < 20 and solar > 0:
    anomalies.append("Production solaire insuffisante")

  eco = peak or cost_risk == "high" or batt < 30
  recs = []
  if eco:
    recs.append("Activer mode ECO — reduire charges non critiques")
  if coverage > 60:
    recs.append("Bon apport solaire — reporter charges flexibles")
  if batt < 40 and batt > 0:
    recs.append("Recharger batterie en heures creuses")
  if not recs:
    recs.append("Profil energetique equilibre")

  return EnergyAiInsights(
      site_id=site_id,
      efficiency_score=efficiency,
      cost_risk=cost_risk,
      load_trend=trend,
      predicted_load_2h=predicted,
      solar_coverage_pct=coverage,
      anomalies=anomalies,
      recommendations=recs,
      eco_mode_recommended=eco,
  )


def network_overview(latest: dict[str, dict]) -> dict[str, Any]:
  if not latest:
    return {"sites": 0, "total_load_kw": 0, "solar_share_pct": 0}
  load = sum(float(v.get("load_kw", 0)) for v in latest.values())
  solar = sum(float(v.get("solar_kw", 0)) for v in latest.values())
  return {
      "sites": len(latest),
      "total_load_kw": round(load, 1),
      "total_solar_kw": round(solar, 1),
      "solar_share_pct": round(solar / load * 100, 1) if load else 0,
  }
