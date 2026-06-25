#!/usr/bin/env python3
"""Catalogue web Films — Flask + SQLite."""
from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

from flask import Flask, jsonify, render_template, request

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB = ROOT / "data" / "films.db"

app = Flask(__name__)
DB_PATH = DEFAULT_DB


def get_db() -> sqlite3.Connection:
  conn = sqlite3.connect(DB_PATH)
  conn.row_factory = sqlite3.Row
  return conn


@app.route("/")
def index():
  return render_template("films.html")


@app.route("/api/films")
def api_films():
  genre = request.args.get("genre", "").strip()
  q = request.args.get("q", "").strip()
  sql = """
    SELECT f.id, f.titre, f.annee, f.duree_min, f.note, f.synopsis,
           r.prenom || ' ' || r.nom AS realisateur,
           r.pays AS pays_realisateur,
           (SELECT GROUP_CONCAT(g.nom, ', ')
            FROM film_genre fg
            JOIN genre g ON g.id = fg.genre_id
            WHERE fg.film_id = f.id) AS genres,
           (SELECT GROUP_CONCAT(a.prenom || ' ' || a.nom, ', ')
            FROM film_acteur fa
            JOIN acteur a ON a.id = fa.acteur_id
            WHERE fa.film_id = f.id) AS casting
    FROM film f
    JOIN realisateur r ON r.id = f.realisateur_id
    WHERE 1=1
  """
  params: list = []
  if genre:
    sql += """
      AND EXISTS (
        SELECT 1 FROM film_genre fg
        JOIN genre g ON g.id = fg.genre_id
        WHERE fg.film_id = f.id AND g.nom = ?
      )
    """
    params.append(genre)
  if q:
    like = f"%{q}%"
    sql += """
      AND (
        f.titre LIKE ? OR r.nom LIKE ? OR r.prenom LIKE ?
        OR EXISTS (
          SELECT 1 FROM film_acteur fa
          JOIN acteur a ON a.id = fa.acteur_id
          WHERE fa.film_id = f.id AND (a.nom LIKE ? OR a.prenom LIKE ?)
        )
      )
    """
    params.extend([like, like, like, like, like])
  sql += " ORDER BY f.note DESC, f.titre"
  with get_db() as conn:
    rows = conn.execute(sql, params).fetchall()
  return jsonify([dict(r) for r in rows])


@app.route("/api/genres")
def api_genres():
  with get_db() as conn:
    rows = conn.execute("SELECT nom FROM genre ORDER BY nom").fetchall()
  return jsonify([r["nom"] for r in rows])


@app.route("/api/stats")
def api_stats():
  with get_db() as conn:
    stats = {
        "films": conn.execute("SELECT COUNT(*) FROM film").fetchone()[0],
        "acteurs": conn.execute("SELECT COUNT(*) FROM acteur").fetchone()[0],
        "realisateurs": conn.execute("SELECT COUNT(*) FROM realisateur").fetchone()[0],
        "genres": conn.execute("SELECT COUNT(*) FROM genre").fetchone()[0],
        "note_moyenne": conn.execute("SELECT ROUND(AVG(note), 2) FROM film").fetchone()[0],
        "films_tunisiens": conn.execute(
            "SELECT COUNT(*) FROM film f JOIN realisateur r ON r.id = f.realisateur_id WHERE r.pays = 'Tunisie'"
        ).fetchone()[0],
    }
  return jsonify(stats)


def parse_args() -> argparse.Namespace:
  p = argparse.ArgumentParser(description="Catalogue Films El Jezi")
  p.add_argument("--db", type=Path, default=DEFAULT_DB)
  p.add_argument("--host", default="127.0.0.1")
  p.add_argument("--web-port", type=int, default=8070)
  return p.parse_args()


def main() -> int:
  global DB_PATH
  args = parse_args()
  DB_PATH = args.db
  if not DB_PATH.exists():
    print(f"Base absente : {DB_PATH}")
    print("Lancez : python scripts/init_db.py")
    return 1
  print(f"Catalogue Films : http://{args.host}:{args.web_port}")
  app.run(host=args.host, port=args.web_port, debug=False, threaded=True)
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
