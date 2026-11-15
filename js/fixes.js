// Onglet Fixes : vue Mois (pour cocher) et vue Année (la grille, comme l'Excel)

const fixes = {
  vue: 'mois',          // 'mois' ou 'annee'
  mois: null,           // mois affiché, "AAAA-MM-01"
  annee: null,          // année affichée dans la vue Année
  depart: null,         // date de départ de l'appli
  aConfirmer: null,     // charge sur laquelle on a touché une fois pour annuler
  minuteur: null,
  conteneur: null
};

ONGLETS.fixes = {
  async afficher(conteneur) {
    fixes.conteneur = conteneur;
    if (!fixes.mois) fixes.mois = moisDe(aujourdhui());
    if (!fixes.depart) {
      const p = await demander(client.from('parametres').select('date_depart').single());
      fixes.depart = p ? p.date_depart : fixes.mois;
    }
    await dessinerFixes();
  }
};

// Toujours entre le mois de départ et décembre de l'année prochaine (comme la base)
function moisPermis(mois) {
  const fin = (Number(aujourdhui().slice(0, 4)) + 1) + '-12-01';
  return mois >= fixes.depart && mois <= fin;
}

async function dessinerFixes() {
  const c = fixes.conteneur;
  const choix = el('div', { class: 'segments', role: 'group', 'aria-label': 'Vue' },
    el('button', { type: 'button', 'aria-pressed': String(fixes.vue === 'mois'), onclick: () => { fixes.vue = 'mois'; dessinerFixes(); } }, 'Mois'),
    el('button', { type: 'button', 'aria-pressed': String(fixes.vue === 'annee'), onclick: () => { fixes.vue = 'annee'; fixes.annee = Number(fixes.mois.slice(0, 4)); dessinerFixes(); } }, 'Année'));

  if (fixes.vue === 'annee') {
    await dessinerAnnee(c, choix);
    return;
  }

  const precedent = ajouterMois(fixes.mois, -1);
  const suivant = ajouterMois(fixes.mois, 1);
  const selecteur = el('div', { class: 'selecteur-mois' },
    el('button', { type: 'button', class: 'bouton-icone', 'aria-label': 'Mois précédent', disabled: !moisPermis(precedent),
      onclick: () => { fixes.mois = precedent; dessinerFixes(); } }, icone('gauche')),
    el('span', { class: 'selecteur-texte' }, nomMois(fixes.mois)),
    el('button', { type: 'button', class: 'bouton-icone', 'aria-label': 'Mois suivant', disabled: !moisPermis(suivant),
      onclick: () => { fixes.mois = suivant; dessinerFixes(); } }, icone('droite')));

  // Données : les cases du mois, la réserve, et les charges annuelles à venir
  const moisCourant = moisDe(aujourdhui());
  const [lignes, reserve, annuelles] = await Promise.all([
    demander(client.from('v_charges_grille').select('*').eq('mois', fixes.mois).order('ordre').order('charge_id')),
    demander(client.from('v_reserve_fixes').select('reserve').single()),
    demander(client.from('v_charges_grille').select('charge_id, nom, mois')
      .eq('mois_echeance', true).eq('etat', 'cote')
      .gte('mois', moisCourant).lte('mois', ajouterMois(moisCourant, 11)).order('mois'))
  ]);
  if (lignes === null) return;

  const totalPrevu = lignes.reduce((s, l) => s + l.montant, 0);
  const totalPaye = lignes.filter((l) => l.etat === 'paye').reduce((s, l) => s + l.montant, 0);

  const resume = el('div', { class: 'resume' },
    carteChiffre('Prévu ce mois', euros(totalPrevu)),
    carteChiffre('Payé', euros(totalPaye), 'bleu'),
    carteChiffre('Mis de côté', euros(totalPrevu - totalPaye), 'orange'),
    carteChiffre('Réserve totale', reserve ? euros(reserve.reserve) : '—', 'fonce'));

  const bandeau = fixes.mois === moisCourant ? bandeauAPayer(lignes, annuelles || []) : null;

  if (lignes.length === 0) {
    c.replaceChildren(enTete('Fixes', [choix, selecteur]), resume,
      el('p', { class: 'vide', text: 'Aucune charge ce mois-là.' }));
    return;
  }

  c.replaceChildren(enTete('Fixes', [choix, selecteur]), resume, bandeau, colonnesDeGroupes(lignes));
}

function carteChiffre(titre, valeur, couleur = '') {
  return el('div', { class: 'carte chiffre-carte ' + couleur },
    el('div', { class: 'chiffre-titre', text: titre }),
    el('div', { class: 'chiffre-valeur chiffre', text: valeur }));
}

// ---------- Bandeau « À payer bientôt » ----------

function bandeauAPayer(lignes, annuelles) {
  const jour = Number(aujourdhui().slice(8, 10));
  const pastilles = [];
  // Prélèvements du mois pas encore cochés (seulement ceux qui ont un jour)
  lignes.filter((l) => l.echeance_type === 'jour' && l.echeance_jour && l.etat === 'cote')
    .sort((a, b) => a.echeance_jour - b.echeance_jour)
    .forEach((l) => {
      const urgent = l.echeance_jour - jour <= 7; // en retard ou dans les 7 jours
      pastilles.push(el('span', { class: 'pastille' + (urgent ? ' urgente' : '') },
        el('strong', { text: 'le ' + l.echeance_jour }), ' ' + l.nom + ' · ', el('span', { class: 'chiffre', text: euros(l.montant) })));
    });
  // Charges annuelles dans les 12 prochains mois (urgentes ce mois-ci et le suivant)
  const limite = ajouterMois(moisDe(aujourdhui()), 1);
  annuelles.forEach((a) => {
    pastilles.push(el('span', { class: 'pastille' + (a.mois <= limite ? ' urgente' : '') },
      el('strong', { text: nomDuMois(Number(a.mois.slice(5, 7)), true) }), ' ' + a.nom));
  });
  if (pastilles.length === 0) return null;
  return el('div', { class: 'bandeau' }, el('span', { class: 'bandeau-titre', text: 'À payer bientôt' }), ...pastilles);
}

// ---------- Groupes et lignes ----------

// Répartit les groupes en 2 colonnes à peu près égales (en gardant l'ordre)
function colonnesDeGroupes(lignes) {
  const groupes = [];
  lignes.forEach((l) => {
    let g = groupes.find((x) => x.nom === l.groupe);
    if (!g) { g = { nom: l.groupe, lignes: [] }; groupes.push(g); }
    g.lignes.push(l);
  });
  const moitie = lignes.length / 2;
  const gauche = [], droite = [];
  let compte = 0;
  groupes.forEach((g) => {
    (compte + g.lignes.length / 2 <= moitie ? gauche : droite).push(g);
    compte += g.lignes.length;
  });
  const colonne = (liste) => el('div', { class: 'colonne' }, ...liste.map(carteGroupe));
  return el('div', { class: 'colonnes' }, colonne(gauche), colonne(droite));
}

function carteGroupe(g) {
  const paye = g.lignes.filter((l) => l.etat === 'paye').reduce((s, l) => s + l.montant, 0);
  const total = g.lignes.reduce((s, l) => s + l.montant, 0);
  return el('section', { class: 'carte groupe' },
    el('div', { class: 'groupe-haut' },
      el('h2', { text: g.nom }),
      el('span', { class: 'chiffre groupe-resume', text: euros(paye) + ' payés sur ' + euros(total) })),
    ...g.lignes.map(ligneCharge));
}

// Petite ligne sous le nom : quand est-ce que ça se paie
function texteEcheance(l) {
  const carte = l.carte_id ? ' · par carte' : '';
  if (l.etat === 'paye') return 'payé le ' + jourCourt(l.date_paiement) + carte;
  if (l.echeance_type === 'jour') return (l.echeance_jour ? 'prélevé le ' + l.echeance_jour : 'chaque mois') + carte;
  if (l.echeance_type === 'mois') return (l.mois_echeance ? 'à payer ce mois-ci' : 'mis de côté · payé en ' + nomDuMois(l.echeance_mois)) + carte;
  return 'mis de côté · payé quand il faut' + carte;
}

function ligneCharge(l) {
  const paye = l.etat === 'paye';
  const enAttente = fixes.aConfirmer === l.charge_id + '|' + l.mois;
  const pilule = paye
    ? el('span', { class: 'pilule payee' + (enAttente ? ' a-confirmer' : '') }, enAttente ? 'Annuler ?' : icone('coche', 14), enAttente ? null : 'Payé')
    : el('span', { class: 'pilule cote' }, 'Mis de côté');
  return el('button', {
    type: 'button', class: 'ligne',
    'aria-label': l.nom + ', ' + euros(l.montant) + ', ' + (paye ? 'payé' : 'mis de côté') + '. ' + (paye ? 'Toucher deux fois pour annuler.' : 'Toucher pour payer.'),
    onclick: () => toucherLigne(l)
  },
    el('span', { class: 'ligne-texte' },
      el('span', { class: 'ligne-nom', text: l.nom }),
      el('span', { class: 'ligne-detail', text: texteEcheance(l) })),
    el('span', { class: 'ligne-montant chiffre', text: euros(l.montant) }),
    pilule);
}

// ---------- Payer et annuler ----------

function toucherCase(x) { toucherLigne(x); } // même comportement dans la grille

async function toucherLigne(l) {
  if (l.etat === 'paye') {
    // Annuler en deux touchers : le premier demande confirmation pendant 4 secondes
    const cle = l.charge_id + '|' + l.mois;
    if (fixes.aConfirmer !== cle) {
      fixes.aConfirmer = cle;
      clearTimeout(fixes.minuteur);
      fixes.minuteur = setTimeout(() => { fixes.aConfirmer = null; dessinerFixes(); }, 4000);
      dessinerFixes();
      return;
    }
    clearTimeout(fixes.minuteur);
    fixes.aConfirmer = null;
    const ok = await demander(client.rpc('annuler_paiement', { p_charge_id: l.charge_id, p_mois: l.mois }));
    if (ok !== null) afficherMessage(l.nom + ' : paiement annulé');
    dessinerFixes();
    return;
  }
  if (l.echeance_type === 'jour') {
    // Prélèvement mensuel : payé au montant prévu, aujourd'hui
    if (l.montant <= 0) { afficherMessage('Montant prévu à 0 € : rien à payer.', true); return; }
    await payer(l, l.montant, aujourdhui());
    return;
  }
  feuillePayer(l); // charge annuelle ou « quand il faut » : on demande le montant de la facture
}

async function payer(l, montant, date) {
  const r = await demander(client.rpc('payer_charge', { p_charge_id: l.charge_id, p_mois: l.mois, p_montant: montant, p_date: date }));
  if (r !== null) afficherMessage(l.nom + ' : payé ' + euros(montant));
  dessinerFixes();
}

function feuillePayer(l) {
  const propose = l.echeance_type === 'mois' ? l.montant * 12 : null;
  const champMontant = el('input', { id: 'payer-montant', inputmode: 'decimal', autocomplete: 'off',
    value: propose ? montantPourChamp(propose) : '' });
  const champDate = el('input', { id: 'payer-date', type: 'date', value: aujourdhui() });
  const erreur = el('p', { class: 'erreur', role: 'alert' });
  const bouton = el('button', { type: 'submit', class: 'bouton-principal' }, 'Payer');
  const formulaire = el('form', { class: 'formulaire' },
    el('p', { class: 'aide', text: l.echeance_type === 'mois'
      ? 'Montant de la facture (proposé : 12 mois de ' + euros(l.montant) + ').'
      : 'Montant de la facture.' }),
    el('label', { for: 'payer-montant', text: 'Montant payé (€)' }), champMontant,
    el('label', { for: 'payer-date', text: 'Date du paiement' }), champDate,
    erreur, bouton);
  formulaire.addEventListener('submit', async (evenement) => {
    evenement.preventDefault();
    const montant = lireMontant(champMontant.value);
    if (!montant) { erreur.textContent = 'Montant invalide (ex. 130 ou 130,50).'; return; }
    if (!champDate.value) { erreur.textContent = 'Choisis une date.'; return; }
    bouton.disabled = true;
    fermerFeuille();
    await payer(l, montant, champDate.value);
  });
  ouvrirFeuille('Payer · ' + l.nom, formulaire);
}

// ---------- Vue Année ----------

const MOIS_COURTS = ['Janv', 'Févr', 'Mars', 'Avr', 'Mai', 'Juin', 'Juil', 'Août', 'Sept', 'Oct', 'Nov', 'Déc'];

// 26540 → "265" (euros arrondis : la grille doit rester lisible)
function eurosRonds(centimes) {
  return Math.round(centimes / 100).toLocaleString('fr-BE');
}

function texteEcheanceCourt(c) {
  const carte = c.carte_id ? ' · carte' : '';
  if (c.echeance_type === 'jour') return (c.echeance_jour ? 'le ' + c.echeance_jour : 'chaque mois') + carte;
  if (c.echeance_type === 'mois') return nomDuMois(c.echeance_mois) + carte;
  return 'quand il faut' + carte;
}

async function dessinerAnnee(c, choix) {
  if (!fixes.annee) fixes.annee = Number(fixes.mois.slice(0, 4));
  const premiereAnnee = Number(fixes.depart.slice(0, 4));
  const derniereAnnee = Number(aujourdhui().slice(0, 4)) + 1;
  const selecteur = el('div', { class: 'selecteur-mois' },
    el('button', { type: 'button', class: 'bouton-icone', 'aria-label': 'Année précédente', disabled: fixes.annee <= premiereAnnee,
      onclick: () => { fixes.annee -= 1; dessinerFixes(); } }, icone('gauche')),
    el('span', { class: 'selecteur-texte annee' }, String(fixes.annee)),
    el('button', { type: 'button', class: 'bouton-icone', 'aria-label': 'Année suivante', disabled: fixes.annee >= derniereAnnee,
      onclick: () => { fixes.annee += 1; dessinerFixes(); } }, icone('droite')));
  const legende = el('div', { class: 'legende' },
    el('span', {}, el('span', { class: 'temoin payee' }), 'Payé'),
    el('span', {}, el('span', { class: 'temoin cote' }), 'Mis de côté'),
    el('span', {}, el('span', { class: 'temoin point' }), 'Échéance'));

  // Toutes les cases depuis le départ jusqu'à décembre de l'année affichée (pour la réserve de fin de mois)
  const fin = fixes.annee + '-12-01';
  const [cases, ajustements] = await Promise.all([
    demanderTout(() => client.from('v_charges_grille').select('*')
      .gte('mois', fixes.depart).lte('mois', fin).order('mois').order('ordre').order('charge_id')),
    demander(client.from('reserve_ajustements').select('date, montant'))
  ]);
  if (cases === null || ajustements === null) return;

  const mois = Array.from({ length: 12 }, (_, i) => fixes.annee + '-' + String(i + 1).padStart(2, '0') + '-01');
  const moisCourant = moisDe(aujourdhui());

  // Une ligne par charge, avec ses cases de l'année
  const charges = new Map();
  cases.filter((x) => x.mois.slice(0, 4) === String(fixes.annee)).forEach((x) => {
    if (!charges.has(x.charge_id)) charges.set(x.charge_id, { info: x, cases: {} });
    charges.get(x.charge_id).cases[x.mois] = x;
  });
  const lignes = [...charges.values()].sort((a, b) => a.info.ordre - b.info.ordre || a.info.charge_id - b.info.charge_id);

  // Totaux par mois et réserve en fin de mois
  const paye = mois.map((m) => cases.filter((x) => x.mois === m && x.etat === 'paye').reduce((s, x) => s + x.montant, 0));
  const cote = mois.map((m) => cases.filter((x) => x.mois === m && x.etat === 'cote').reduce((s, x) => s + x.montant, 0));
  const reserve = mois.map((m) => {
    const finMois = ajouterMois(m, 1); // on compare avec « avant le 1er du mois suivant »
    return ajustements.filter((a) => a.date < finMois).reduce((s, a) => s + a.montant, 0)
      + cases.filter((x) => x.etat === 'cote' && x.mois <= m).reduce((s, x) => s + x.montant, 0)
      - cases.filter((x) => x.etat === 'paye' && x.echeance_type !== 'jour' && x.date_paiement < finMois).reduce((s, x) => s + x.montant, 0);
  });

  // En-tête des colonnes : toucher un mois ouvre la vue Mois
  const entete = el('div', { class: 'grille-ligne grille-entete' },
    el('span', { text: 'Charge' }), el('span', { class: 'a-droite', text: 'Prévu' }), el('span', { text: 'Échéance' }),
    ...mois.map((m, i) => el('button', {
      type: 'button', class: 'grille-mois' + (m === moisCourant ? ' courant' : ''), disabled: !moisPermis(m),
      'aria-label': 'Voir ' + nomMois(m), onclick: () => { fixes.mois = m; fixes.vue = 'mois'; dessinerFixes(); }
    }, MOIS_COURTS[i])));

  const corps = [];
  let groupe = null;
  lignes.forEach((ligne) => {
    if (ligne.info.groupe !== groupe) {
      groupe = ligne.info.groupe;
      corps.push(el('div', { class: 'grille-groupe', text: groupe }));
    }
    const prevu = ligne.cases[moisCourant] || Object.values(ligne.cases)[0];
    corps.push(el('div', { class: 'grille-ligne' },
      el('span', { class: 'grille-nom', text: ligne.info.nom }),
      el('span', { class: 'a-droite chiffre grille-prevu', text: euros(prevu.montant) }),
      el('span', { class: 'grille-echeance', text: texteEcheanceCourt(ligne.info) }),
      ...mois.map((m) => caseAnnee(ligne.cases[m]))));
  });

  const totaux = el('div', { class: 'grille-totaux' },
    ligneTotal('Payé', paye, 'bleu'),
    ligneTotal('Mis de côté', cote, 'orange'),
    ligneTotal('Réserve fin de mois', reserve, '', mois.map((m) => m > moisCourant)));

  c.replaceChildren(
    enTete('Fixes', [choix, selecteur]),
    legende,
    lignes.length === 0
      ? el('p', { class: 'vide', text: 'Aucune charge cette année-là (l\'appli démarre en ' + nomMois(fixes.depart).toLowerCase() + ').' })
      : el('div', { class: 'carte grille-cadre' }, el('div', { class: 'grille' }, entete, ...corps, totaux)));
}

function caseAnnee(x) {
  if (!x) return el('span', { class: 'case vide-case', 'aria-hidden': 'true' });
  const paye = x.etat === 'paye';
  const enAttente = paye && fixes.aConfirmer === x.charge_id + '|' + x.mois;
  return el('button', {
    type: 'button',
    class: 'case ' + (paye ? 'payee' : 'cote') + (enAttente ? ' a-confirmer' : ''),
    'aria-label': x.nom + ', ' + nomMois(x.mois) + ', ' + euros(x.montant) + ', ' + (paye ? 'payé' : 'mis de côté') + (x.mois_echeance ? ', mois de l\'échéance' : ''),
    onclick: () => toucherCase(x)
  }, enAttente ? '?' : eurosRonds(x.montant), x.mois_echeance ? el('span', { class: 'point-echeance', 'aria-hidden': 'true' }) : null);
}

function ligneTotal(titre, valeurs, couleur, previsions = []) {
  return el('div', { class: 'grille-ligne grille-total ' + couleur },
    el('span', { class: 'grille-nom', text: titre }), el('span'), el('span'),
    ...valeurs.map((v, i) => el('span', { class: 'chiffre' + (previsions[i] ? ' prevision' : ''), text: eurosRonds(v) })));
}
