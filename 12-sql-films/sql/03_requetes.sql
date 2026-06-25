-- Requetes SQL pedagogiques — El Jezi Films

-- 1. Liste des films avec realisateur
SELECT f.titre, f.annee, f.note,
       r.prenom || ' ' || r.nom AS realisateur
FROM film f
JOIN realisateur r ON r.id = f.realisateur_id
ORDER BY f.note DESC;

-- 2. Films par genre
SELECT g.nom AS genre, COUNT(*) AS nb_films
FROM genre g
JOIN film_genre fg ON fg.genre_id = g.id
GROUP BY g.nom
ORDER BY nb_films DESC;

-- 3. Acteurs et leurs films
SELECT a.prenom || ' ' || a.nom AS acteur,
       f.titre, fa.role
FROM acteur a
JOIN film_acteur fa ON fa.acteur_id = a.id
JOIN film f ON f.id = fa.film_id
ORDER BY acteur, f.titre;

-- 4. Films tunisiens ou realisateur tunisien
SELECT f.titre, f.annee, r.pays
FROM film f
JOIN realisateur r ON r.id = f.realisateur_id
WHERE r.pays = 'Tunisie';

-- 5. Meilleure note par decennie
SELECT (f.annee / 10) * 10 AS decennie,
       MAX(f.note) AS meilleure_note
FROM film f
GROUP BY decennie
ORDER BY decennie;

-- 6. Films avec au moins 2 genres (sous-requete)
SELECT f.titre
FROM film f
WHERE (
  SELECT COUNT(*) FROM film_genre fg WHERE fg.film_id = f.id
) >= 2;

-- 7. Realisateurs avec moyenne de notes > 8
SELECT r.prenom || ' ' || r.nom AS realisateur,
       ROUND(AVG(f.note), 2) AS note_moyenne,
       COUNT(*) AS nb_films
FROM realisateur r
JOIN film f ON f.realisateur_id = r.id
GROUP BY r.id
HAVING AVG(f.note) >= 8.0
ORDER BY note_moyenne DESC;

-- 8. INSERT exemple
-- INSERT INTO film (titre, annee, duree_min, note, synopsis, realisateur_id)
-- VALUES ('Nouveau film', 2024, 120, 7.5, 'Synopsis...', 1);

-- 9. Top 5 des films les mieux notes
SELECT titre, annee, note
FROM film
ORDER BY note DESC
LIMIT 5;

-- 10. Acteurs les plus prolifiques (au moins 2 films)
SELECT a.prenom || ' ' || a.nom AS acteur,
       COUNT(DISTINCT fa.film_id) AS nb_films
FROM acteur a
JOIN film_acteur fa ON fa.acteur_id = a.id
GROUP BY a.id
HAVING COUNT(DISTINCT fa.film_id) >= 2
ORDER BY nb_films DESC, acteur;

-- 11. Cinema tunisien : films, realisateur et casting
SELECT f.titre, f.annee,
       r.prenom || ' ' || r.nom AS realisateur,
       GROUP_CONCAT(a.prenom || ' ' || a.nom, ', ') AS casting
FROM film f
JOIN realisateur r ON r.id = f.realisateur_id
LEFT JOIN film_acteur fa ON fa.film_id = f.id
LEFT JOIN acteur a ON a.id = fa.acteur_id
WHERE r.pays = 'Tunisie'
GROUP BY f.id
ORDER BY f.annee DESC;
