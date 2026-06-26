"""Moteur IA Smart Parking — recommandation place, prediction saturation."""
from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any


@dataclass
class ParkingAiInsights:
  lot_id: str
  occupancy_risk: str
  occupancy_trend: str
  predicted_occ_2h: int | None
  minutes_until_full: int | None
  best_alternative: str | None
  anomalies: list[str]
  recommendations: list[str]
  navigate_here: bool
  source: str = "cloud"

  def to_dict(self) -> dict[str, Any]:
    return asdict(self)


def _trend(vals: list[int]) -> str:
  if len(vals) < 2:
    return "stable"
  d = vals[-1] - vals[0]
  if d > 8:
    return "hausse"
  if d < -5:
    return "baisse"
  return "stable"


def analyze_lot(history: list[dict], *, lot_id: str, latest_by_lot: dict | None = None) -> ParkingAiInsights:
  rows = [r for r in history if r.get("lot_id") == lot_id]
  if not rows:
    return ParkingAiInsights(
        lot_id=lot_id, occupancy_risk="unknown", occupancy_trend="stable",
        predicted_occ_2h=None, minutes_until_full=None, best_alternative=None,
        anomalies=["Pas d'historique"], recommendations=["Lancez le simulateur MQTT"],
        navigate_here=False,
    )

  occs = [int(r.get("occupancy_pct", r.get("occ", 0))) for r in rows[-15:]]
  current = occs[-1]
  trend = _trend(occs)
  slope = (occs[-1] - occs[-2]) if len(occs) >= 2 else 0
  predicted = int(min(100, max(0, current + slope * 4)))
  mins_full = None
  if slope > 0.3 and current < 98:
    mins_full = int((98 - current) / max(slope, 0.5) * 15)

  risk = "high" if current >= 90 else "medium" if current >= 75 else "low"
  row = rows[-1]
  ev_free = int(row.get("ev_free", 0))
  gate = row.get("gate_open", True)

  anomalies = []
  if current >= 95:
    anomalies.append(f"Parking sature {current}%")
  elif current >= 85:
    anomalies.append(f"Occupation elevee {current}%")
  if ev_free == 0:
    anomalies.append("Aucune borne EV libre")
  if gate is False:
    anomalies.append("Barriere fermee")

  best_alt = None
  if latest_by_lot and current >= 80:
    candidates = [
        (lid, int(v.get("occupancy_pct", v.get("occ", 100))))
        for lid, v in latest_by_lot.items()
        if lid != lot_id
    ]
    if candidates:
      best = min(candidates, key=lambda x: x[1])
      if best[1] < current - 10:
        best_alt = best[0]

  recs = []
  navigate = current < 75 and gate is not False
  if current >= 90:
    recs.append("Eviter ce parking — chercher alternative")
  elif current >= 75:
    recs.append("Arrivee rapide recommandee")
  if best_alt:
    recs.append(f"Alternative : {best_alt}")
  if ev_free == 0:
    recs.append("Pas de borne EV disponible")
  if not recs:
    recs.append("Bon choix — places disponibles")

  return ParkingAiInsights(
      lot_id=lot_id,
      occupancy_risk=risk,
      occupancy_trend=trend,
      predicted_occ_2h=predicted,
      minutes_until_full=mins_full,
      best_alternative=best_alt,
      anomalies=anomalies,
      recommendations=recs,
      navigate_here=navigate,
  )


def network_overview(latest: dict[str, dict]) -> dict[str, Any]:
  if not latest:
    return {"lots": 0, "avg_occ": 0, "full_lots": 0}
  occs = [int(v.get("occupancy_pct", v.get("occ", 0))) for v in latest.values()]
  full = sum(1 for o in occs if o >= 90)
  best = min(latest.items(), key=lambda x: int(x[1].get("occupancy_pct", x[1].get("occ", 100))))
  return {
      "lots": len(latest),
      "avg_occ": round(sum(occs) / len(occs), 1),
      "full_lots": full,
      "best_lot": best[0],
      "best_occ": int(best[1].get("occupancy_pct", best[1].get("occ", 0))),
  }
