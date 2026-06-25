-- El Jezi Ghassen — Base de donnees Films
-- Schema relationnel (SQLite / PostgreSQL compatible)

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS realisateur (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  nom           TEXT NOT NULL,
  prenom        TEXT NOT NULL,
  pays          TEXT,
  annee_naissance INTEGER
);

CREATE TABLE IF NOT EXISTS genre (
  id   INTEGER PRIMARY KEY AUTOINCREMENT,
  nom  TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS acteur (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  nom           TEXT NOT NULL,
  prenom        TEXT NOT NULL,
  pays          TEXT
);

CREATE TABLE IF NOT EXISTS film (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  titre           TEXT NOT NULL,
  annee           INTEGER NOT NULL,
  duree_min       INTEGER,
  note            REAL CHECK (note >= 0 AND note <= 10),
  synopsis        TEXT,
  realisateur_id  INTEGER NOT NULL,
  FOREIGN KEY (realisateur_id) REFERENCES realisateur(id)
);

CREATE TABLE IF NOT EXISTS film_genre (
  film_id  INTEGER NOT NULL,
  genre_id INTEGER NOT NULL,
  PRIMARY KEY (film_id, genre_id),
  FOREIGN KEY (film_id) REFERENCES film(id) ON DELETE CASCADE,
  FOREIGN KEY (genre_id) REFERENCES genre(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS film_acteur (
  film_id   INTEGER NOT NULL,
  acteur_id INTEGER NOT NULL,
  role      TEXT,
  PRIMARY KEY (film_id, acteur_id),
  FOREIGN KEY (film_id) REFERENCES film(id) ON DELETE CASCADE,
  FOREIGN KEY (acteur_id) REFERENCES acteur(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_film_annee ON film(annee);
CREATE INDEX IF NOT EXISTS idx_film_realisateur ON film(realisateur_id);
CREATE INDEX IF NOT EXISTS idx_film_note ON film(note);
