# PokoPoko

Jeu de puzzle mobile (Android / iOS) à réactions en chaîne, développé avec **Godot 4.3** (licence MIT, sans frais).
Code original : inspiré des mécaniques du genre, sans reprendre de code ni d'éléments de Puyo VS 2 ou Puyo Puyo.

## Structure
- `scripts/board.gd` — règles pures (grille, paire, gravité, groupes, score), testables.
- `scripts/game.gd` — affichage, contrôles tactiles, machine à états.
- `scenes/main.tscn` — scène principale.
- `tests/test_board.gd` — tests des règles.
- `prototype/index.html` — ancien prototype web, pour référence uniquement.

## Lancer
- Éditeur : ouvrir le dossier dans Godot 4.3 puis F5.
- Tests : `godot --headless --path . -s tests/test_board.gd`

## Exporter sur mobile
Éditeur → Projet → Exporter : ajouter le préréglage Android (SDK Android + modèles d'export)
ou iOS (macOS + Xcode requis).

## Contrôles
Glisser ↔ : déplacer · Toucher : tourner · Glisser ↓ : chute rapide
