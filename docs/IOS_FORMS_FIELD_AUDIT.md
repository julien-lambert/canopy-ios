# Audit Formulaires iOS

Date: 2026-03-15
Périmètre: `JardinForet` iOS, couche de saisie terrain `species` / `cultivars` / `individuals`

## Constats

Le socle `Canopy` est désormais beaucoup plus propre côté données, mais les formulaires gardent encore une logique trop proche du schéma et pas assez proche des usages terrain.

Le problème principal n'est pas un champ manquant. Le problème est la forme globale de la saisie:

- on demande trop d'informations trop tôt ;
- on mélange création terrain et curation botanique ;
- on imbrique des créations secondaires dans des écrans déjà lourds ;
- on oblige l'utilisateur à penser comme la base de données au lieu de penser comme un jardinier sur site.

## Audit Par Formulaire

### `PlantFormView`

Référence: `JardinForet/View/PlantFormView.swift`

Le formulaire individu est actuellement composé de huit sections:

- espèce
- cultivar
- informations sur l'individu
- localisation
- position géographique
- croissance
- acquisition
- notes

Problèmes observés:

- `PlantFormView.swift:139` à `PlantFormView.swift:148`
  - le formulaire principal est long et linéaire ; il n'y a pas de hiérarchie entre l'essentiel et le secondaire.
- `PlantFormView.swift:207`
  - depuis la création d'un individu, on peut ouvrir une création complète d'espèce.
- `PlantFormView.swift:263`
  - depuis la même vue, on peut aussi ouvrir une création complète de cultivar.
- `PlantFormView.swift:312`
  - la géolocalisation est utile sur terrain, mais elle arrive comme une section de plus, pas comme un geste central du flux.
- `PlantFormView.swift:343`
  - hauteur et envergure sont présentes, ce qui est bien, mais elles arrivent sans distinction entre mesure utile sur terrain et enrichissement optionnel.

Conséquence UX:

- pour ajouter vite un individu, l'écran demande déjà une charge mentale de curation ;
- pour modifier un individu, on repasse par un écran trop généraliste ;
- la création de cultivar n'est pas assez fluide parce qu'elle dépend d'un détour lourd.

### `SpeciesFormView`

Référence: `JardinForet/View/SpeciesFormView.swift`

Le formulaire espèce mélange:

- identité botanique ;
- enrichissement IA ;
- gestion des cultivars ;
- écologie / culture / usages ;
- métriques botaniques ;
- médias ;
- suppression.

Problèmes observés:

- `SpeciesFormView.swift:113`
  - le formulaire commence déjà avec un niveau de détail de curation, pas avec un minimum viable de saisie.
- `SpeciesFormView.swift:146`
  - la gestion des cultivars est imbriquée dans l'écran espèce.
- `SpeciesFormView.swift:188`
  - les champs éditoriaux et botaniques sont présentés d'un bloc.
- `SpeciesFormView.swift:195`
  - les dimensions et périodes sont utiles, mais elles devraient vivre dans un niveau avancé ou de curation.

Conséquence UX:

- bon formulaire pour une fiche botanique riche ;
- mauvais formulaire pour créer rapidement une espèce manquante sur le terrain ;
- confusion entre "je dois juste pouvoir continuer ma saisie" et "je suis en train de compléter une monographie".

### `CultivarFormView`

Référence: `JardinForet/View/CultivarFormView.swift`

Le formulaire cultivar est aujourd'hui presque une mini-fiche espèce.

Problèmes observés:

- `CultivarFormView.swift:97`
  - la section de base est correcte.
- `CultivarFormView.swift:120`
  - la seconde section bascule immédiatement dans une curation lourde.
- la création d'un cultivar demande trop d'informations pour un usage terrain.

Conséquence UX:

- on peut techniquement créer un cultivar ;
- mais on ne peut pas le faire rapidement pendant une saisie d'individu.

### `PlantIdentifierView`

Référence: `JardinForet/View/PlantIdentifierView.swift`

Cette vue est structurellement plus claire:

- photos ;
- action ;
- propositions ;
- import.

Problèmes observés:

- `PlantIdentifierView.swift:243`
  - l'import crée une espèce et éventuellement un individu, mais le passage vers un vrai flux d'édition reste trop implicite.
- le flux est bon pour "identifier", moins bon pour "intégrer proprement dans le référentiel local".

Conséquence UX:

- bon point d'entrée ;
- pas encore un vrai assistant terrain complet.

## Diagnostic Produit

Aujourd'hui, l'app mélange trois métiers qui devraient être séparés:

1. capturer un individu sur le terrain ;
2. compléter ou corriger une fiche botanique ;
3. maintenir le référentiel des cultivars.

Ces trois tâches n'ont pas le même rythme, pas la même charge cognitive, pas le même contexte d'usage.

## Architecture Cible Des Formulaires

### Principe 1 — Séparer Terrain Et Curation

Il faut deux niveaux de saisie:

- saisie terrain rapide ;
- édition botanique avancée.

La règle:

- un individu doit pouvoir être créé en moins de 30 secondes ;
- une espèce doit pouvoir être créée en mode minimal sans bloquer le terrain ;
- les détails botaniques riches doivent être édités ensuite, pas imposés au départ.

### Principe 2 — L'individu Est Le Flux Principal Terrain

Le flux principal sur site doit être:

1. choisir une espèce ;
2. choisir éventuellement un cultivar ;
3. confirmer GPS / zone ;
4. renseigner statut ;
5. optionnel: hauteur actuelle, envergure actuelle, note rapide, photo ;
6. enregistrer.

Le formulaire individu ne doit plus être la porte d'entrée vers une grosse édition taxonomique.

### Principe 3 — Espèce Et Cultivar Doivent Avoir Un Mode Léger

Créer une espèce manquante doit demander seulement:

- nom vernaculaire ;
- nom latin ;
- famille optionnelle ;
- genre optionnel ;
- strate optionnelle ;
- image optionnelle.

Créer un cultivar doit demander seulement:

- espèce parente ;
- nom du cultivar ;
- note courte optionnelle.

Les autres champs doivent être dans un mode "Compléter la fiche".

## Flux Recommandés

### Flux A — Ajout Terrain Rapide D'un Individu

Nouvelle vue cible: `IndividualQuickEntryView`

Champs visibles par défaut:

- espèce
- cultivar optionnel
- statut
- zone
- GPS
- hauteur actuelle optionnelle
- envergure actuelle optionnelle
- note rapide

Actions:

- `Créer une espèce` ouvre une feuille minimale
- `Créer un cultivar` ouvre une feuille minimale seulement si une espèce est sélectionnée
- retour automatique avec sélection préremplie

### Flux B — Édition D'un Individu Existant

Nouvelle vue cible: `IndividualDetailEditorView`

Deux niveaux:

- résumé principal
- détails avancés repliables

Champs avancés:

- micro-site
- exposition locale
- type de sol
- acquisition
- notes d'entretien

### Flux C — Création Ou Curation D'une Espèce

Nouvelle vue cible: `SpeciesEditorView`

Sous-ensembles:

- identité
- profil botanique
- usages / culture
- dimensions
- médias
- cultivars liés

Mode création:

- identitié minimale d'abord ;
- écran de complétion ensuite si besoin.

### Flux D — Création Ou Curation D'un Cultivar

Nouvelle vue cible: `CultivarEditorView`

Mode minimal:

- espèce parente
- nom
- note

Mode avancé:

- morphologie
- culture
- usages
- dimensions
- périodes

## Design Recommandé

### Pour Le Terrain

- sections courtes ;
- priorité visuelle sur espèce, cultivar, GPS, statut ;
- CTA principal clair ;
- valeurs par défaut intelligentes ;
- repli des champs secondaires ;
- création inline via feuille modale légère, pas via gros détour de navigation.

### Pour La Curation

- écrans dédiés ;
- structure plus proche d'une fiche ;
- possibilité d'éditer longtemps et proprement ;
- IA comme aide de remplissage, pas comme bouton placé au sommet de tous les flux.

## Décisions Recommandées

1. sortir la création complète d'espèce hors du formulaire individu ;
2. sortir la création complète de cultivar hors du formulaire individu ;
3. créer un vrai flux `ajout individu terrain` ;
4. garder `SpeciesFormView` et `CultivarFormView` comme base de curation, puis les simplifier ;
5. ne pas demander les champs riches tant qu'ils ne débloquent pas l'action terrain immédiate.

## Ordre D'Implémentation Recommandé

### Lot 1

- concevoir un nouveau formulaire `ajout individu terrain`
- espèce requise
- cultivar optionnel
- GPS central
- hauteur actuelle / envergure actuelle visibles
- création minimale d'espèce et de cultivar en feuille

### Lot 2

- refondre `SpeciesFormView` en deux niveaux:
  - création minimale
  - édition avancée

### Lot 3

- refondre `CultivarFormView` sur le même principe:
  - création minimale
  - édition avancée

### Lot 4

- raccorder `PlantIdentifierView` au nouveau flux terrain
- après identification:
  - créer espèce si nécessaire
  - proposer directement la création d'un individu terrain propre

## Invariant Produit

Le schéma Canopy reste la source de vérité.

La simplification des formulaires ne doit pas appauvrir le modèle. Elle doit seulement:

- mieux séquencer la saisie ;
- mieux adapter l'UI au terrain ;
- réduire la friction ;
- préserver une curation riche dans des écrans dédiés.
