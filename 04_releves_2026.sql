-- donnees/04_releves_2026.sql
-- ⚠️ Fichier privé : ne JAMAIS le mettre sur GitHub (le dépôt est public).
-- Index des compteurs 2026 repris de Mensuelles 2026, datés du 1er de chaque mois.
-- Septembre manque dans l'Excel : octobre couvre donc deux mois (marqué dans l'appli).
-- Rejouable sans erreur : un relevé qui existe déjà (même compteur, même date) n'est pas écrasé.

with liste (compteur, date, valeur) as (values
  ('Eau', date '2026-01-01', 947),
  ('Gaz', date '2026-01-01', 79505),
  ('Prélevé jour (1.8.1)', date '2026-01-01', 4633.26),
  ('Prélevé nuit (1.8.2)', date '2026-01-01', 5481.24),
  ('Injecté jour (2.8.1)', date '2026-01-01', 2967.87),
  ('Injecté nuit (2.8.2)', date '2026-01-01', 1112.63),
  ('Eau', date '2026-02-01', 952),
  ('Gaz', date '2026-02-01', 80016.5),
  ('Prélevé jour (1.8.1)', date '2026-02-01', 4870.48),
  ('Prélevé nuit (1.8.2)', date '2026-02-01', 5685.61),
  ('Injecté jour (2.8.1)', date '2026-02-01', 2968.48),
  ('Injecté nuit (2.8.2)', date '2026-02-01', 1148.62),
  ('Eau', date '2026-03-01', 955.5),
  ('Gaz', date '2026-03-01', 80343),
  ('Prélevé jour (1.8.1)', date '2026-03-01', 5036.54),
  ('Prélevé nuit (1.8.2)', date '2026-03-01', 5829.03),
  ('Injecté jour (2.8.1)', date '2026-03-01', 2971.45),
  ('Injecté nuit (2.8.2)', date '2026-03-01', 1235.54),
  ('Eau', date '2026-04-01', 960),
  ('Gaz', date '2026-04-01', 80674),
  ('Prélevé jour (1.8.1)', date '2026-04-01', 5212.43),
  ('Prélevé nuit (1.8.2)', date '2026-04-01', 5965.59),
  ('Injecté jour (2.8.1)', date '2026-04-01', 3001.59),
  ('Injecté nuit (2.8.2)', date '2026-04-01', 1568.47),
  ('Eau', date '2026-05-01', 965),
  ('Gaz', date '2026-05-01', 80837),
  ('Prélevé jour (1.8.1)', date '2026-05-01', 5348.98),
  ('Prélevé nuit (1.8.2)', date '2026-05-01', 6116.8),
  ('Injecté jour (2.8.1)', date '2026-05-01', 3124.07),
  ('Injecté nuit (2.8.2)', date '2026-05-01', 1926.03),
  ('Eau', date '2026-06-01', 968.5),
  ('Gaz', date '2026-06-01', 80931),
  ('Prélevé jour (1.8.1)', date '2026-06-01', 5632.54),
  ('Prélevé nuit (1.8.2)', date '2026-06-01', 6490.78),
  ('Injecté jour (2.8.1)', date '2026-06-01', 3189.73),
  ('Injecté nuit (2.8.2)', date '2026-06-01', 2137.06),
  ('Eau', date '2026-07-01', 973.5),
  ('Gaz', date '2026-07-01', 80969.5),
  ('Prélevé jour (1.8.1)', date '2026-07-01', 5913.95),
  ('Prélevé nuit (1.8.2)', date '2026-07-01', 6788.86),
  ('Injecté jour (2.8.1)', date '2026-07-01', 3248.7),
  ('Injecté nuit (2.8.2)', date '2026-07-01', 2297.11),
  ('Eau', date '2026-08-01', 982),
  ('Gaz', date '2026-08-01', 80989),
  ('Prélevé jour (1.8.1)', date '2026-08-01', 6125.37),
  ('Prélevé nuit (1.8.2)', date '2026-08-01', 6998.05),
  ('Injecté jour (2.8.1)', date '2026-08-01', 3377.93),
  ('Injecté nuit (2.8.2)', date '2026-08-01', 2542.09),
  ('Eau', date '2026-10-01', 1000),
  ('Gaz', date '2026-10-01', 81063),
  ('Prélevé jour (1.8.1)', date '2026-10-01', 6621.51),
  ('Prélevé nuit (1.8.2)', date '2026-10-01', 7459.51),
  ('Injecté jour (2.8.1)', date '2026-10-01', 3479.32),
  ('Injecté nuit (2.8.2)', date '2026-10-01', 2964.53),
  ('Eau', date '2026-11-01', 1004.5),
  ('Gaz', date '2026-11-01', 81237),
  ('Prélevé jour (1.8.1)', date '2026-11-01', 6923.09),
  ('Prélevé nuit (1.8.2)', date '2026-11-01', 7711.21),
  ('Injecté jour (2.8.1)', date '2026-11-01', 3400.99),
  ('Injecté nuit (2.8.2)', date '2026-11-01', 3106.29)
)
insert into public.releves (compteur_id, date, valeur)
select c.id, l.date, l.valeur
from liste l
join public.compteurs c on c.nom = l.compteur
on conflict (compteur_id, date) do nothing;

-- Vérification : 60 relevés ; les lignes « anomalie = true » sont des index plus bas que le relevé d'avant
select nom, count(*) as releves, min(date) as premier, max(date) as dernier,
       bool_or(anomalie) as anomalie
from public.v_consommations
group by nom, ordre
order by ordre;
