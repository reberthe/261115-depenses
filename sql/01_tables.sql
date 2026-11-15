-- 01_tables.sql
-- Structure de la base : tables, contraintes, index et déclencheurs.
-- Rejouable sans erreur. Montants en centimes (12,40 € = 1240). Dates locales de Bruxelles en "date".
-- Aucune donnée personnelle ici : elles sont dans donnees/ (hors GitHub).

create schema if not exists prive;

-- ============ Réglages généraux ============

create table if not exists public.parametres (
  id smallint primary key default 1 check (id = 1),
  date_depart date not null default date '2027-01-01' check (extract(day from date_depart) = 1),
  modifie_le timestamptz not null default now()
);
insert into public.parametres (id) values (1) on conflict (id) do nothing;

create table if not exists public.membres (
  user_id uuid primary key references auth.users (id) on delete cascade,
  nom text not null check (length(trim(nom)) between 1 and 40)
);

-- ============ Listes (réglables dans l'appli) ============

-- Comptes en banque, poches (liquide, Livre, Vinted, chèques-repas…) et bons d'achat
create table if not exists public.comptes (
  id bigint generated always as identity primary key,
  nom text not null unique check (length(trim(nom)) between 1 and 60),
  type text not null check (type in ('banque', 'poche', 'bon')),
  dans_argent_libre boolean not null default true,
  ordre integer not null default 0,
  actif boolean not null default true
);

-- Cartes de crédit : à relevé (Visa) ou à débit différé (Visa Carrefour)
create table if not exists public.cartes (
  id bigint generated always as identity primary key,
  nom text not null unique check (length(trim(nom)) between 1 and 60),
  mode text not null check (mode in ('releve', 'differe')),
  jour_fin smallint check (jour_fin between 1 and 28),
  delai_jours smallint check (delai_jours between 0 and 60),
  compte_debit_id bigint not null references public.comptes (id),
  ordre integer not null default 0,
  actif boolean not null default true,
  constraint carte_coherente check (
    (mode = 'releve' and jour_fin is not null and delai_jours is null)
    or (mode = 'differe' and delai_jours is not null and jour_fin is null)
  )
);

-- Colonnes Personnes : enveloppes (Jérôme, Régine, Vacances) et dettes (Lola, Emma, Annette)
create table if not exists public.personnes (
  id bigint generated always as identity primary key,
  nom text not null unique check (length(trim(nom)) between 1 and 40),
  type text not null check (type in ('enveloppe', 'dette')),
  debut date,
  fin date,
  ordre integer not null default 0,
  check (fin is null or debut is null or fin >= debut)
);

-- Montant versé tout seul le 1er du mois (argent de poche), à partir d'un mois donné
create table if not exists public.montants_mensuels (
  id bigint generated always as identity primary key,
  personne_id bigint not null references public.personnes (id) on delete cascade,
  a_partir_de date not null check (extract(day from a_partir_de) = 1),
  montant bigint not null check (montant between 0 and 100000000),
  unique (personne_id, a_partir_de)
);

-- Catégories des dépenses de la maison
create table if not exists public.categories (
  id bigint generated always as identity primary key,
  nom text not null unique check (length(trim(nom)) between 1 and 40),
  ordre integer not null default 0,
  actif boolean not null default true
);

-- Sources des rentrées
create table if not exists public.sources (
  id bigint generated always as identity primary key,
  nom text not null check (length(trim(nom)) between 1 and 40),
  groupe text not null check (groupe in ('jerome', 'regine', 'divers')),
  est_salaire boolean not null default false,
  compte_defaut_id bigint references public.comptes (id),
  ordre integer not null default 0,
  actif boolean not null default true,
  unique (nom, groupe)
);

-- ============ Fixes ============

create table if not exists public.charges (
  id bigint generated always as identity primary key,
  nom text not null check (length(trim(nom)) between 1 and 60),
  groupe text not null check (length(trim(groupe)) between 1 and 40),
  echeance_type text not null check (echeance_type in ('jour', 'mois', 'libre')),
  echeance_jour smallint check (echeance_jour between 1 and 31),
  echeance_mois smallint check (echeance_mois between 1 and 12),
  compte_id bigint not null references public.comptes (id),
  fin date check (fin is null or extract(day from fin) = 1), -- 1er mois où la charge n'existe plus
  ordre integer not null default 0,
  constraint echeance_coherente check (
    (echeance_type = 'jour' and echeance_jour is not null and echeance_mois is null)
    or (echeance_type = 'mois' and echeance_mois is not null)
    or (echeance_type = 'libre' and echeance_jour is null and echeance_mois is null)
  )
);

-- Montant prévu par mois, à partir d'un mois donné (« à partir de ce mois »)
create table if not exists public.charges_prevu (
  id bigint generated always as identity primary key,
  charge_id bigint not null references public.charges (id) on delete cascade,
  a_partir_de date not null check (extract(day from a_partir_de) = 1),
  montant bigint not null check (montant between 0 and 100000000),
  unique (charge_id, a_partir_de)
);

-- Une case de la grille, seulement quand elle diffère du prévu : payée, ou montant changé
create table if not exists public.charges_mois (
  id bigint generated always as identity primary key,
  charge_id bigint not null references public.charges (id) on delete cascade,
  mois date not null check (extract(day from mois) = 1),
  montant bigint not null check (montant between 0 and 100000000),
  etat text not null default 'cote' check (etat in ('cote', 'paye')),
  date_paiement date,
  cree_par uuid default auth.uid() references auth.users (id) on delete set null,
  cree_le timestamptz not null default now(),
  modifie_le timestamptz not null default now(),
  unique (charge_id, mois),
  check ((etat = 'paye') = (date_paiement is not null))
);

-- Réserve des fixes : montant de départ et ajustements datés
create table if not exists public.reserve_ajustements (
  id bigint generated always as identity primary key,
  date date not null,
  montant bigint not null check (abs(montant) <= 100000000000),
  type text not null check (type in ('depart', 'ajustement')),
  note text check (note is null or length(note) <= 200),
  cree_par uuid default auth.uid() references auth.users (id) on delete set null,
  cree_le timestamptz not null default now(),
  modifie_le timestamptz not null default now()
);
create unique index if not exists reserve_un_seul_depart on public.reserve_ajustements (type) where type = 'depart';

-- ============ Le grand livre : tout ce qui bouge de l'argent ============
-- montant > 0 : entrée ; montant < 0 : sortie.

create table if not exists public.operations (
  id bigint generated always as identity primary key,
  date date not null,
  montant bigint not null check (montant <> 0 and abs(montant) <= 100000000000),
  type text not null check (type in ('depense', 'rentree', 'virement', 'retrait', 'fixe', 'debit_visa', 'versement', 'depart', 'ajustement')),
  statut text not null default 'confirme' check (statut in ('confirme', 'a_confirmer')),
  compte_id bigint references public.comptes (id),
  carte_id bigint references public.cartes (id),
  releve date check (releve is null or extract(day from releve) = 1),
  personne_id bigint references public.personnes (id),
  categorie_id bigint references public.categories (id),
  source_id bigint references public.sources (id),
  nature text check (nature in ('normal', 'pecule', 'treizieme', 'prime')),
  groupe uuid,
  charge_mois_id bigint unique references public.charges_mois (id) on delete cascade,
  auto_cle text unique,
  note text check (note is null or length(note) <= 200),
  cree_par uuid default auth.uid() references auth.users (id) on delete set null,
  cree_le timestamptz not null default now(),
  modifie_le timestamptz not null default now(),
  constraint operation_coherente check (
    case type
      -- Onglet Dépenses : payé par un compte/une poche OU une carte, pour une personne OU une catégorie
      when 'depense' then num_nonnulls(compte_id, carte_id) = 1
        and num_nonnulls(personne_id, categorie_id) = 1 and source_id is null
      -- Onglet Rentrées : arrive sur un compte, avec une source ou une note (rentrée ponctuelle)
      when 'rentree' then compte_id is not null and carte_id is null and montant > 0
        and personne_id is null and categorie_id is null and num_nonnulls(source_id, note) >= 1
      -- Virement ou retrait : deux lignes liées par le même groupe
      when 'virement' then compte_id is not null and carte_id is null and groupe is not null
        and num_nonnulls(personne_id, categorie_id, source_id) = 0
      when 'retrait' then compte_id is not null and carte_id is null and groupe is not null
        and num_nonnulls(personne_id, categorie_id, source_id) = 0
      -- Fixe payé : toujours lié à sa case de la grille
      when 'fixe' then compte_id is not null and carte_id is null and charge_mois_id is not null and montant < 0
        and num_nonnulls(personne_id, categorie_id, source_id) = 0
      -- Débit du relevé Visa sur le compte
      when 'debit_visa' then compte_id is not null and carte_id is not null and releve is not null and montant < 0
        and num_nonnulls(personne_id, categorie_id, source_id) = 0
      -- Argent de poche versé dans une enveloppe (aucun compte ne bouge)
      when 'versement' then personne_id is not null and compte_id is null and carte_id is null and montant > 0
        and num_nonnulls(categorie_id, source_id) = 0
      -- Montant de départ ou ajustement : sur un compte OU une personne
      else num_nonnulls(compte_id, personne_id) = 1 and carte_id is null
        and num_nonnulls(categorie_id, source_id) = 0
    end
  ),
  check (statut = 'confirme' or type in ('rentree', 'debit_visa')),
  check (nature is null or type = 'rentree'),
  check (releve is null or carte_id is not null),
  check (charge_mois_id is null or type = 'fixe')
);

create index if not exists operations_date on public.operations (date);
create index if not exists operations_compte on public.operations (compte_id);
create index if not exists operations_carte_releve on public.operations (carte_id, releve);
create index if not exists operations_personne on public.operations (personne_id);
create index if not exists operations_categorie on public.operations (categorie_id);
create index if not exists operations_source on public.operations (source_id);
create unique index if not exists un_debit_par_releve on public.operations (carte_id, releve) where type = 'debit_visa';

-- Automatismes déjà faits (argent de poche, salaires à confirmer) :
-- une ligne supprimée par Régine n'est jamais recréée.
create table if not exists public.automatismes (
  cle text primary key check (length(cle) <= 60),
  cree_le timestamptz not null default now()
);

-- ============ Avoirs ============

create table if not exists public.remboursements (
  id bigint generated always as identity primary key,
  libelle text not null check (length(trim(libelle)) between 1 and 60),
  montant bigint not null check (montant between 1 and 100000000),
  date date not null,
  recu_le date,
  operation_id bigint unique references public.operations (id) on delete set null,
  cree_par uuid default auth.uid() references auth.users (id) on delete set null,
  cree_le timestamptz not null default now(),
  modifie_le timestamptz not null default now()
);

create table if not exists public.verifications (
  id bigint generated always as identity primary key,
  compte_id bigint not null references public.comptes (id) on delete cascade,
  date date not null,
  solde_banque bigint not null,
  solde_calcule bigint not null,
  operation_id bigint references public.operations (id) on delete set null,
  cree_par uuid default auth.uid() references auth.users (id) on delete set null,
  cree_le timestamptz not null default now()
);

create table if not exists public.placements (
  id bigint generated always as identity primary key,
  nom text not null unique check (length(trim(nom)) between 1 and 60),
  ordre integer not null default 0,
  actif boolean not null default true
);

create table if not exists public.placements_valeurs (
  id bigint generated always as identity primary key,
  placement_id bigint not null references public.placements (id) on delete cascade,
  mois date not null check (extract(day from mois) = 1),
  valeur bigint not null check (valeur between 0 and 100000000000),
  frais bigint not null default 0 check (frais between 0 and 100000000),
  cree_par uuid default auth.uid() references auth.users (id) on delete set null,
  cree_le timestamptz not null default now(),
  modifie_le timestamptz not null default now(),
  unique (placement_id, mois)
);

create table if not exists public.placements_mouvements (
  id bigint generated always as identity primary key,
  placement_id bigint not null references public.placements (id) on delete cascade,
  date date not null,
  montant bigint not null check (montant <> 0 and abs(montant) <= 100000000000),
  note text check (note is null or length(note) <= 200),
  cree_par uuid default auth.uid() references auth.users (id) on delete set null,
  cree_le timestamptz not null default now(),
  modifie_le timestamptz not null default now()
);

-- ============ Compteurs ============

-- Un « compteur » = un index à relever (eau, gaz, ou un des 4 registres de l'électricité)
create table if not exists public.compteurs (
  id bigint generated always as identity primary key,
  nom text not null unique check (length(trim(nom)) between 1 and 40),
  groupe text not null check (length(trim(groupe)) between 1 and 40),
  unite text not null check (length(trim(unite)) between 1 and 10),
  sens text not null default 'preleve' check (sens in ('preleve', 'injecte')),
  periode text check (periode in ('jour', 'nuit')),
  ordre integer not null default 0,
  actif boolean not null default true
);

create table if not exists public.releves (
  id bigint generated always as identity primary key,
  compteur_id bigint not null references public.compteurs (id) on delete cascade,
  date date not null,
  valeur numeric(14, 3) not null check (valeur >= 0),
  nouveau_compteur boolean not null default false,
  cree_par uuid default auth.uid() references auth.users (id) on delete set null,
  cree_le timestamptz not null default now(),
  modifie_le timestamptz not null default now(),
  unique (compteur_id, date)
);

-- ============ Déclencheurs ============

-- Date de modification remplie par la base
create or replace function prive.maj_modifie_le() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.modifie_le := now();
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['parametres', 'charges_mois', 'reserve_ajustements', 'operations', 'remboursements',
                           'placements_valeurs', 'placements_mouvements', 'releves']
  loop
    execute format('create or replace trigger maj_modifie_le before update on public.%I
                    for each row execute function prive.maj_modifie_le()', t);
  end loop;
end;
$$;

-- Relevé Visa rempli par la base d'après la date : jusqu'au jour de fin inclus → relevé du mois, sinon du mois suivant.
-- On peut le changer à la main ; il est recalculé si la date ou la carte change.
create or replace function prive.remplir_releve() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_mode text;
  v_jour_fin smallint;
begin
  if new.type <> 'depense' or new.carte_id is null then
    if new.type <> 'debit_visa' then new.releve := null; end if;
    return new;
  end if;
  select c.mode, c.jour_fin into v_mode, v_jour_fin from public.cartes c where c.id = new.carte_id;
  if v_mode = 'differe' then
    new.releve := null;
  elsif new.releve is null
     or (tg_op = 'UPDATE' and (new.date <> old.date or new.carte_id <> old.carte_id)
         and new.releve is not distinct from old.releve) then
    new.releve := case when extract(day from new.date) <= v_jour_fin
                       then date_trunc('month', new.date)::date
                       else (date_trunc('month', new.date) + interval '1 month')::date end;
  end if;
  return new;
end;
$$;

create or replace trigger remplir_releve before insert or update on public.operations
  for each row execute function prive.remplir_releve();
