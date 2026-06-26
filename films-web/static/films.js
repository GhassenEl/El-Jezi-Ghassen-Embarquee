const grid = document.getElementById("filmGrid");
const search = document.getElementById("search");
const genreFilter = document.getElementById("genreFilter");
const statsEl = document.getElementById("stats");

async function loadGenres() {
  const res = await fetch("/api/genres");
  const genres = await res.json();
  genres.forEach((g) => {
    const opt = document.createElement("option");
    opt.value = g;
    opt.textContent = g;
    genreFilter.appendChild(opt);
  });
}

async function loadStats() {
  const res = await fetch("/api/stats");
  const s = await res.json();
  statsEl.innerHTML = `
    <strong>${s.films}</strong> films · <strong>${s.acteurs}</strong> acteurs<br>
    <strong>${s.genres}</strong> genres · <strong>${s.films_tunisiens}</strong> films tunisiens<br>
    Note moy. <strong>${s.note_moyenne}</strong>/10`;
}

async function loadFilms() {
  const q = search.value.trim();
  const genre = genreFilter.value;
  const params = new URLSearchParams();
  if (q) params.set("q", q);
  if (genre) params.set("genre", genre);
  const res = await fetch(`/api/films?${params}`);
  const films = await res.json();
  grid.innerHTML = films
    .map(
      (f) => `
    <article class="card">
      <h2>${f.titre}</h2>
      <p class="meta">${f.annee} · ${f.duree_min || "—"} min · ${f.realisateur}</p>
      <p class="note">${f.note ?? "—"}/10</p>
      <p class="genres">${f.genres || "—"}</p>
      <p class="cast">${f.casting ? "Casting : " + f.casting : ""}</p>
      <p class="synopsis">${f.synopsis || ""}</p>
    </article>`
    )
    .join("");
}

search.addEventListener("input", () => loadFilms());
genreFilter.addEventListener("change", () => loadFilms());

loadGenres();
loadStats();
loadFilms();
