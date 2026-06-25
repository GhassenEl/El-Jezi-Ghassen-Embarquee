#!/usr/bin/env python3
"""Execute un fichier .sql et affiche les resultats."""
from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB = ROOT / "data" / "films.db"


def main() -> int:
  p = argparse.ArgumentParser(description="Executer requetes SQL films")
  p.add_argument("sql_file", type=Path, nargs="?", default=ROOT / "sql" / "03_requetes.sql")
  p.add_argument("--db", type=Path, default=DEFAULT_DB)
  args = p.parse_args()

  if not args.db.exists():
    print(f"Base absente : {args.db} — lancez scripts/init_db.py")
    return 1

  conn = sqlite3.connect(args.db)
  conn.row_factory = sqlite3.Row
  raw = args.sql_file.read_text(encoding="utf-8")
  statements = [s.strip() for s in raw.split(";") if s.strip() and not s.strip().startswith("--")]

  for i, stmt in enumerate(statements, 1):
    if not stmt.upper().startswith("SELECT"):
      continue
    print(f"\n--- Requete {i} ---\n{stmt[:80]}...")
    try:
      rows = conn.execute(stmt).fetchall()
      if not rows:
        print("(aucun resultat)")
        continue
      cols = rows[0].keys()
      print(" | ".join(cols))
      print("-" * 40)
      for row in rows:
        print(" | ".join(str(row[c]) for c in cols))
    except sqlite3.Error as e:
      print(f"Erreur : {e}")

  conn.close()
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
