// Outils communs à tous les onglets

const client = supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_CLE_PUBLIQUE);

// Chaque onglet s'inscrit ici : ONGLETS.fixes = { afficher(conteneur) { … } }
const ONGLETS = {};

// ---------- Montants (toujours en centimes dans la base) ----------

// 1240 → "12,40 €"
function euros(centimes) {
  return (centimes / 100).toLocaleString('fr-BE', { style: 'currency', currency: 'EUR' });
}

// "12,40" ou "12.40" ou "1 234,5" → 1240 / 123450 ; sinon null
function lireMontant(texte) {
  const propre = String(texte).trim().replace(/[\s  ]/g, '').replace(',', '.');
  if (!/^\d{1,9}(\.\d{1,2})?$/.test(propre)) return null;
  return Math.round(parseFloat(propre) * 100);
}

// 1240 → "12,40" (pour remplir un champ)
function montantPourChamp(centimes) {
  return (centimes / 100).toLocaleString('fr-BE', { minimumFractionDigits: 2, maximumFractionDigits: 2, useGrouping: false });
}

// ---------- Dates (date du jour à Bruxelles, au format "AAAA-MM-JJ") ----------

function aujourdhui() {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Brussels' }).format(new Date());
}

// "2026-11-15" → "2026-11-01"
function moisDe(date) {
  return date.slice(0, 8) + '01';
}

// ("2026-11-01", 2) → "2027-01-01"
function ajouterMois(mois, n) {
  const annee = Number(mois.slice(0, 4));
  const m = Number(mois.slice(5, 7)) - 1 + n;
  const a = annee + Math.floor(m / 12);
  const mm = ((m % 12) + 12) % 12 + 1;
  return a + '-' + String(mm).padStart(2, '0') + '-01';
}

// "2026-11-01" → "Novembre 2026"
function nomMois(mois, avecAnnee = true) {
  const d = new Date(Date.UTC(Number(mois.slice(0, 4)), Number(mois.slice(5, 7)) - 1, 1));
  const options = avecAnnee ? { month: 'long', year: 'numeric', timeZone: 'UTC' } : { month: 'long', timeZone: 'UTC' };
  const texte = d.toLocaleDateString('fr-BE', options);
  return texte.charAt(0).toUpperCase() + texte.slice(1);
}

// 10 → "octobre" ; avec court = true → "oct."
function nomDuMois(numero, court = false) {
  const d = new Date(Date.UTC(2000, numero - 1, 1));
  return d.toLocaleDateString('fr-BE', { month: court ? 'short' : 'long', timeZone: 'UTC' });
}

// "2026-11-15" → "15/11"
function jourCourt(date) {
  return date.slice(8, 10) + '/' + date.slice(5, 7);
}

// ---------- Construction de l'écran (jamais de innerHTML avec des données) ----------

// el('button', { class: 'x', text: 'OK', onclick: f }, enfant1, enfant2…)
function el(balise, attributs = {}, ...enfants) {
  const e = document.createElement(balise);
  for (const [cle, valeur] of Object.entries(attributs)) {
    if (valeur === null || valeur === undefined || valeur === false) continue;
    if (cle === 'text') e.textContent = valeur;
    else if (cle === 'class') e.className = valeur;
    else if (cle.startsWith('on')) e.addEventListener(cle.slice(2), valeur);
    else if (cle === 'style') e.style.cssText = valeur;
    else e.setAttribute(cle, valeur === true ? '' : valeur);
  }
  for (const enfant of enfants) {
    if (enfant === null || enfant === undefined || enfant === false) continue;
    e.append(enfant instanceof Node ? enfant : document.createTextNode(String(enfant)));
  }
  return e;
}

// Icônes (dessins fixes, aucune donnée dedans)
const DESSINS = {
  reglages: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
  gauche: '<path d="M15 6l-6 6 6 6"/>',
  droite: '<path d="M9 6l6 6-6 6"/>',
  coche: '<path d="M5 12l5 5 9-10"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  points: '<circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/>'
};
function icone(nom, taille = 20) {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('width', taille);
  svg.setAttribute('height', taille);
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('fill', 'none');
  svg.setAttribute('stroke', 'currentColor');
  svg.setAttribute('stroke-width', '2');
  svg.setAttribute('stroke-linecap', 'round');
  svg.setAttribute('stroke-linejoin', 'round');
  svg.setAttribute('aria-hidden', 'true');
  svg.innerHTML = DESSINS[nom];
  return svg;
}

// En-tête d'un onglet : titre, éléments à gauche et à droite, et le bouton Réglages
function enTete(titre, aGauche = [], aDroite = []) {
  return el('div', { class: 'entete' },
    el('h1', { text: titre }),
    el('div', { class: 'entete-controles' }, ...aGauche),
    el('div', { class: 'entete-droite' }, ...aDroite,
      el('button', { type: 'button', class: 'bouton-icone', 'aria-label': 'Réglages', onclick: ouvrirReglages }, icone('reglages')))
  );
}

// ---------- Messages et feuilles ----------

let minuteurMessage = null;
function afficherMessage(texte, estErreur = false) {
  const m = document.getElementById('message');
  m.textContent = texte;
  m.classList.toggle('erreur-message', estErreur);
  m.hidden = false;
  clearTimeout(minuteurMessage);
  minuteurMessage = setTimeout(() => { m.hidden = true; }, estErreur ? 6000 : 3000);
}

// Ouvre une feuille par-dessus l'écran avec un titre et un contenu
function ouvrirFeuille(titre, ...contenu) {
  document.getElementById('feuille-titre').textContent = titre;
  const corps = document.getElementById('feuille-corps');
  corps.replaceChildren(...contenu);
  document.getElementById('feuille').hidden = false;
}
function fermerFeuille() {
  document.getElementById('feuille').hidden = true;
  document.getElementById('feuille-corps').replaceChildren();
}

// Transforme une erreur Supabase en phrase lisible
function texteErreur(erreur) {
  if (!navigator.onLine) return 'Pas de connexion internet.';
  const m = (erreur && erreur.message) || String(erreur);
  if (/Failed to fetch|NetworkError|Load failed/i.test(m)) return 'Supabase ne répond pas. Réessaie dans un moment.';
  if (/row-level security|permission denied/i.test(m)) return 'Ce compte n\'a pas le droit de faire ça.';
  return m;
}

// Lit toutes les lignes par paquets de 1 000 (la limite de Supabase par demande).
// "construire" fabrique la requête, avec un ordre stable (sinon des lignes peuvent sauter d'un paquet à l'autre).
async function demanderTout(construire) {
  let tout = [];
  for (let debut = 0; ; debut += 1000) {
    const paquet = await demander(construire().range(debut, debut + 999));
    if (paquet === null) return null;
    tout = tout.concat(paquet);
    if (paquet.length < 1000) return tout;
  }
}

// Lance une requête Supabase ; en cas d'erreur, affiche un message et renvoie null
async function demander(requete) {
  try {
    const { data, error } = await requete;
    if (error) throw error;
    return data;
  } catch (e) {
    console.error(e);
    afficherMessage(texteErreur(e), true);
    return null;
  }
}
