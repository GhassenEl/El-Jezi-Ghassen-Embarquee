# 12 — SQL Films

Projet pedagogique **bases de donnees relationnelles** : schema, donnees, requetes SQL et catalogue web.

```
sql/01_schema.sql  → tables (film, acteur, realisateur, genre…)
sql/02_seed.sql    → donnees de demo
sql/03_requetes.sql → SELECT, JOIN, GROUP BY, HAVING
scripts/init_db.py  → cree data/films.db (SQLite)
films-web/          → catalogue Flask (port 8070)
```

## Modele relationnel

```
realisateur ──< film >── film_genre >── genre
                  │
                  └── film_acteur >── acteur
```

| Table | Description |
|-------|-------------|
| `realisateur` | Nom, pays, annee de naissance |
| `film` | Titre, annee, duree, note, synopsis |
| `genre` | Drame, SF, Thriller… |
| `acteur` | Casting |
| `film_genre` | N-N film ↔ genre |
| `film_acteur` | N-N film ↔ acteur + role |

## Demarrage rapide

```bash
# 1. Creer la base SQLite
python scripts/init_db.py --reset

# 2. Executer les requetes exemple
python scripts/run_queries.py

# 3. Catalogue web
cd films-web
pip install -r requirements.txt
python app.py --web-port 8070
```

Ouvrir **http://127.0.0.1:8070**

## Requetes manuelles (sqlite3)

```bash
sqlite3 data/films.db
.tables
SELECT titre, note FROM film ORDER BY note DESC;
.quit
```

## Branche GitHub

```bash
git clone -b project/12-sql-films --single-branch \
  https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git
```

## Auteur

**Ghassen El Jezi** — SQL, relations, jointures, agregations.
