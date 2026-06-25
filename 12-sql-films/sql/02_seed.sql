-- Donnees de demonstration — cinema mondial + tunisien

INSERT INTO realisateur (nom, prenom, pays, annee_naissance) VALUES
  ('Nolan', 'Christopher', 'Royaume-Uni', 1970),
  ('Scorsese', 'Martin', 'USA', 1942),
  ('Bouzid', 'Nouri', 'Tunisie', 1952),
  ('Tarantino', 'Quentin', 'USA', 1963),
  ('Amenabar', 'Alejandro', 'Espagne', 1972),
  ('Villeneuve', 'Denis', 'Canada', 1967);

INSERT INTO genre (nom) VALUES
  ('Drame'), ('Science-fiction'), ('Thriller'), ('Comedie'), ('Historique'), ('Action');

INSERT INTO acteur (nom, prenom, pays) VALUES
  ('DiCaprio', 'Leonardo', 'USA'),
  ('Hanks', 'Tom', 'USA'),
  ('Bouajila', 'Sami', 'Tunisie/France'),
  ('Chastain', 'Jessica', 'USA'),
  ('Gosling', 'Ryan', 'Canada'),
  ('Bardem', 'Javier', 'Espagne');

INSERT INTO film (titre, annee, duree_min, note, synopsis, realisateur_id) VALUES
  ('Inception', 2010, 148, 8.8, 'Un voleur qui s''infiltre dans les reves.', 1),
  ('Les Infiltres', 2006, 151, 8.5, 'Policier et mafia a Boston.', 2),
  ('Making Of', 2006, 115, 7.2, 'Tournage chaotique d''un film tunisien.', 3),
  ('Pulp Fiction', 1994, 154, 8.9, 'Histoires entrelacees a Los Angeles.', 4),
  ('La Vie des autres', 2006, 137, 8.4, 'Surveillance est-allemande.', 5),
  ('Blade Runner 2049', 2017, 164, 8.0, 'Un replicant cherche son identite.', 6),
  ('Interstellar', 2014, 169, 8.6, 'Voyage spatial pour sauver l''humanite.', 1);

INSERT INTO film_genre (film_id, genre_id) VALUES
  (1, 2), (1, 3),
  (2, 1), (2, 3),
  (3, 1), (3, 4),
  (4, 3), (4, 4),
  (5, 1), (5, 5),
  (6, 2), (6, 6),
  (7, 2), (7, 1);

INSERT INTO film_acteur (film_id, acteur_id, role) VALUES
  (1, 1, 'Cobb'),
  (2, 1, 'Billy'),
  (3, 3, 'Samir'),
  (4, 1, 'Jack'),
  (5, 6, 'Agent secret'),
  (6, 5, 'K'),
  (7, 1, 'Cooper');
