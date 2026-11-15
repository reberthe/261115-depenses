-- 03_calculs.sql
-- Les calculs, sous forme de vues : soldes, reports, réserve des fixes, relevés Visa, argent libre, compteurs.
-- Rejouable sans erreur. Les vues respectent les règles d'accès (security_invoker) :
-- un compte qui n'est pas membre n'y voit rien. Tous les montants sont en centimes.
-- "Aujourd'hui" = la date du jour à Bruxelles.

-- Liste des mois : du mois de départ à décembre de l'année prochaine
create or replace view public.v_mois with (security_invoker = true) as
select gs::date as mois
from public.parametres p,
     generate_series(p.date_depart::timestamp,
                     date_trunc('year', prive.aujourdhui()) + interval '23 months',
                     interval '1 month') gs
where p.id = 1;

-- Ce qui touche réellement chaque compte, et à quelle date :
--   - lignes sur un compte (sauf achats par carte) ;
--   - débit du relevé Visa ;
--   - achats Visa Carrefour, débités "délai" jours après l'achat.
-- Les achats Visa ne touchent le compte qu'au débit du relevé.
create or replace view public.v_mouvements_comptes with (security_invoker = true) as
select o.id as operation_id, o.compte_id, o.date as date_effet, o.montant, o.type, o.note
from public.operations o
where o.statut = 'confirme' and o.compte_id is not null
  and (o.carte_id is null or o.type = 'debit_visa')
union all
select o.id, c.compte_debit_id, o.date + c.delai_jours, o.montant, o.type, o.note
from public.operations o
join public.cartes c on c.id = o.carte_id
where o.statut = 'confirme' and o.type in ('depense', 'fixe') and c.mode = 'differe';

-- Solde de chaque compte, poche ou bon aujourd'hui
create or replace view public.v_soldes_comptes with (security_invoker = true) as
select c.id as compte_id, c.nom, c.type, c.dans_argent_libre, c.ordre, c.actif,
       coalesce(sum(m.montant) filter (where m.date_effet <= prive.aujourdhui()), 0)::bigint as solde
from public.comptes c
left join public.v_mouvements_comptes m on m.compte_id = c.id
group by c.id;

-- Solde de chaque personne aujourd'hui.
-- Enveloppe : ce qui reste (négatif = dépassée). Dette : négatif = la personne doit cet argent.
create or replace view public.v_soldes_personnes with (security_invoker = true) as
select p.id as personne_id, p.nom, p.type, p.ordre,
       coalesce(sum(o.montant) filter (where o.date <= prive.aujourdhui() and o.statut = 'confirme'), 0)::bigint as solde
from public.personnes p
left join public.operations o on o.personne_id = p.id
group by p.id;

-- Colonnes Personnes, mois par mois : report, +, −, solde en fin de mois
create or replace view public.v_personnes_mois with (security_invoker = true) as
select p.id as personne_id, p.nom, p.type, p.ordre, m.mois,
       coalesce(sum(o.montant) filter (where o.date < m.mois), 0)::bigint as report,
       coalesce(sum(o.montant) filter (where o.date >= m.mois and o.date < m.mois + interval '1 month'
                                         and o.montant > 0), 0)::bigint as plus,
       coalesce(sum(-o.montant) filter (where o.date >= m.mois and o.date < m.mois + interval '1 month'
                                          and o.montant < 0), 0)::bigint as moins,
       coalesce(sum(o.montant) filter (where o.date < m.mois + interval '1 month'), 0)::bigint as solde_fin
from public.personnes p
cross join public.v_mois m
left join public.operations o on o.personne_id = p.id and o.statut = 'confirme'
where (p.debut is null or m.mois >= date_trunc('month', p.debut))
  and (p.fin is null or m.mois <= p.fin)
group by p.id, m.mois;

-- Grille des fixes : chaque charge × chaque mois.
-- Une case non enregistrée prend le montant prévu de ce mois-là et l'état « mis de côté ».
create or replace view public.v_charges_grille with (security_invoker = true) as
select ch.id as charge_id, ch.nom, ch.groupe, ch.ordre, ch.echeance_type, ch.echeance_jour, ch.echeance_mois,
       ch.compte_id, m.mois,
       coalesce(cm.montant, pr.montant)::bigint as montant,
       coalesce(cm.etat, 'cote') as etat,
       cm.id as charge_mois_id,
       cm.date_paiement,
       (ch.echeance_type = 'mois' and extract(month from m.mois) = ch.echeance_mois) as mois_echeance,
       ch.carte_id -- ajoutée à la fin : une vue existante ne peut gagner des colonnes qu'à la fin
from public.charges ch
cross join public.v_mois m
left join public.charges_mois cm on cm.charge_id = ch.id and cm.mois = m.mois
left join lateral (
  select cp.montant from public.charges_prevu cp
  where cp.charge_id = ch.id and cp.a_partir_de <= m.mois
  order by cp.a_partir_de desc limit 1
) pr on true
where (ch.fin is null or m.mois < ch.fin)
  and (cm.id is not null or pr.montant is not null);

-- Réserve des fixes = départ et ajustements
--   + tout ce qui est « mis de côté » jusqu'au mois en cours
--   − les charges annuelles ou « quand il faut » déjà payées.
-- (Une charge mensuelle payée sort simplement de la réserve, puisqu'elle n'est plus « mise de côté ».)
create or replace view public.v_reserve_fixes with (security_invoker = true) as
select (
    coalesce((select sum(r.montant) from public.reserve_ajustements r
              where r.date <= prive.aujourdhui()), 0)
  + coalesce((select sum(g.montant) from public.v_charges_grille g
              where g.etat = 'cote' and g.mois <= date_trunc('month', prive.aujourdhui())), 0)
  - coalesce((select sum(g.montant) from public.v_charges_grille g
              where g.etat = 'paye' and g.echeance_type <> 'jour' and g.date_paiement <= prive.aujourdhui()), 0)
  )::bigint as reserve;

-- Relevés des cartes Visa : période, total, et état
--   en_cours  : le relevé qui se remplit maintenant ;
--   a_debiter : clôturé, débit pas encore confirmé ;
--   debite    : débit confirmé ;  futur : achats datés plus tard.
create or replace view public.v_releves_visa with (security_invoker = true) as
with cartes_r as (
  select c.id, c.nom, c.jour_fin, c.compte_debit_id,
         case when extract(day from prive.aujourdhui()) <= c.jour_fin
              then date_trunc('month', prive.aujourdhui())::date
              else (date_trunc('month', prive.aujourdhui()) + interval '1 month')::date end as releve_en_cours
  from public.cartes c where c.mode = 'releve'
),
achats as (
  select o.carte_id, o.releve, sum(-o.montant)::bigint as total, count(*)::int as nb
  from public.operations o
  where o.type in ('depense', 'fixe') and o.releve is not null and o.statut = 'confirme'
  group by o.carte_id, o.releve
)
select c.id as carte_id, c.nom as carte, c.compte_debit_id, a.releve, a.total, a.nb,
       ((a.releve - interval '1 month')::date + c.jour_fin) as du,
       (a.releve + c.jour_fin - 1) as au,
       d.id as debit_id, d.statut as debit_statut, -d.montant as debit_montant, d.date as debit_date,
       case when d.statut = 'confirme' then 'debite'
            when a.releve = c.releve_en_cours then 'en_cours'
            when a.releve < c.releve_en_cours then 'a_debiter'
            else 'futur' end as etat
from cartes_r c
join achats a on a.carte_id = c.id
left join public.operations d on d.type = 'debit_visa' and d.carte_id = c.id and d.releve = a.releve;

-- Visa Carrefour : achats pas encore débités (débit "délai" jours après l'achat)
create or replace view public.v_differe_en_attente with (security_invoker = true) as
select c.id as carte_id, c.nom as carte,
       coalesce(sum(-o.montant), 0)::bigint as total,
       count(o.id)::int as nb,
       max(o.date + c.delai_jours) as jusqu_au
from public.cartes c
left join public.operations o
  on o.carte_id = c.id and o.type in ('depense', 'fixe') and o.statut = 'confirme'
 and o.date <= prive.aujourdhui() and o.date + c.delai_jours > prive.aujourdhui()
where c.mode = 'differe'
group by c.id;

-- Argent libre = ce qu'on a − ce qui est déjà promis
create or replace view public.v_argent_libre with (security_invoker = true) as
with a as (
  select
    coalesce((select sum(solde) from public.v_soldes_comptes where dans_argent_libre), 0)::bigint as comptes,
    coalesce((select sum(-solde) from public.v_soldes_personnes where type = 'dette'), 0)::bigint as dettes,
    coalesce((select sum(montant) from public.remboursements where recu_le is null), 0)::bigint as remboursements,
    coalesce((select reserve from public.v_reserve_fixes), 0)::bigint as reserve,
    coalesce((select sum(solde) from public.v_soldes_personnes where type = 'enveloppe'), 0)::bigint as enveloppes,
    coalesce((select sum(total) from public.v_releves_visa where etat in ('en_cours', 'a_debiter')), 0)::bigint as visa,
    coalesce((select sum(total) from public.v_differe_en_attente), 0)::bigint as differe
)
select comptes, dettes, remboursements,
       comptes + dettes + remboursements as ce_qu_on_a,
       reserve, enveloppes, visa, differe,
       reserve + enveloppes + visa + differe as deja_promis,
       (comptes + dettes + remboursements) - (reserve + enveloppes + visa + differe) as argent_libre
from a;

-- Placements : dernière valeur connue de chacun
create or replace view public.v_placements with (security_invoker = true) as
select p.id as placement_id, p.nom, p.ordre, p.actif, v.mois, v.valeur, v.frais
from public.placements p
left join lateral (
  select pv.mois, pv.valeur, pv.frais from public.placements_valeurs pv
  where pv.placement_id = p.id order by pv.mois desc limit 1
) v on true;

-- Compteurs : consommation entre deux relevés datés, et par jour.
-- Pas de consommation au premier relevé ni quand le compteur a été remplacé.
create or replace view public.v_consommations with (security_invoker = true) as
select r.id as releve_id, r.compteur_id, c.nom, c.groupe, c.unite, c.sens, c.periode, c.ordre,
       r.date, r.valeur, r.nouveau_compteur,
       lag(r.date) over w as date_precedente,
       lag(r.valeur) over w as valeur_precedente,
       case when r.nouveau_compteur then null else r.valeur - lag(r.valeur) over w end as conso,
       r.date - lag(r.date) over w as jours,
       case when r.nouveau_compteur or r.date = lag(r.date) over w then null
            else round((r.valeur - lag(r.valeur) over w) / (r.date - lag(r.date) over w), 3) end as par_jour,
       (not r.nouveau_compteur and r.valeur < lag(r.valeur) over w) as anomalie
from public.releves r
join public.compteurs c on c.id = r.compteur_id
window w as (partition by r.compteur_id order by r.date);

-- Droits : lecture seule, pour les membres connectés seulement
revoke all on public.v_mois, public.v_mouvements_comptes, public.v_soldes_comptes, public.v_soldes_personnes,
  public.v_personnes_mois, public.v_charges_grille, public.v_reserve_fixes, public.v_releves_visa,
  public.v_differe_en_attente, public.v_argent_libre, public.v_placements, public.v_consommations
  from anon, authenticated;
grant select on public.v_mois, public.v_mouvements_comptes, public.v_soldes_comptes, public.v_soldes_personnes,
  public.v_personnes_mois, public.v_charges_grille, public.v_reserve_fixes, public.v_releves_visa,
  public.v_differe_en_attente, public.v_argent_libre, public.v_placements, public.v_consommations
  to authenticated;
