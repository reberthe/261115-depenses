-- 04_actions.sql
-- Les actions qui écrivent à plusieurs endroits d'un coup : tout réussit, ou rien n'est écrit.
-- Rejouable sans erreur. Elles s'exécutent avec les droits de la personne connectée (règles d'accès comprises).

-- Payer une charge fixe pour un mois : la case passe à « payé » et une ligne sort du compte de prélèvement
-- (ou s'ajoute au relevé de la carte, si la charge est payée par carte).
create or replace function public.payer_charge(p_charge_id bigint, p_mois date, p_montant bigint,
                                               p_date date default null)
returns bigint
language plpgsql set search_path = '' as $$
declare
  v_compte bigint;
  v_carte bigint;
  v_nom text;
  v_case bigint;
  v_operation bigint;
  v_date date := coalesce(p_date, prive.aujourdhui());
begin
  if p_montant is null or p_montant <= 0 then
    raise exception 'Montant invalide';
  end if;
  select ch.compte_id, ch.carte_id, ch.nom into v_compte, v_carte, v_nom
  from public.charges ch where ch.id = p_charge_id;
  if v_nom is null then
    raise exception 'Charge introuvable';
  end if;

  insert into public.charges_mois (charge_id, mois, montant, etat, date_paiement)
  values (p_charge_id, date_trunc('month', p_mois)::date, p_montant, 'paye', v_date)
  on conflict (charge_id, mois) do update
    set montant = excluded.montant, etat = 'paye', date_paiement = excluded.date_paiement
    where public.charges_mois.etat = 'cote'
  returning id into v_case;
  if v_case is null then
    raise exception 'Ce mois est déjà payé';
  end if;

  insert into public.operations (date, montant, type, compte_id, carte_id, charge_mois_id, note)
  values (v_date, -p_montant, 'fixe', v_compte, v_carte, v_case, v_nom)
  returning id into v_operation;
  return v_operation;
end;
$$;

-- Annuler un paiement : la ligne du compte disparaît, la case repasse à « mis de côté ».
create or replace function public.annuler_paiement(p_charge_id bigint, p_mois date)
returns void
language plpgsql set search_path = '' as $$
declare v_case bigint;
begin
  select cm.id into v_case from public.charges_mois cm
  where cm.charge_id = p_charge_id and cm.mois = date_trunc('month', p_mois)::date and cm.etat = 'paye';
  if v_case is null then
    raise exception 'Ce mois n''est pas payé';
  end if;
  delete from public.operations o where o.charge_mois_id = v_case;
  update public.charges_mois set etat = 'cote', date_paiement = null where id = v_case;
end;
$$;

-- Remboursement reçu : la rentrée est créée et la ligne « On me doit » est marquée reçue.
create or replace function public.recevoir_remboursement(p_id bigint, p_compte_id bigint, p_date date default null)
returns bigint
language plpgsql set search_path = '' as $$
declare
  v_libelle text;
  v_montant bigint;
  v_operation bigint;
  v_date date := coalesce(p_date, prive.aujourdhui());
begin
  select r.libelle, r.montant into v_libelle, v_montant
  from public.remboursements r where r.id = p_id and r.recu_le is null;
  if v_libelle is null then
    raise exception 'Remboursement introuvable ou déjà reçu';
  end if;
  insert into public.operations (date, montant, type, compte_id, note)
  values (v_date, v_montant, 'rentree', p_compte_id, v_libelle)
  returning id into v_operation;
  update public.remboursements set recu_le = v_date, operation_id = v_operation where id = p_id;
  return v_operation;
end;
$$;

-- Vérification mensuelle d'un compte : on note le solde de la banque ;
-- s'il y a un écart, un ajustement daté le corrige. Renvoie l'écart en centimes.
create or replace function public.verifier_solde(p_compte_id bigint, p_solde_banque bigint,
                                                 p_date date default null, p_note text default null)
returns bigint
language plpgsql set search_path = '' as $$
declare
  v_date date := coalesce(p_date, prive.aujourdhui());
  v_calcule bigint;
  v_ecart bigint;
  v_operation bigint;
begin
  if not exists (select 1 from public.comptes c where c.id = p_compte_id) then
    raise exception 'Compte introuvable';
  end if;
  select coalesce(sum(m.montant), 0) into v_calcule
  from public.v_mouvements_comptes m where m.compte_id = p_compte_id and m.date_effet <= v_date;
  v_ecart := p_solde_banque - v_calcule;
  if v_ecart <> 0 then
    insert into public.operations (date, montant, type, compte_id, note)
    values (v_date, v_ecart, 'ajustement', p_compte_id, coalesce(nullif(trim(p_note), ''), 'Vérification du solde'))
    returning id into v_operation;
  end if;
  insert into public.verifications (compte_id, date, solde_banque, solde_calcule, operation_id)
  values (p_compte_id, v_date, p_solde_banque, v_calcule, v_operation);
  return v_ecart;
end;
$$;

-- Automatismes, appelés à chaque ouverture de l'appli. Ils rattrapent les mois manqués
-- et ne créent jamais de doublon (clé unique), même si l'iPad et l'iPhone s'ouvrent en même temps.
--   1. argent de poche versé le 1er du mois ;
--   2. salaires « à confirmer » le 1er du mois (montant du dernier salaire normal confirmé) ;
--   3. débit Visa « à confirmer » pour chaque relevé clôturé, daté du 1er du mois suivant.
-- Pour 1 et 2, la clé est gardée dans "automatismes" : une ligne supprimée n'est jamais recréée.
-- Pour 3, un débit supprimé par erreur est recréé (un relevé clôturé doit toujours être débité).
-- Renvoie le nombre de lignes créées.
create or replace function public.creer_automatismes()
returns integer
language plpgsql set search_path = '' as $$
declare
  v_mois_courant date := date_trunc('month', prive.aujourdhui())::date;
  v_n integer;
  v_total integer := 0;
begin
  -- 1. Argent de poche
  with candidats as (
    select m.mois, mm.montant, p.id as personne_id,
           'versement:' || p.id || ':' || to_char(m.mois, 'YYYY-MM') as cle
    from public.personnes p
    join public.v_mois m on m.mois <= v_mois_courant
     and (p.debut is null or m.mois >= date_trunc('month', p.debut))
     and (p.fin is null or m.mois <= p.fin)
    join lateral (
      select x.montant from public.montants_mensuels x
      where x.personne_id = p.id and x.a_partir_de <= m.mois
      order by x.a_partir_de desc limit 1
    ) mm on mm.montant > 0
  ),
  nouvelles as (
    insert into public.automatismes (cle) select cle from candidats
    on conflict (cle) do nothing returning cle
  )
  insert into public.operations (date, montant, type, personne_id, auto_cle, note)
  select c.mois, c.montant, 'versement', c.personne_id, c.cle, 'Versement du 1er du mois'
  from candidats c join nouvelles n on n.cle = c.cle
  on conflict do nothing;
  get diagnostics v_n = row_count;
  v_total := v_total + v_n;

  -- 2. Salaires à confirmer (seulement s'il n'y a encore aucun salaire normal ce mois-là)
  with candidats as (
    select m.mois, dernier.montant, s.compte_defaut_id, s.id as source_id,
           'salaire:' || s.id || ':' || to_char(m.mois, 'YYYY-MM') as cle
    from public.sources s
    join public.v_mois m on m.mois <= v_mois_courant
    join lateral (
      select o.montant from public.operations o
      where o.source_id = s.id and o.type = 'rentree' and o.statut = 'confirme'
        and coalesce(o.nature, 'normal') = 'normal' and o.date < m.mois
      order by o.date desc, o.id desc limit 1
    ) dernier on true
    where s.est_salaire and s.actif and s.compte_defaut_id is not null
      and not exists (
        select 1 from public.operations o2
        where o2.source_id = s.id and o2.type = 'rentree' and coalesce(o2.nature, 'normal') = 'normal'
          and o2.date >= m.mois and o2.date < m.mois + interval '1 month'
      )
  ),
  nouvelles as (
    insert into public.automatismes (cle) select cle from candidats
    on conflict (cle) do nothing returning cle
  )
  insert into public.operations (date, montant, type, statut, compte_id, source_id, nature, auto_cle)
  select c.mois, c.montant, 'rentree', 'a_confirmer', c.compte_defaut_id, c.source_id, 'normal', c.cle
  from candidats c join nouvelles n on n.cle = c.cle
  on conflict do nothing;
  get diagnostics v_n = row_count;
  v_total := v_total + v_n;

  -- 3. Débits Visa à confirmer pour les relevés clôturés
  insert into public.operations (date, montant, type, statut, compte_id, carte_id, releve, auto_cle, note)
  select (r.releve + interval '1 month')::date, -r.total, 'debit_visa', 'a_confirmer', r.compte_debit_id,
         r.carte_id, r.releve, 'visa:' || r.carte_id || ':' || to_char(r.releve, 'YYYY-MM'),
         'Débit du relevé ' || r.carte
  from public.v_releves_visa r
  where r.etat = 'a_debiter' and r.debit_id is null and r.total > 0
  on conflict do nothing;
  get diagnostics v_n = row_count;
  v_total := v_total + v_n;

  return v_total;
end;
$$;

-- Droits : seulement pour les membres connectés (les règles d'accès s'appliquent en plus)
revoke all on function public.payer_charge(bigint, date, bigint, date) from public, anon;
revoke all on function public.annuler_paiement(bigint, date) from public, anon;
revoke all on function public.recevoir_remboursement(bigint, bigint, date) from public, anon;
revoke all on function public.verifier_solde(bigint, bigint, date, text) from public, anon;
revoke all on function public.creer_automatismes() from public, anon;
grant execute on function public.payer_charge(bigint, date, bigint, date) to authenticated;
grant execute on function public.annuler_paiement(bigint, date) to authenticated;
grant execute on function public.recevoir_remboursement(bigint, bigint, date) to authenticated;
grant execute on function public.verifier_solde(bigint, bigint, date, text) to authenticated;
grant execute on function public.creer_automatismes() to authenticated;
