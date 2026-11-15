// Démarrage de l'appli : connexion, barre d'onglets, automatismes, réglages

const NOMS_ONGLETS = { avoirs: 'Avoirs', rentrees: 'Rentrées', depenses: 'Dépenses', fixes: 'Fixes', compteurs: 'Compteurs' };
let ongletActif = 'fixes';
let jourDesAutomatismes = null; // date du dernier lancement des automatismes

// Mémoire de l'appareil (peut être indisponible : on ignore alors l'erreur)
function lireMemoire(cle) { try { return localStorage.getItem(cle); } catch (e) { return null; } }
function ecrireMemoire(cle, valeur) { try { localStorage.setItem(cle, valeur); } catch (e) { /* rien */ } }

function montrer(ecran) {
  document.getElementById('chargement').hidden = ecran !== 'chargement';
  document.getElementById('ecran-connexion').hidden = ecran !== 'connexion';
  document.getElementById('appli').hidden = ecran !== 'appli';
}

// ---------- Connexion ----------

document.getElementById('form-connexion').addEventListener('submit', async (evenement) => {
  evenement.preventDefault();
  const bouton = evenement.target.querySelector('button');
  const erreur = document.getElementById('erreur-connexion');
  erreur.textContent = '';
  bouton.disabled = true;
  const { data, error } = await client.auth.signInWithPassword({
    email: document.getElementById('email').value.trim(),
    password: document.getElementById('motdepasse').value
  });
  bouton.disabled = false;
  if (error) {
    erreur.textContent = /invalid login/i.test(error.message) ? 'E-mail ou mot de passe incorrect.' : texteErreur(error);
    return;
  }
  document.getElementById('motdepasse').value = '';
  await entrer(data.session);
});

async function entrer(session) {
  // Un compte qui existe mais n'est pas dans la liste des membres ne voit rien : on le dit clairement
  const membre = await demander(client.from('membres').select('nom').eq('user_id', session.user.id).maybeSingle());
  if (!membre) {
    montrer('connexion');
    document.getElementById('erreur-connexion').textContent = 'Ce compte n\'a pas accès à l\'appli.';
    await client.auth.signOut({ scope: 'local' });
    return;
  }
  await lancerAutomatismes();
  montrer('appli');
  ongletActif = NOMS_ONGLETS[lireMemoire('depenses_onglet')] ? lireMemoire('depenses_onglet') : 'fixes';
  afficherOnglet(ongletActif);
}

// Argent de poche du 1er, salaires et débits Visa à confirmer : une fois par jour suffit
async function lancerAutomatismes() {
  const jour = aujourdhui();
  if (jourDesAutomatismes === jour) return;
  const crees = await demander(client.rpc('creer_automatismes'));
  if (crees !== null) jourDesAutomatismes = jour;
}

// ---------- Onglets ----------

function afficherOnglet(nom) {
  ongletActif = nom;
  ecrireMemoire('depenses_onglet', nom);
  document.querySelectorAll('.onglets button').forEach((b) => {
    if (b.dataset.onglet === nom) b.setAttribute('aria-current', 'page');
    else b.removeAttribute('aria-current');
  });
  const conteneur = document.getElementById('contenu');
  conteneur.scrollTop = 0;
  if (ONGLETS[nom]) {
    ONGLETS[nom].afficher(conteneur);
  } else {
    conteneur.replaceChildren(enTete(NOMS_ONGLETS[nom]), el('p', { class: 'vide', text: 'Cet onglet arrive bientôt.' }));
  }
}

document.querySelectorAll('.onglets button').forEach((b) => {
  b.addEventListener('click', () => afficherOnglet(b.dataset.onglet));
});

// En revenant sur l'appli un autre jour : on relance les automatismes et on rafraîchit l'onglet
document.addEventListener('visibilitychange', async () => {
  if (document.visibilityState !== 'visible' || document.getElementById('appli').hidden) return;
  if (jourDesAutomatismes !== aujourdhui()) {
    await lancerAutomatismes();
    afficherOnglet(ongletActif);
  }
});

// ---------- Réglages ----------

async function ouvrirReglages() {
  const { data } = await client.auth.getSession();
  const email = data.session ? data.session.user.email : '';
  ouvrirFeuille('Réglages',
    el('div', { class: 'carte' },
      el('p', { style: 'margin:0', text: 'Connecté avec ' + email })),
    el('button', {
      type: 'button', class: 'bouton-secondaire',
      onclick: async () => {
        await client.auth.signOut({ scope: 'local' }); // déconnecte seulement cet appareil
        fermerFeuille();
        montrer('connexion');
      }
    }, 'Se déconnecter de cet appareil')
  );
}

document.getElementById('feuille-fermer').addEventListener('click', fermerFeuille);
document.getElementById('feuille').addEventListener('click', (evenement) => {
  if (evenement.target.id === 'feuille') fermerFeuille(); // toucher le fond ferme la feuille
});

// ---------- Démarrage ----------

(async () => {
  const { data } = await client.auth.getSession();
  if (data.session) await entrer(data.session);
  else montrer('connexion');
})();
