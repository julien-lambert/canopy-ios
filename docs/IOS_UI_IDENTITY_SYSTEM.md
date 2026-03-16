# Système UI iOS

Date: 2026-03-15
Périmètre: homogénéité visuelle et structurelle de `JardinForet`

## Constat

L'application a maintenant une base data plus cohérente, mais la couche UI reste encore trop fragmentée.

Les symptômes visibles:

- cartes visuelles recréées différemment selon les écrans ;
- tailles d'icônes et typographies non stabilisées ;
- boutons d'action et boutons de sauvegarde non homogènes ;
- styles de sections, vides, badges et états de sélection dupliqués ;
- logique d'écran parfois "formulaire natif", parfois "cartes custom", sans règle explicite.

## Duplication Déjà Visible

Exemples actuels:

- `JardinForet/View/HomeView.swift:435`
  - `ActionCard`
- `JardinForet/View/HomeView.swift:490`
  - `InfoCard`
- `JardinForet/View/PlantDetailView.swift:814`
  - `DetailCard`
- `JardinForet/View/SpeciesDetailView.swift:487`
  - `SectionCard`
- `JardinForet/View/PlantIdentifierView.swift:119`
  - carte custom ad hoc
- `JardinForet/View/PlantIdentifierView.swift:180`
  - deuxième carte custom ad hoc
- `JardinForet/View/PlantIdentifierView.swift:236`
  - troisième carte custom ad hoc

Le problème n'est pas que ces composants soient mauvais. Le problème est qu'ils expriment plusieurs mini-chartes implicites.

## Règle Cible

On ne doit plus styliser écran par écran.

On doit passer par:

1. des tokens visuels centralisés ;
2. des composants UI réutilisables ;
3. des conventions d'écran stables.

## Ce Qui Doit Être Centralisé

### Tokens

- palette de couleurs
- niveaux d'ombre
- rayons d'angle
- espacements
- tailles d'icônes
- hiérarchie typographique

### Composants

- `CanopyCard`
- `CanopySectionHeader`
- `CanopyPrimaryButton`
- `CanopySecondaryButton`
- `CanopyInlineStat`
- `CanopyEmptyState`
- `CanopyFieldGroup`
- `CanopyScreen`

### Routines

- structure d'un écran détail
- structure d'un écran liste
- structure d'un écran formulaire
- méthode de sauvegarde
- méthode d'annulation
- méthode d'affichage des actions secondaires

## Règles D'Identité

### Cartes

Une seule famille de cartes pour l'app:

- même rayon
- même fond
- même ombre
- même padding
- même logique de titre / sous-titre / action

### Icônes

Trois tailles maximum:

- navigation / inline
- carte / action rapide
- illustration / état vide

### Boutons

Une règle claire:

- primaire = sauvegarder / confirmer / continuer
- secondaire = ouvrir / compléter / filtrer
- destructif = supprimer

On évite les boutons stylés différemment d'un écran à l'autre pour la même intention.

### Formulaires

Les formulaires doivent partager:

- même ordre visuel ;
- même style de section ;
- même manière d'afficher les aides ;
- même placement du CTA principal ;
- même logique pour les champs avancés repliables.

## Ordre D'Implémentation Recommandé

### Lot A

- créer les primitives visuelles centrales
- remplacer les cartes dupliquées par un composant partagé

### Lot B

- unifier les boutons et les en-têtes
- unifier les écrans formulaires

### Lot C

- harmoniser les écrans détail et listes
- supprimer les styles locaux redondants

## Invariant

On ne doit plus ajouter un nouvel écran en "dessinant à la main" son style local.

Tout nouvel écran doit être composé à partir de primitives UI de l'app.
