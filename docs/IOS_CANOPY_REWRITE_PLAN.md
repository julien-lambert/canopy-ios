# iOS Canopy Rewrite Plan (v0.0)

Date: 2026-03-09
Scope: `JardinForet` iOS/macOS app migration to Canopy schema (`jardin-supabase` source of truth).

## 1) Resume du probleme

L'app iOS actuelle est offline-first mais repose sur un modele legacy:

- SQLite locale legacy (`species`, `plants`, `cultivars`, `varieties`, `photos`, `plant_events`, `hives`, etc.).
- DTO reseau historiques `SpeciesDTO`, `PlantDTO`, `CultivarDTO` en IDs `Int`.
- Sync Supabase sur tables legacy (`species`, `plants`, `cultivars`) sans `site_id`.

Le modele produit Canopy v0.0 est different:

- IDs metier en `uuid`.
- Scope multi-tenant obligatoire via `site_id`.
- Domaine plantes cible: `species_global`, `species_private`, `cultivars`, `individuals`, `individual_photos`, `observations`.
- Soft-delete via `deleted_at`.
- RLS membre/site stricte.

Conclusion: migration de noyau data necessaire (pas un patch).

## 2) Sources de verite (ordre)

1. `jardin-supabase/supabase/migrations/*.sql` (verite executable DB)
2. `jardin-supabase/schema/entities.yaml`
3. `jardin-supabase/schema/types.yaml`
4. `jardin-supabase/schema/modules.yaml`
5. `jardin-supabase/docs/FRONTEND_HANDOFF_v0_0.md`
6. `jardin-supabase/docs/NOTICE_v0_0_core_canopy.md`
7. `jardin-supabase/docs/SCHEMA_AS_CODE.md`

Regle: aucune signature runtime iOS ne doit diverger de ces sources.

## 3) Audit de l'existant iOS

## 3.1 Couplage actuel des couches

- `GardenDTO.swift`
  - Melange DTO remote + records SQLite + UI models.
  - DTO legacy `SpeciesDTO/PlantDTO/CultivarDTO` mappes sur tables legacy.
  - IDs `Int` partout (non alignes Canopy).

- `GardenDatabase.swift`
  - Utilise `jardin.db` bundle copy -> Documents.
  - Ecrit/lit directement tables legacy (`species`, `plants`, `cultivars`).
  - Pas de systeme de migration DB (`DatabaseMigrator` absent).
  - Logique business + persistence + merge sync dans le meme fichier.

- `GardenSyncService.swift`
  - Supabase sans auth utilisateur/membership.
  - Utilise tables legacy distantes: `species`, `plants`, `cultivars`.
  - Pas de `site_id`, pas de scoping multi-tenant.

- `GardenStore.swift`
  - Melange orchestration UI + sync + gestion markers + calls DB.
  - Lock DB manuel + pipeline sync directement dans le store.

- Vues SwiftUI `View/*`
  - Bien decouplees du SQL direct (elles passent par `GardenStore`).
  - Mais dependance forte aux vieux ViewModels (`GardenPlant`, `GardenTaxon`) et IDs `Int`.

## 3.2 Etat de la base locale legacy (`jardin.db`)

Tables:
- `species`, `cultivars`, `varieties`, `plants`, `photos`, `plant_events`
- `hives`, `hive_colonies`, `hive_inspections`, `hive_harvests`
- `species_usage`, `usage_types`, `strata_types`, `soil_types`, `exposure_types`
- `sync_state`

Volumetrie observee:
- `species=50`, `cultivars=15`, `varieties=0`, `plants=57`
- `photos=0`, `plant_events=0`
- `hives=3`, `hive_colonies=3`

Constats:
- IDs `INTEGER` legacy + `uuid TEXT` secondaire.
- Soft-delete legacy en `deleted INTEGER`.
- `status` plants heterogene (`planté`, `vivant`, `générique`, `à_surveiller`, etc.).
- Aucun `site_id`.

## 3.3 Divergences critiques avec Canopy

1. Table names legacy vs Canopy:
- legacy `plants` != Canopy `individuals`
- legacy `species` != Canopy `species_private/species_global`

2. Identifiants:
- legacy `Int` vs Canopy `UUID`.

3. Multi-tenant:
- absence de `site_id` local/runtime actuel.

4. Sync:
- marqueurs texte simples + pull/push par `updated_at` sans queue d'operations.

5. RLS/Auth:
- client anon-only actuel incompatible avec policies Canopy site-scoped.

6. Types:
- tags `TEXT csv` legacy vs `text[]` Canopy.
- soft delete `deleted` vs `deleted_at`.

## 4) Cartographie legacy -> Canopy

## 4.1 Domaine plantes

- `species` -> `species_private` (principal) + enrichissement `species_global` optionnel
- `cultivars` + `varieties` -> `cultivars`
- `plants` -> `individuals`
- `photos` -> `individual_photos`
- `plant_events` -> `observations` (`target_type='individual'`)
- `species_usage` + `usage_types` -> `species_private.tags` / `uses`
- `soil_types` / `exposure_types` / `strata_types` -> defaults/config site (pas tables runtime directes)

## 4.2 Domaine ruches

- `hives` -> futur `hives`
- `hive_colonies` -> futur `colonies`
- `hive_inspections` / `hive_harvests` -> futur `observations` cible hive

Note: migrations DB Canopy pour `hives/colonies` non encore presentes dans `supabase/migrations`.

## 5) Architecture cible iOS (V1)

## 5.1 Modules cibles

1. `Remote`
- DTO/clients Supabase alignes sur Canopy (`species_private`, `cultivars`, `individuals`, `individual_photos`, `observations`, `sites`, `site_members`).
- Requetes explicitement scopees par `site_id`.

2. `Local Database (SQLite v2)`
- Projection offline-first du modele Canopy (pas copie legacy).
- Tables v2 avec `remote_id UUID` + `site_id` + `updated_at` + `deleted_at`.

3. `Repository + Sync Engine`
- Pull remote -> projection locale.
- Mutations locales -> outbox.
- Push outbox -> Supabase.
- Resolution conflits simple par `updated_at` + precedence remote configurable.

4. `UI Adapters`
- Adapte records locaux v2 vers models consommables par vues.
- Les vues ne parlent ni SQL ni Supabase.

5. `Store`
- Depend d'interfaces repository, pas des details de DB/HTTP.

## 5.2 Contrat de separation

- `RemoteDTO` != `LocalRecord` != `ViewModel`.
- Mapping explicite entre les 3.
- Aucune conversion implicite cachee dans la vue.

## 6) SQLite v2 (reconstruction propre)

Decision: **creer une base locale v2 propre** (`jardin_v2.db`).

Motif:
- Eviter de tordre le schema legacy `Int`/tables historiques.
- Aligner structurellement Canopy des le depart.

Tables minimales v2:

- `app_context` (current_user_id, current_site_id, last_full_pull_at)
- `species_global_local`
- `species_private_local`
- `cultivars_local`
- `individuals_local`
- `individual_photos_local`
- `observations_local`
- `sync_state` (per table watermark)
- `sync_outbox` (operations locales en attente)

Colonnes communes:
- `remote_id TEXT` (uuid)
- `site_id TEXT` (uuid)
- `updated_at TEXT` (ISO8601)
- `deleted_at TEXT NULL`
- metadata utile (`dirty`, `last_error`, `version`, etc. selon table)

Champs legacy non presents dans Canopy:
- migrer vers `metadata` JSON local quand pertinent (`micro_site`, `exposure_local`, `soil_local`, etc.).

## 7) Strategie de sync cible

## 7.1 Pull

- Pull par table Canopy scopee `site_id`.
- Filtre incremental via `updated_at > watermark`.
- Upsert local par `remote_id`.
- Appliquer `deleted_at` distant localement.

## 7.2 Mutations offline

- Toute ecriture UI ecrit d'abord local v2.
- Marque row `dirty` + ajoute entree `sync_outbox` (operation explicite).

## 7.3 Push

- Worker outbox FIFO (avec retry/backoff).
- Envoi vers tables Canopy correspondantes.
- Sur succes: clear `dirty`, retire outbox item.
- Sur erreur RLS/conflit: stocke erreur + remonte etat dans Store.

## 7.4 Conflits

V1 (simple et explicite):
- `deleted_at` gagne toujours sur row active plus ancienne.
- Sinon last-write-wins base sur `updated_at` distant/local.
- Conflits irreconciliables traces en erreur outbox (pas silencieux).

## 7.5 Site scoping

- Toutes operations remote + locale filtrees par `site_id` actif.
- Aucun acces metier sans site resolu depuis membership.

## 8) Compatibilite UI (preserver les vues)

Priorite de preservation:
1. `SpeciesListView`
2. `PlantsListView`
3. `SpeciesDetailView`
4. `PlantDetailView`
5. `SpeciesFormView` / `CultivarFormView` / `PlantFormView`
6. `GardenMapView`

Strategie:
- Conserver layout/comportements vues.
- Remplacer progressivement les models source par adapters v2.
- Si une vue depend d'un champ legacy absent, fournir via `metadata` adapter temporaire.

Hives:
- conserver lecture locale legacy transitoire tant que module DB Canopy `hives` n'est pas deploye.
- isoler dans un repository distinct pour migration ulterieure.

## 9) Fichiers a refactorer / creer / retirer

## 9.1 Refactor lourd

- `JardinForet/GardenDTO.swift`
- `JardinForet/GardenDatabase.swift`
- `JardinForet/GardenStore.swift`
- `JardinForet/GardenSyncService.swift`

## 9.2 A creer

- `JardinForet/Data/Remote/CanopyRemoteDTO.swift`
- `JardinForet/Data/Remote/CanopyRemoteClient.swift`
- `JardinForet/Data/LocalV2/SchemaV2.swift`
- `JardinForet/Data/LocalV2/LocalV2Records.swift`
- `JardinForet/Data/LocalV2/LocalV2Migrator.swift`
- `JardinForet/Data/Sync/SyncOutboxEngine.swift`
- `JardinForet/Data/Sync/SyncConflictPolicy.swift`
- `JardinForet/Domain/Repository/PlantsRepository.swift`
- `JardinForet/Domain/Repository/SpeciesRepository.swift`
- `JardinForet/Domain/Repository/HivesRepository.swift` (stub transitoire)
- `JardinForet/UIAdapters/TaxonomyAdapter.swift`
- `JardinForet/UIAdapters/IndividualsAdapter.swift`

## 9.3 A supprimer (apres bascule)

- DTO legacy `SpeciesDTO/PlantDTO/CultivarDTO` actuels
- sync legacy directe `from("species")/from("plants")/from("cultivars")`
- dependance runtime sur `jardin.db` legacy comme schema produit

## 10) Ordre d'execution (commits logiques)

1. **Doc + contracts**
- figer plan + checklist + invariants.

2. **Foundation data v2**
- introduire schema local v2 + migrator + records sans impacter vues.

3. **Remote Canopy client**
- client supabase site-scoped + DTO Canopy.

4. **Repository + adapters (read path)**
- brancher Store sur read v2 via adapters, vues intactes.

5. **Write path + outbox**
- formulaires ecrivent local v2 + outbox.

6. **Sync engine V2**
- pull/apply + push queue + state.

7. **Legacy importer one-shot**
- importer `jardin.db` -> v2 (species/cultivars/individuals).

8. **Cleanup legacy runtime**
- retirer anciens DTO/DB/sync code.

## 11) Premier lot propose (sans casser les vues)

Lot 1 (safe, anti-drift, testable):

1. Introduire `Data/LocalV2` (schema + records + migrator) en parallele.
2. Introduire `Data/Remote/CanopyRemoteClient` (lecture seule initiale).
3. Ajouter `UIAdapters` pour produire les modeles actuellement consommes (`GardenTaxon`, `GardenPlant`) depuis v2.
4. Ajouter `Feature flag` interne dans `GardenStore` pour switch read legacy -> read v2.
5. Ne pas modifier les vues dans ce lot.

Livrable lot 1:
- app compile,
- vues principales encore identiques,
- lecture possible depuis v2 sans ecriture distante.

