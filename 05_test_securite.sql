-- 05_test_securite.sql
-- Test de sécurité, à lancer dans le SQL Editor en entier. Il se fait passer pour :
--   - un membre (le premier de la liste "membres") ;
--   - un compte qui existe mais n'est pas membre (le compte de test) ;
--   - un visiteur non connecté.
-- Il n'écrit rien : toutes les tentatives d'écriture doivent échouer ou ne toucher aucune ligne
-- (seuls les automatismes lancés par le membre peuvent créer des lignes, comme à l'ouverture de l'appli).
-- Aucun identifiant ni nom dans ce fichier : il peut aller sur GitHub.
-- Résultat attendu : toutes les lignes à « true » dans la colonne ok.

drop table if exists pg_temp.resultats;
create temp table resultats (n serial primary key, test text not null, ok boolean not null, obtenu text);

-- Exécute une requête en se faisant passer pour quelqu'un, renvoie la 1re valeur ou 'ERREUR'
create or replace function pg_temp.en_tant_que(p_uid uuid, p_sql text) returns text
language plpgsql as $$
declare v text;
begin
  if p_uid is null then
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform set_config('request.jwt.claim.sub', '', true);
  else
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', p_uid::text, true);
  end if;
  begin
    execute p_sql into v;
    v := coalesce(v, 'vide');
  exception when others then
    v := 'ERREUR';
  end;
  perform set_config('role', 'none', true);
  return v;
end;
$$;

do $$
declare
  v_membre uuid := (select m.user_id from public.membres m order by m.nom limit 1);
  v_intrus uuid := (select u.id from auth.users u
                    where u.id not in (select m.user_id from public.membres m) limit 1);
  v_charge bigint := (select min(id) from public.charges);
  t text;
  r text;
begin
  insert into resultats (test, ok, obtenu) values
    ('il y a au moins un membre', v_membre is not null, coalesce(v_membre::text, 'aucun')),
    ('il existe un compte de test (pas membre)', v_intrus is not null, coalesce(v_intrus::text, 'à créer dans Authentication → Users'));

  -- 1. Le membre voit les données et toutes les vues
  r := pg_temp.en_tant_que(v_membre, 'select (count(*) > 0)::text from public.comptes');
  insert into resultats (test, ok, obtenu) values ('membre : voit les comptes', r = 'true', r);
  r := pg_temp.en_tant_que(v_membre, 'select (count(*) > 0)::text from public.charges');
  insert into resultats (test, ok, obtenu) values ('membre : voit les charges', r = 'true', r);
  foreach t in array array['v_mois', 'v_mouvements_comptes', 'v_soldes_comptes', 'v_soldes_personnes',
                           'v_personnes_mois', 'v_charges_grille', 'v_reserve_fixes', 'v_releves_visa',
                           'v_differe_en_attente', 'v_argent_libre', 'v_placements', 'v_consommations']
  loop
    r := pg_temp.en_tant_que(v_membre, format('select count(*)::text from public.%I', t));
    insert into resultats (test, ok, obtenu) values ('membre : lit ' || t, r <> 'ERREUR', r);
  end loop;
  r := pg_temp.en_tant_que(v_membre, 'select creer_automatismes()::text');
  insert into resultats (test, ok, obtenu) values ('membre : lance les automatismes', r <> 'ERREUR', r);
  r := pg_temp.en_tant_que(v_membre, format('insert into public.membres values (%L, %L) returning 1', v_intrus, 'Intrus'));
  insert into resultats (test, ok, obtenu) values ('membre : ne peut pas ajouter un membre', r = 'ERREUR', r);
  r := pg_temp.en_tant_que(v_membre, format(
    'insert into public.operations (date, montant, type, compte_id, categorie_id, cree_par)
     values (current_date, -1, %L, (select min(id) from public.comptes), (select min(id) from public.categories), %L) returning 1',
    'depense', v_intrus));
  insert into resultats (test, ok, obtenu) values ('membre : ne peut pas écrire « cree_par » lui-même', r = 'ERREUR', r);

  -- 2. Le compte de test (pas membre) ne voit rien et ne peut rien écrire
  foreach t in array array['parametres', 'membres', 'comptes', 'cartes', 'personnes', 'montants_mensuels',
                           'categories', 'sources', 'charges', 'charges_prevu', 'charges_mois',
                           'reserve_ajustements', 'operations', 'automatismes', 'remboursements',
                           'verifications', 'placements', 'placements_valeurs', 'placements_mouvements',
                           'compteurs', 'releves']
  loop
    r := pg_temp.en_tant_que(v_intrus, format('select count(*)::text from public.%I', t));
    insert into resultats (test, ok, obtenu) values ('compte de test : 0 ligne dans ' || t, r = '0', r);
  end loop;
  r := pg_temp.en_tant_que(v_intrus, 'select argent_libre::text from public.v_argent_libre');
  insert into resultats (test, ok, obtenu) values ('compte de test : argent libre à 0', r = '0', r);
  r := pg_temp.en_tant_que(v_intrus, 'select count(*)::text from public.v_charges_grille');
  insert into resultats (test, ok, obtenu) values ('compte de test : grille des fixes vide', r = '0', r);
  r := pg_temp.en_tant_que(v_intrus, $q$insert into public.categories (nom) values ('Intrus') returning 1$q$);
  insert into resultats (test, ok, obtenu) values ('compte de test : ne peut pas créer de catégorie', r = 'ERREUR', r);
  r := pg_temp.en_tant_que(v_intrus, $q$insert into public.operations (date, montant, type, compte_id, categorie_id)
                                      values (current_date, -1, 'depense', 1, 1) returning 1$q$);
  insert into resultats (test, ok, obtenu) values ('compte de test : ne peut pas créer d''opération', r = 'ERREUR', r);
  r := pg_temp.en_tant_que(v_intrus, $q$with u as (update public.charges set nom = 'Intrus' returning 1) select count(*)::text from u$q$);
  insert into resultats (test, ok, obtenu) values ('compte de test : ne modifie aucune charge', r = '0', r);
  r := pg_temp.en_tant_que(v_intrus, $q$with d as (delete from public.charges returning 1) select count(*)::text from d$q$);
  insert into resultats (test, ok, obtenu) values ('compte de test : ne supprime aucune charge', r = '0', r);
  r := pg_temp.en_tant_que(v_intrus, format('select payer_charge(%s, date_trunc(%L, current_date)::date, 100)::text', v_charge, 'month'));
  insert into resultats (test, ok, obtenu) values ('compte de test : ne peut pas payer une charge', r = 'ERREUR', r);
  r := pg_temp.en_tant_que(v_intrus, 'select creer_automatismes()::text');
  insert into resultats (test, ok, obtenu) values ('compte de test : automatismes sans effet', r = '0', r);

  -- 3. Le visiteur non connecté n'a accès à rien
  r := pg_temp.en_tant_que(null, 'select count(*)::text from public.operations');
  insert into resultats (test, ok, obtenu) values ('visiteur : opérations refusées', r = 'ERREUR', r);
  r := pg_temp.en_tant_que(null, 'select count(*)::text from public.membres');
  insert into resultats (test, ok, obtenu) values ('visiteur : membres refusés', r = 'ERREUR', r);
  r := pg_temp.en_tant_que(null, 'select argent_libre::text from public.v_argent_libre');
  insert into resultats (test, ok, obtenu) values ('visiteur : argent libre refusé', r = 'ERREUR', r);
  r := pg_temp.en_tant_que(null, 'select creer_automatismes()::text');
  insert into resultats (test, ok, obtenu) values ('visiteur : automatismes refusés', r = 'ERREUR', r);
  r := pg_temp.en_tant_que(null, format('select payer_charge(%s, date_trunc(%L, current_date)::date, 100)::text', v_charge, 'month'));
  insert into resultats (test, ok, obtenu) values ('visiteur : payer une charge refusé', r = 'ERREUR', r);
end;
$$;

-- Résumé en première ligne, puis le détail
select 'RÉSUMÉ' as test, (count(*) filter (where ok) = count(*)) as ok,
       count(*) filter (where ok) || ' / ' || count(*) || ' réussis' as obtenu, 0 as n
from resultats
union all
select test, ok, obtenu, n from resultats
order by n;
