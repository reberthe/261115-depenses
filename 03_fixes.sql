-- donnees/03_fixes.sql
-- ⚠️ Fichier privé : ne JAMAIS le mettre sur GitHub (le dépôt est public).
-- Les charges fixes reprises du fichier Fixes 2026, vérifiées par Régine le 15/11/2026.
-- Montant prévu par mois = celui de décembre 2026, valable dès la date de départ.
-- Rejouable sans erreur : une charge qui existe déjà (même nom) n'est ni dupliquée ni écrasée,
-- sauf Netflix, qui passe sur la Visa (payée via PayPal).
-- À lancer après sql/01 (version du 15/11 : jour facultatif, charges payées par carte) et donnees/02_listes.sql.
-- Types : 'jour' = prélevée chaque mois ; 'mois' = annuelle, payée un mois connu ;
--         'libre' = mise de côté, payée quand il faut (dont l'eau, facturée tous les 3 mois).

with liste (groupe, nom, echeance_type, echeance_jour, echeance_mois, compte, carte, ordre) as (values
  ('Maison', 'Précompte immobilier', 'mois', null::smallint, 10::smallint, 'Crelan commun', null, 1),
  ('Maison', 'Prêt hypothécaire 1', 'jour', 23::smallint, null::smallint, 'Crelan commun', null, 2),
  ('Maison', 'Prêt hypothécaire 2', 'jour', 16::smallint, null::smallint, 'Crelan commun', null, 3),
  ('Maison', 'Assurance SRD 1', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 4),
  ('Maison', 'Assurance SRD 2', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 5),
  ('Maison', 'Assurance SRD 3', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 6),
  ('Maison', 'Assurance SRD 4', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 7),
  ('Maison', 'Taxe poubelles', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 8),
  ('Maison', 'Gaz', 'jour', 29::smallint, null::smallint, 'Crelan commun', null, 9),
  ('Maison', 'Eau', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 10),
  ('Maison', 'Électricité', 'jour', 29::smallint, null::smallint, 'Crelan commun', null, 11),
  ('Maison', 'Vitres', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 12),
  ('Maison', 'Entretien chaudière', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 13),
  ('Maison', 'Entretien adoucisseur', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 14),
  ('Maison', 'Entretien airco', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 15),
  ('Maison', 'Verisure', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 16),
  ('Maison', 'Assurance incendie + RC fam.', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 17),
  ('Maison', 'Assurance annulation vacances', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 18),
  ('Maison', 'Assurance juridique DAS', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 19),
  ('Télé & téléphone', 'Voo', 'jour', 26::smallint, null::smallint, 'Crelan commun', null, 20),
  ('Télé & téléphone', 'Netflix', 'jour', null::smallint, null::smallint, null, 'Visa', 21),
  ('Télé & téléphone', 'Apple One', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 22),
  ('Télé & téléphone', 'iCloud', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 23),
  ('Télé & téléphone', 'Antivirus+VPN', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 24),
  ('Télé & téléphone', 'Amazon prémium', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 25),
  ('Télé & téléphone', 'GSM', 'jour', 26::smallint, null::smallint, 'Crelan commun', null, 26),
  ('Voitures', 'Mini · Assurance', 'jour', 28::smallint, null::smallint, 'Crelan commun', null, 27),
  ('Voitures', 'Mini · Entretiens et réparations', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 28),
  ('Voitures', 'Mini · Taxe circulation', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 29),
  ('Voitures', 'Mini · Europ assistance', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 30),
  ('Voitures', 'Mini · Provision', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 31),
  ('Voitures', '240i · Assurance', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 32),
  ('Voitures', '240i · Entretiens et réparations', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 33),
  ('Voitures', '240i · Taxe circulation', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 34),
  ('Voitures', '240i · Prêt', 'jour', 25::smallint, null::smallint, 'Crelan commun', null, 35),
  ('Voitures', 'MX5 · Prêt Mazda', 'jour', 1::smallint, null::smallint, 'Crelan commun', null, 36),
  ('Divers', 'Épargne pension', 'jour', 1::smallint, null::smallint, 'Crelan commun', null, 37),
  ('Divers', 'Épargne Crelan', 'jour', 1::smallint, null::smallint, 'Crelan commun', null, 38),
  ('Divers', 'Épargne Solidaris filles', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 39),
  ('Divers', 'Delta Lloyd', 'jour', 1::smallint, null::smallint, 'Crelan commun', null, 40),
  ('Divers', 'Syndicat', 'jour', 1::smallint, null::smallint, 'Crelan commun', null, 41),
  ('Divers', 'UNSP', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 42),
  ('Divers', 'Mutuelle 1', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 43),
  ('Divers', 'Mutuelle 2', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 44),
  ('Divers', 'Soins (Dane, Effi & Sylvie)', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 45),
  ('Divers', 'Lucas', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 46),
  ('Divers', 'Les enfants du Vietnam', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 47),
  ('Divers', 'Frais gestion Axa', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 48),
  ('Divers', 'Frais gestion CA', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 49),
  ('Divers', 'Cadeaux divers', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 50),
  ('Divers', 'Provision travaux', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 51),
  ('Divers', 'Remplacement électro', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 52),
  ('Divers', 'Vacances', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 53),
  ('Divers', 'Provision Lola', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 54),
  ('Divers', 'Provision Emma', 'libre', null::smallint, null::smallint, 'Crelan commun', null, 55),
  ('Divers', 'Cadeaux aux filles', 'jour', null::smallint, null::smallint, 'Crelan commun', null, 56)
)
insert into public.charges (nom, groupe, echeance_type, echeance_jour, echeance_mois, compte_id, carte_id, ordre)
select l.nom, l.groupe, l.echeance_type, l.echeance_jour, l.echeance_mois, co.id, ca.id, l.ordre
from liste l
left join public.comptes co on co.nom = l.compte
left join public.cartes ca on ca.nom = l.carte
where not exists (select 1 from public.charges ch where ch.nom = l.nom);

-- Netflix : payée par la Visa (si le script a déjà été lancé avec Crelan commun)
update public.charges
set carte_id = (select id from public.cartes where nom = 'Visa'), compte_id = null
where nom = 'Netflix' and carte_id is null;

with liste (nom, montant) as (values
  ('Précompte immobilier', 22000),
  ('Prêt hypothécaire 1', 18175),
  ('Prêt hypothécaire 2', 42051),
  ('Assurance SRD 1', 542),
  ('Assurance SRD 2', 500),
  ('Assurance SRD 3', 1583),
  ('Assurance SRD 4', 1233),
  ('Taxe poubelles', 1083),
  ('Gaz', 35000),
  ('Eau', 3500),
  ('Électricité', 20000),
  ('Vitres', 5000),
  ('Entretien chaudière', 830),
  ('Entretien adoucisseur', 1140),
  ('Entretien airco', 2500),
  ('Verisure', 5936),
  ('Assurance incendie + RC fam.', 9360),
  ('Assurance annulation vacances', 1300),
  ('Assurance juridique DAS', 3000),
  ('Voo', 12599),
  ('Netflix', 1699),
  ('Apple One', 2795),
  ('iCloud', 999),
  ('Antivirus+VPN', 1500),
  ('Amazon prémium', 600),
  ('GSM', 2600),
  ('Mini · Assurance', 9695),
  ('Mini · Entretiens et réparations', 10000),
  ('Mini · Taxe circulation', 4542),
  ('Mini · Europ assistance', 1600),
  ('Mini · Provision', 30000),
  ('240i · Assurance', 20000),
  ('240i · Entretiens et réparations', 10000),
  ('240i · Taxe circulation', 9200),
  ('240i · Prêt', 73406),
  ('MX5 · Prêt Mazda', 37431),
  ('Épargne pension', 19051),
  ('Épargne Crelan', 50000),
  ('Épargne Solidaris filles', 800),
  ('Delta Lloyd', 10000),
  ('Syndicat', 2160),
  ('UNSP', 1750),
  ('Mutuelle 1', 1140),
  ('Mutuelle 2', 1140),
  ('Soins (Dane, Effi & Sylvie)', 10000),
  ('Lucas', 42000),
  ('Les enfants du Vietnam', 2500),
  ('Frais gestion Axa', 300),
  ('Frais gestion CA', 300),
  ('Cadeaux divers', 15000),
  ('Provision travaux', 20000),
  ('Remplacement électro', 7500),
  ('Vacances', 30000),
  ('Provision Lola', 30000),
  ('Provision Emma', 30000),
  ('Cadeaux aux filles', 10000)
)
insert into public.charges_prevu (charge_id, a_partir_de, montant)
select ch.id, (select date_depart from public.parametres where id = 1), l.montant
from liste l
join public.charges ch on ch.nom = l.nom
on conflict (charge_id, a_partir_de) do nothing;

-- Vérification : 56 charges (34 mensuelles, 1 annuelle avec un mois, 21 « quand il faut »),
-- un total prévu de 6870.40 € par mois, et 1 charge payée par carte (Netflix)
select ch.echeance_type, count(*) as charges, count(ch.carte_id) as par_carte,
       sum(cp.montant) / 100.0 as euros_par_mois
from public.charges ch
join public.charges_prevu cp on cp.charge_id = ch.id
group by rollup (ch.echeance_type)
order by ch.echeance_type nulls last;
