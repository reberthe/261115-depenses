-- 00_test_nettoyage.sql
-- Fin de l'étape 1 : supprime la table de test. Rejouable sans erreur.

drop table if exists public.test_connexion;

-- Vérification : doit afficher 0 ligne
select table_name from information_schema.tables
where table_schema = 'public' and table_name = 'test_connexion';
