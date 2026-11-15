-- 02_securite.sql
-- Qui voit et modifie quoi. Rejouable sans erreur. À lancer après 01_tables.sql.
-- Règle : seuls les comptes listés dans "membres" voient et écrivent, et ils voient tout (un seul foyer).
-- Un visiteur non connecté (anon) n'a accès à rien.

-- Schéma privé : invisible pour l'API, utilisable par les règles
revoke all on schema prive from public;
grant usage on schema prive to authenticated;

-- Est-ce que la personne connectée est membre ?
-- "security definer" : lit la table membres sans dépendre de ses propres règles.
create or replace function prive.est_membre() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.membres m where m.user_id = (select auth.uid()));
$$;
revoke all on function prive.est_membre() from public, anon;
grant execute on function prive.est_membre() to authenticated;

-- Date du jour à Bruxelles (utilisée par les calculs)
create or replace function prive.aujourdhui() returns date
language sql stable set search_path = '' as $$
  select (now() at time zone 'Europe/Brussels')::date;
$$;
revoke all on function prive.aujourdhui() from public, anon;
grant execute on function prive.aujourdhui() to authenticated;

-- RLS sur chaque table + une règle « membres seulement »
do $$
declare t text;
begin
  foreach t in array array['parametres', 'comptes', 'cartes', 'personnes', 'montants_mensuels', 'categories',
                           'sources', 'charges', 'charges_prevu', 'charges_mois', 'reserve_ajustements',
                           'operations', 'automatismes', 'remboursements', 'verifications', 'placements', 'placements_valeurs',
                           'placements_mouvements', 'compteurs', 'releves']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "membres seulement" on public.%I', t);
    execute format('create policy "membres seulement" on public.%I for all to authenticated
                    using ((select prive.est_membre())) with check ((select prive.est_membre()))', t);
  end loop;
end;
$$;

-- La liste des membres : lecture seule depuis l'appli (on la change dans le SQL Editor)
alter table public.membres enable row level security;
drop policy if exists "membres seulement" on public.membres;
create policy "membres seulement" on public.membres for select to authenticated
  using ((select prive.est_membre()));

-- Droits : on enlève tout, puis on donne seulement le nécessaire
revoke all on all tables in schema public from anon, authenticated;
grant select on all tables in schema public to authenticated;

-- Listes et réglages : modifiables
grant insert, update, delete on public.comptes, public.cartes, public.personnes, public.montants_mensuels,
  public.categories, public.sources, public.charges, public.charges_prevu, public.placements, public.compteurs
  to authenticated;
grant update (date_depart) on public.parametres to authenticated;

-- Tables avec « qui / quand » : ces colonnes sont remplies par la base, jamais par l'appli
grant insert (date, montant, type, statut, compte_id, carte_id, releve, personne_id, categorie_id, source_id,
              nature, groupe, charge_mois_id, auto_cle, note),
      update (date, montant, type, statut, compte_id, carte_id, releve, personne_id, categorie_id, source_id,
              nature, groupe, charge_mois_id, note),
      delete on public.operations to authenticated;
grant insert (cle) on public.automatismes to authenticated;
grant insert (charge_id, mois, montant, etat, date_paiement),
      update (montant, etat, date_paiement), delete on public.charges_mois to authenticated;
grant insert (date, montant, type, note), update (date, montant, note), delete
  on public.reserve_ajustements to authenticated;
grant insert (libelle, montant, date, recu_le, operation_id), update (libelle, montant, date, recu_le, operation_id),
      delete on public.remboursements to authenticated;
grant insert (compte_id, date, solde_banque, solde_calcule, operation_id), delete
  on public.verifications to authenticated;
grant insert (placement_id, mois, valeur, frais), update (valeur, frais), delete
  on public.placements_valeurs to authenticated;
grant insert (placement_id, date, montant, note), update (date, montant, note), delete
  on public.placements_mouvements to authenticated;
grant insert (compteur_id, date, valeur, nouveau_compteur), update (date, valeur, nouveau_compteur), delete
  on public.releves to authenticated;
