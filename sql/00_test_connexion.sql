-- 00_test_connexion.sql
-- Étape 1 (tests préalables) : petite table lisible sans compte, pour tester la connexion.
-- Rejouable sans erreur. À supprimer avec 00_test_nettoyage.sql à la fin de l'étape 1.

create table if not exists public.test_connexion (
  id integer primary key,
  message text not null
);

alter table public.test_connexion enable row level security;

-- Lecture seule pour tout le monde (aucune écriture possible)
drop policy if exists "lecture test" on public.test_connexion;
create policy "lecture test" on public.test_connexion
  for select to anon, authenticated
  using (true);

grant select on public.test_connexion to anon, authenticated;

insert into public.test_connexion (id, message)
values (1, 'Connexion à Supabase OK')
on conflict (id) do nothing;

-- Vérification : doit afficher une ligne
select * from public.test_connexion;
