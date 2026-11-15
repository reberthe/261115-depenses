-- 06_periode_essai.sql
-- Période d'essai : l'appli démarre au 1er novembre 2026, pour que Régine l'essaie tout de suite.
-- Les montants prévus (charges fixes, argent de poche) qui commençaient à l'ancienne date de départ
-- commencent à la nouvelle. Rejouable : relancé, il ne change plus rien.
-- Au vrai démarrage, un autre script effacera les essais et remettra la bonne date.

do $$
declare
  v_ancienne date;
  v_nouvelle date := date '2026-11-01';
begin
  select p.date_depart into v_ancienne from public.parametres p where p.id = 1;
  if v_ancienne <> v_nouvelle then
    update public.charges_prevu cp set a_partir_de = v_nouvelle
    where cp.a_partir_de = v_ancienne
      and not exists (select 1 from public.charges_prevu x
                      where x.charge_id = cp.charge_id and x.a_partir_de = v_nouvelle);
    update public.montants_mensuels mm set a_partir_de = v_nouvelle
    where mm.a_partir_de = v_ancienne
      and not exists (select 1 from public.montants_mensuels x
                      where x.personne_id = mm.personne_id and x.a_partir_de = v_nouvelle);
    update public.parametres set date_depart = v_nouvelle where id = 1;
  end if;
end;
$$;

-- Vérification : date de départ au 2026-11-01, 56 montants prévus et 2 argents de poche déplacés
select p.date_depart,
       (select count(*) from public.charges_prevu where a_partir_de = p.date_depart) as charges_prevues,
       (select count(*) from public.montants_mensuels where a_partir_de = p.date_depart) as argents_de_poche
from public.parametres p where p.id = 1;
