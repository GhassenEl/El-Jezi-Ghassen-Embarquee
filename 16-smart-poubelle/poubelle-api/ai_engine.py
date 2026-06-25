"""Moteur IA Smart Poubelle — prediction remplissage, priorite collecte."""
from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any


@dataclass
class PoubelleAiInsights:
  bin_id: str
  fill_risk: str
  fill_trend: str
  predicted_fill_24h: int | None
  days_until_full: float | None
  collection_priority: int
  anomalies: list[str]
  recommendations: list[str]
  collect_now: bool
  source: str = "cloud"

  def to_dict(self) -> dict[str, Any]:
    return asdict(self)


def _fill_trend(fills: list[int]) -> str:
  if len(fills) < 2:
    return "stable"
  d = fills[-1] - fills[0]
  if d > 8:
    return "hausse"
  if d < -5:
    return "baisse"
  return "stable"


def analyze_bin(history: list[dict], *, bin_id: str, latest_by_bin: dict | None = None) -> PoubelleAiInsights:
  rows = [r for r in history if r.get("bin_id") == bin_id]
  if not rows:
    return PoubelleAiInsights(
        bin_id=bin_id, fill_risk="unknown", fill_trend="stable",
        predicted_fill_24h=None, days_until_full=None, collection_priority=0,
        anomalies=["Pas d'historique"], recommendations=["Lancez le simulateur MQTT"],
        collect_now=False,
    )

  fills = [int(r["fill_pct"]) for r in rows[-15:]]
  current = fills[-1]
  trend = _fill_trend(fills)
  slope = (fills[-1] - fills[-2]) if len(fills) >= 2 else 0
  predicted = int(min(100, max(0, current + slope * 8)))
  days_until = None
  if slope > 0.5:
    days_until = round((95 - current) / (slope * 4), 1)
  elif current >= 95:
    days_until = 0.0

  risk = "high" if current >= 90 else "medium" if current >= 75 else "low"
  priority = min(100, current + (15 if trend == "hausse" else 0))
  row = rows[-1]
  gas = int(row.get("gas_ppm", 0))
  batt = int(row.get("battery_pct", 100))
  lid = bool(row.get("lid_open"))

  anomalies = []
  if current >= 95:
    anomalies.append(f"Poubelle pleine {current}%")
  elif current >= 85:
    anomalies.append(f"Remplissage eleve {current}%")
  if gas > 250:
    anomalies.append(f"Odeur/gaz eleve {gas} ppm")
  if batt < 25:
    anomalies.append(f"Batterie faible {batt}%")
  if lid:
    anomalies.append("Couvercle ouvert")

  recs = []
  collect_now = current >= 88 or (trend == "hausse" and current >= 80)
  if collect_now:
    recs.append("Planifier collecte urgente")
  if gas > 200:
    recs.append("Verifier contenu organique / ventilation")
  if batt < 30:
    recs.append("Remplacer batterie capteur")
  if not recs:
    recs.append("Niveau normal — surveillance continue")

  return PoubelleAiInsights(
      bin_id=bin_id,
      fill_risk=risk,
      fill_trend=trend,
      predicted_fill_24h=predicted,
      days_until_full=days_until,
      collection_priority=priority,
      anomalies=anomalies,
      recommendations=recs,
      collect_now=collect_now,
  )


def network_overview(latest: dict[str, dict]) -> dict[str, Any]:
  if not latest:
    return {"bins": 0, "avg_fill": 0, "need_collection": 0}
  fills = [int(v.get("fill_pct", 0)) for v in latest.values()]
  need = sum(1 for f in fills if f >= 85)
  worst = max(latest.items(), key=lambda x: int(x[1].get("fill_pct", 0)))
  return {
      "bins": len(latest),
      "avg_fill": round(sum(fills) / len(fills), 1),
      "need_collection": need,
      "fullest_bin": worst[0],
      "fullest_fill": int(worst[1].get("fill_pct", 0)),
  }
