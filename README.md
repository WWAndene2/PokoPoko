# PokoPoko

Jeu de puzzle mobile (Android / iOS) à réactions en chaîne, développé avec **Godot 4.3** (licence MIT, sans frais).
Code original : inspiré des mécaniques du genre, sans reprendre de code ni d'éléments de Puyo VS 2 ou Puyo Puyo.

## Structure
- `scripts/board.gd` — règles de la grille (paire, rotation, gravité, groupes, grumeaux, score).
- `scripts/player.gd` — déroulé d'une partie pour un joueur (chute, chaînes, attaques, contre-attaque, grille vide).
- `scripts/ai.gd` — adversaire ordinateur (3 niveaux).
- `scripts/game.gd` — menu, écrans, affichage et contrôles tactiles.
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
- Glisser ↔ : déplacer
- Toucher la moitié droite / gauche de l'écran : tourner à droite / à gauche
- Glisser ↓ lentement et maintenir : descente rapide · Glisser ↓ vite : chute immédiate
