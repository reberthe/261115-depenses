// Onglet Fixes — version provisoire (squelette) : vérifie seulement la connexion à la base.
// La vraie version (vues Mois et Année) arrive à la partie suivante.

ONGLETS.fixes = {
  async afficher(conteneur) {
    conteneur.replaceChildren(enTete('Fixes'), el('p', { class: 'vide', text: 'Chargement…' }));
    const charges = await demander(client.from('charges').select('id', { count: 'exact', head: false }));
    const parametres = await demander(client.from('parametres').select('date_depart').single());
    if (charges === null || parametres === null) return;
    conteneur.replaceChildren(
      enTete('Fixes'),
      el('div', { class: 'carte' },
        el('p', { text: 'Connexion OK ✓' }),
        el('p', { text: charges.length + ' charges fixes dans la base.' }),
        el('p', { text: 'Départ de l\'appli : ' + nomMois(parametres.date_depart) + '.' }),
        el('p', { class: 'vide', text: 'Les vues Mois et Année arrivent à la prochaine partie.' })
      )
    );
  }
};
