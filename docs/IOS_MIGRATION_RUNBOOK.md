# iOS Migration Runbook (Canopy v0.0)

Date: 2026-03-09  
Repo: `JardinForet`  
Reference plan: `docs/IOS_CANOPY_REWRITE_PLAN.md`

## Objectif de ce fichier

Ce runbook est la checklist operationnelle que je dois relire **au debut de chaque lot** pour eviter le drift pendant la migration iOS vers Canopy.

## Regles non negociables (a relire avant chaque modification)

1. Source de verite schema = `jardin-supabase` (migrations SQL + `schema/*.yaml`).
2. Ne pas modifier les vues SwiftUI en premier.
3. Pas de patch legacy dans le coeur v2: `RemoteDTO != LocalRecord != UIModel`.
4. Toute donnee metier doit etre scopee par `site_id`.
5. Soft delete standard = `deleted_at`.
6. Offline-first obligatoire: ecriture locale puis sync.
7. Commits petits, lisibles, par lot.
8. Avant chaque lot data/sync: regenerer le contrat Swift depuis `jardin-supabase/schema/entities.yaml`:
   - `./scripts/generate_canopy_schema_swift.py`
   - verifier `JardinForet/Data/Remote/CanopySchemaContract.generated.swift`
   - le generateur lit aussi `jardin-supabase/supabase/migrations` pour les champs core (`site_members`) afin d'eviter les constantes hardcodees.

## Lot 1 (current)

But:
- Poser les fondations techniques sans casser l'UX.

Livrables:
- [ ] Document d'architecture valide et maintenu.
- [ ] Module LocalV2 (schema + migrator) en parallele du legacy.
- [ ] Module Remote Canopy read-only (DTO + client).
- [ ] UI adapters vers `GardenTaxon` / `GardenPlant`.
- [ ] Feature flag Store pour selectionner read-path (`legacy` par defaut).
- [ ] Aucune vue SwiftUI modifiee.

Definition of done:
- App compile.
- Behaviour par defaut identique (legacy).
- Code v2 present, isolable, activable sans toucher les vues.

## Lot 2 (current)

But:
- Mettre en place le **pull Canopy -> projection locale v2** avec resolution de `site_id`.

Livrables:
- [x] Client remote Canopy read-only branche sur tables v0.0 (`site_members`, `species_private`, `individuals`).
- [x] Projection SQLite v2 (upsert idempotent).
- [x] Context courant `current_site_id` en local v2.
- [x] Watermarks de pull (`sync_state_v2`) pour incremental pull.
- [x] `GardenStore` branche sur pipeline v2 quand `GARDEN_READ_BACKEND=v2`.

## Lot 3 (current)

But:
- Enforcer schema-as-code dans l'app iOS et poser la base outbox push v2.

Livrables:
- [x] Contrat iOS genere directement depuis `jardin-supabase/schema/entities.yaml`.
- [x] Suppression du contrat JSON hardcode.
- [x] Client remote et projection locale qui consomment des constantes generees.
- [x] Outbox v2 exploitable (`pending -> done/failed`) et push engine initialise.

## Lot 4 (current)

But:
- Migrer la couche vues principales sur le read-path v2 sans retomber sur legacy.

Livrables:
- [x] En mode `GARDEN_READ_BACKEND=v2`, lectures Store forcees sur projection locale v2 (pas de fallback legacy pour les listes/details).
- [x] Vues principales species/plants passees en mode lecture seule v2 (actions create/edit/delete legacy masquees).
- [x] Branchement formulaires/editions species/individuals sur outbox v2.

## Lot 5 (current)

But:
- Retablir la compatibilite UI en lecture v2 (cultivars + metadata individu) pour reduire les regressions visibles.

Livrables:
- [x] Pull/projection locale des `cultivars`.
- [x] `fetchSpeciesDetail` v2 retourne les cultivars associes.
- [x] Adapter v2 hydrate les metadata individu (`micro_site`, `exposure_local`, `soil_local`, acquisition, etc.).

## Lot 6 (current)

But:
- Supprimer le risque de drift legacy sur le module plantes.

Livrables:
- [x] Mutations `cultivars` en v2 (`create/update/delete`) via outbox.
- [x] Mutations `individuals` en v2 relient maintenant `cultivar_id` (plus seulement metadata legacy).
- [x] Backend de lecture force en v2 (legacy backend desactive par policy de migration).
- [x] Sync legacy desactivee en runtime (v2 requis).

## Invariants de migration

1. Les IDs v2 sont des UUID cote data; tout int ID legacy en UI est transitoire via adapter.
2. `site_id` est obligatoire dans les couches Remote et LocalV2.
3. Aucune requete Supabase legacy (`species`, `plants`, `cultivars`) dans les nouveaux modules v2.
4. Toute nouvelle ecriture v2 devra passer par outbox (Lot 2+).

## Journal des decisions

- 2026-03-09: Decision confirmee de creer une base locale v2 propre (`jardin_v2.db`) plutot que tordre `jardin.db`.
- 2026-03-09: Hives gardees en mode transitoire tant que migrations Canopy hives/colonies ne sont pas publiees.
