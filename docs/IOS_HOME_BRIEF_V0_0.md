# iOS Home Brief v0.0

Date: 2026-03-16

## Intention

L'accueil iOS affiche maintenant un bloc `Brief du jour`.

Ce bloc ne calcule rien dans l'app.
L'app consomme une reponse serveur issue de `fn-home-brief-v0` et affiche :

- la meteo du jour
- le risque de gel
- des alertes
- des actions
- des verifications terrain
- une synthese courte

## Pourquoi

On veut garder le noyau fonctionnel propre :

- les calculs meteo / gel restent cote Supabase
- Gemini ne vit pas dans les vues SwiftUI
- l'app ne fait qu'afficher un contrat stable

Cette approche prepare le futur mode agent sans figer une logique IA dans le client.

## Fichiers relies

- `JardinForet/UI/HomeBriefingService.swift`
  - decode la reponse de `fn-home-brief-v0`
  - centralise l'appel Edge Function
- `JardinForet/View/HomeView.swift`
  - charge le brief pour le site courant
  - affiche la carte `Brief du jour`

## Contrat consomme

L'app attend une enveloppe de cette forme :

```json
{
  "ok": true,
  "data": {
    "context": { "...": "..." },
    "briefing": { "...": "..." },
    "llm": { "generated": true }
  }
}
```

## Comportement UI

- chargement automatique quand le site courant change
- bouton `Actualiser le brief`
- si Gemini reussit : mention d'une synthese reformulee
- si Gemini echoue : le serveur renvoie un fallback deterministe, donc l'accueil reste utile

## Decision importante

Aucune cle Gemini ni logique de prompt n'est embarquee dans l'app.
Toute la logique IA reste cote Supabase.
