# PokoPoko — Règles de gameplay et gimmicks

> Document de référence du game design. Les valeurs chiffrées sont des **points de départ à équilibrer** en test.
> Statut : ✅ implémenté · 🔜 prochaine étape · 💡 à valider

---

## 1. Vocabulaire

| Terme | Définition |
|---|---|
| **Poko** | Bulle colorée avec des yeux. Unité de base du jeu. |
| **Paire** | Deux Pokos qui tombent ensemble : le **pivot** (en bas) et le **satellite** (qui tourne autour). |
| **Éclatement** | Disparition d'un groupe de 4 Pokos ou plus de même couleur. |
| **Chaîne** | Suite d'éclatements provoqués par la gravité après un premier éclatement. |
| **Grumeau** | Poko gris envoyé à l'adversaire (attaque). Ne s'éclate pas seul. |
| **Grille** | Plateau de 6 colonnes × 12 lignes visibles + 1 ligne cachée au-dessus. |

---

## 2. Règles de base ✅

### 2.1 Grille
- 6 colonnes × 12 lignes visibles.
- Une **ligne cachée** (ligne 0) au-dessus : les Pokos peuvent y rester, mais ils **ne comptent pas** pour les éclatements.
- **Colonne d'apparition** : 3ᵉ colonne en partant de la gauche (marquée en rouge).

### 2.2 La paire
- Chaque paire contient 2 Pokos de couleurs tirées au hasard (même couleur possible).
- La paire apparaît le satellite **au-dessus** du pivot.
- La **paire suivante** est toujours visible et la suivante après elle (2 paires d'avance) ✅.
- Une **ombre** montre où la paire va atterrir.

### 2.3 Couleurs
- Chaque couleur est un **élément** avec sa propre personnalité (voir section 10).
- **4 éléments** en mode normal : Aqua, Blaze, Leaf, Sunny ✅.
- **5 éléments** en mode difficile (+ Nova) 💡.
- Le tirage est fait par un générateur à **graine** (seed) : en versus, les deux joueurs reçoivent **exactement la même suite de paires** (équité) ✅.

### 2.4 Contrôles

| Action | Tactile | Clavier (test) |
|---|---|---|
| Déplacer | Glisser à gauche / droite (1 case par ~0,8 case glissée) | ← → |
| Tourner (sens horaire) | Toucher bref sur la moitié **droite** de l'écran | ↑ ou X |
| Tourner (sens anti-horaire) ✅ | Toucher bref sur la moitié **gauche** de l'écran | Z |
| Descente rapide ✅ | Glisser lentement vers le bas et maintenir (+1 point par case) | ↓ maintenu |
| Chute immédiate | Glisser **vite** vers le bas (+2 points par case) | Espace |

### 2.5 Rotation
1. Rotation sur place si la place est libre.
2. Sinon **décalage contre le mur** : la paire est poussée d'une case à l'opposé du blocage.
3. Sinon **décalage vers le haut** (si le satellite est bloqué par le sol ou un Poko).
4. Sinon, dans un puits de 1 colonne : **retournement à 180°** (le pivot et le satellite échangent leurs places).

### 2.6 Chute et pose
- La paire descend d'une case toutes les **0,70 s** au départ.
- La vitesse augmente à chaque pose (−4 ms), jusqu'à **0,18 s** minimum.
- **Temps de grâce** ✅ : quand la paire touche le sol, le joueur a encore **0,5 s** pour la déplacer ou la tourner (remis à zéro à chaque action, 8 fois maximum).
- Une fois posée, la paire **se sépare** : chaque Poko tombe seul jusqu'au premier obstacle.
- Descente rapide : **+1 point** par case ; chute immédiate : **+2 points** par case. En descente rapide, la paire se pose dès qu'elle touche le sol.

### 2.7 Éclatement
- Un groupe de **4 Pokos ou plus** de même couleur, reliés **horizontalement ou verticalement** (pas en diagonale), éclate.
- Seule la partie visible de la grille compte.
- Plusieurs groupes peuvent éclater **en même temps** : ils comptent pour le même maillon de chaîne.

### 2.8 Chaînes
Après un éclatement :
1. Les Pokos au-dessus tombent (gravité).
2. Si de nouveaux groupes de 4+ se forment → nouvel éclatement = **maillon suivant de la chaîne**.
3. On recommence jusqu'à ce qu'il n'y ait plus rien à éclater.
4. Une nouvelle paire apparaît.

Le joueur ne peut **pas** jouer pendant une chaîne : il doit la **préparer à l'avance**. C'est le cœur stratégique du jeu.

### 2.9 Fin de partie
- La partie est perdue si la **case d'apparition** (3ᵉ colonne, 1ʳᵉ ligne visible) est occupée au moment où une nouvelle paire doit apparaître.

---

## 3. Score ✅

Pour chaque maillon de chaîne :

```
score = 10 × P × (Puissance de chaîne + Bonus de couleurs + Bonus de groupe)
```
- **P** = nombre de Pokos éclatés pendant ce maillon.
- Le multiplicateur total vaut **au moins 1** et **au plus 999**.

| Maillon | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13+ |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Puissance de chaîne | 0 | 8 | 16 | 32 | 64 | 96 | 128 | 160 | 192 | 224 | 256 | 288 | 320 |

| Couleurs éclatées en même temps | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Bonus de couleurs | 0 | 3 | 6 | 12 | 24 |

| Taille d'un groupe | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11+ |
|---|---|---|---|---|---|---|---|---|
| Bonus de groupe | 0 | 2 | 3 | 4 | 5 | 6 | 7 | 10 |

*(Si plusieurs groupes éclatent ensemble, leurs bonus de groupe s'additionnent.)*

**Exemples :**
- 4 Pokos au 1ᵉʳ maillon → 10 × 4 × 1 = **40**
- 4 Pokos au 2ᵉ maillon → 10 × 4 × 8 = **320**
- 4 Pokos au 5ᵉ maillon → 10 × 4 × 64 = **2 560**

**Grille vide** ✅ : vider entièrement la grille donne **+2 100 points**. En versus, l'attaque suivante reçoit **+30 grumeaux** en plus.

---

## 4. Combat (versus) ✅

### 4.1 Grumeaux
- Chaque tranche de **70 points** marqués = **1 grumeau** envoyé à l'adversaire (le reste est gardé pour la suite).
- Les grumeaux tombent **après** la pose de la paire suivante de l'adversaire, au maximum **30 à la fois** (5 lignes). Le reste attend son tour.
- Ils tombent répartis le plus équitablement possible sur les 6 colonnes (colonnes du reste tirées au hasard).
- Un grumeau **disparaît** quand un groupe de Pokos éclate **juste à côté** de lui (horizontalement ou verticalement).
- Un grumeau ne forme jamais de groupe et ne fait jamais partie d'une chaîne.

### 4.2 Annonce des grumeaux (formes et couleurs provisoires ✅)
Au-dessus de la grille, des icônes montrent les grumeaux en attente :

| Icône | Valeur |
|---|---|
| Petit grumeau | 1 |
| Gros grumeau | 6 (1 ligne) |
| Rocher | 30 |
| Étoile | 180 |
| Lune | 360 |
| Couronne | 720 |

### 4.3 Contre-attaque (annulation)
- Si des grumeaux sont en attente et que le joueur marque des points, ses grumeaux servent **d'abord à annuler** ceux qui l'attendent.
- S'il en reste, ils partent chez l'adversaire.
- Les grumeaux en attente **ne tombent pas pendant une chaîne** en cours : on a le temps de contre-attaquer.

### 4.4 Accélération (anti-partie infinie)
- Après **96 s** de match, la valeur d'un grumeau baisse : 70 → 52 → 39 → 29… points (−25 % toutes les 16 s, minimum 1).
- Les attaques deviennent donc plus fortes et le match se termine (objectif : 2 à 4 minutes).

---

## 5. Gimmicks originaux PokoPoko 💡

Ces mécaniques distinguent PokoPoko des autres jeux du genre. Chacune est **activable par mode** et doit être testée avant d'être gardée.

### 5.1 Poko Étoile ⭐ (bombe de couleur)
- Apparaît rarement dans une paire (environ 1 paire sur 40, jamais dans les 20 premières).
- Quand elle se pose, elle **prend la couleur** du Poko qu'elle touche en dessous (ou à côté s'il n'y a rien dessous).
- Si son groupe éclate, elle éclate aussi **tous les Pokos de cette couleur reliés en diagonale** au groupe.
- But : rattraper une grille mal construite. **Désactivée en classé.**

### 5.2 Grumeau gelé 🧊
- Version renforcée du grumeau, envoyée par les chaînes de **7 maillons ou plus** (1 grumeau sur 6).
- Il faut **2 éclatements à côté** de lui : le premier le transforme en grumeau normal, le second le fait disparaître.

### 5.3 Mode Fièvre 🔥
- Une **jauge** se remplit à chaque contre-attaque réussie (1 cran par contre-attaque, 7 crans).
- Jauge pleine : pendant **15 s**, la grille du joueur est remplacée par une **chaîne déjà préparée** ; il suffit de trouver le bon endroit pour la déclencher.
- Chaque chaîne réussie donne **+2 s** et une chaîne préparée plus longue.
- À la fin, la grille d'origine revient intacte.
- Mode séparé, **pas dans le versus de base**.

### 5.4 Pokos dormeurs 😴 (mode Puzzle)
- Pokos aux yeux fermés placés dès le début.
- Ils éclatent normalement, mais **ne tombent pas** tant qu'ils ne sont pas réveillés (un éclatement à côté d'eux les réveille).
- Servent à créer des énigmes de chaînes plus variées.

### 5.5 Indice de chaîne 👀 (aide aux débutants)
- En mode Entraînement, les Pokos qui **feraient partie d'une chaîne** si la paire était posée à l'endroit de l'ombre clignotent doucement.
- Toujours **désactivé** en versus et en classé.

---

## 6. Modes de jeu

| Mode | Statut | Règles |
|---|---|---|
| **Solo infini** | ✅ | Survivre le plus longtemps possible, score maximal. La vitesse augmente. |
| **Entraînement** | 🔜 | Pas de chute automatique, retour en arrière d'un coup, indice de chaîne. |
| **Versus IA** | ✅ | Combat avec grumeaux contre l'ordinateur, 5 niveaux (de « pose au hasard » à « prépare des chaînes de 6+ »). |
| **Défi du jour** | 🔜 | Même suite de paires pour tout le monde (même graine), 1 essai classé + essais libres, code à partager entre amis. |
| **Puzzle** | 💡 | Grille imposée + liste de paires fixe : réaliser une chaîne de N maillons. |
| **Fièvre** | 💡 | Voir 5.3. |
| **Versus en ligne** | 💡 | Classé et amical, même graine pour les deux joueurs, résultat vérifié par le serveur. |

---

## 7. Ressenti (« game feel »)

| Événement | Retour |
|---|---|
| Pose de paire | Petit rebond des Pokos (écrasement 10 %), son sourd |
| Éclatement | Clignotement blanc, gonflement + disparition (0,35 s), son qui monte d'un demi-ton par maillon |
| Chaîne 2+ | Texte « N chaînes ! », tremblement de l'écran proportionnel, vibration (30 ms + 20 ms par maillon, max 150 ms) |
| Chaîne 5+ | Particules, ralenti léger de 0,1 s 💡 |
| Grumeaux reçus | Icônes qui tremblent au-dessus de la grille, avertissement sonore |
| Danger | Colonne d'apparition qui clignote quand elle dépasse 10 lignes |

---

## 8. Principes à respecter (rappel du document stratégique)
- Le classement dépend **uniquement de l'habileté** : aucun achat ni bonus payant ne change le gameplay.
- Les gimmicks d'aide (Poko Étoile, indice de chaîne) sont **interdits en classé**.
- Aucune manipulation cachée du hasard pour pousser à acheter ou à rejouer.
- Les deux joueurs d'un versus reçoivent **toujours** la même suite de paires.


## 9. Inspirations de toute la franchise Puyo Puyo 💡

Rappel légal : les **règles** du genre sont libres, mais le nom « Puyo », les personnages (Arle, Carbuncle…), les voix, musiques, dessins et formules connues (« Bayoeen ! ») appartiennent à SEGA. On reprend **uniquement des mécaniques**, renommées et redessinées.

### 9.1 Ce que chaque épisode apporte

| Épisode (mécanique) | Idée retenue | Nom PokoPoko |
|---|---|---|
| Puyo Puyo (1991) | Règles de base, mode histoire contre une suite d'adversaires | ✅ base + **Tournée** (9.2) |
| Puyo Puyo 2 / Tsu | **Contre-attaque** (annulation), **grille vide**, garbage en attente | Section 4 ✅ (design) |
| Puyo Puyo Sun | **Puyos Soleil** : bulles qui augmentent la force de l'attaque | **Pokos Soleil** (9.3) |
| Puyo Puyo~n | **Cartes de personnage** à pouvoir unique | **Signatures** des Compagnons (9.4) |
| Puyo Puyo Fever | **Mode Fièvre**, **formes de paires variées** (trios, quatuors), **compteur de temps de chute** | Fièvre (5.3) + **Formes** (9.5) |
| Puyo Puyo 7 | **Transformation géante** : grosses bulles plus faciles à éclater | **Mode Méga** (9.6) |
| Puyo Puyo 15th / 20th | Dizaines de **règles alternatives** (Bombe, Sous-marin, Excavation, Glace…) | **Fêtes** (9.7) |
| Puyo Puyo Tetris | Mélange avec un autre genre, **Swap** et **Fusion** | **Mode Mash-up** (9.8), avec un genre maison |
| Puyo Puyo!! Quest | RPG de cartes déclenché par les éclatements | **Donjon** (9.11) |
| Puyo Puyo Champions / eSport | **Règles compétitives figées**, classement, replays | **Règle Classique** (section 8) + 9.9 |

### 9.2 Tournée (mode histoire)
- Suite de **10 adversaires IA** de plus en plus forts, chacun avec un style (bâtisseur de longues chaînes, attaquant rapide, défenseur…).
- Courtes scènes entre les combats avec des **personnages Pokos originaux**.
- Le dernier adversaire a une règle spéciale (ex. ses grumeaux sont toujours gelés).

### 9.3 Pokos Soleil ☀️
- Variante du grumeau envoyé par une **contre-attaque** réussie.
- Dans la grille de celui qui le reçoit, il se comporte comme un grumeau, mais s'il **éclate à côté d'un groupe**, il ajoute **+3 grumeaux** à l'attaque de ce joueur.
- Encourage le retournement de situation. Mode « Soleil » optionnel.

### 9.4 Signatures des Compagnons
- Chaque Compagnon a une **signature** : une petite règle qui lui est propre (ex. « vos grumeaux tombent 1 pose plus tard », « +1 maillon de puissance à la 1ʳᵉ chaîne de 5+ »).
- Uniquement en Versus amical et Donjon ; **jamais en classé**.

### 9.5 Formes de paires 🧩
- Chaque Compagnon a sa **suite de formes** (16 pièces qui se répètent) : paires simples, **trios en L**, **quatuors carrés** de 2 couleurs, **gros Poko** d'une seule couleur (2×2) qui change de couleur quand on le tourne.
- Rend chaque personnage différent à jouer ; mode Classique = paires uniquement.

### 9.6 Mode Méga 🎈
- Une jauge se remplit en éclatant des Pokos (attaque + défense).
- Pleine : pendant **20 s**, la grille passe en **3×6 cases géantes** ; les groupes éclatent dès **3** Pokos et les attaques sont **×1,5**.
- À la fin, retour à la grille normale (intacte).

### 9.7 Fêtes (règles alternatives tournantes)
Une règle mise en avant chaque semaine en Versus amical :

| Fête | Règle |
|---|---|
| **Bombes** | Les grumeaux sont remplacés par des bombes à retardement (5 poses) qui ajoutent 2 lignes si elles ne sont pas désamorcées |
| **Glace** | Toute attaque envoie des Pokos gelés (5.2) au lieu de grumeaux |
| **Excavation** | Grille pré-remplie avec un **trésor** enfoui ; le premier qui le fait remonter en haut gagne |
| **Sous-marin** | La gravité s'inverse toutes les 30 s (les Pokos « flottent » vers le haut) |
| **Grande grille** | 8 colonnes × 14 lignes, 5 couleurs |
| **Taille 3** | Les groupes éclatent dès 3 Pokos, attaques réduites |

### 9.8 Mode Mash-up
- Mélange avec un second genre **original** (pas Tetris) : par exemple des **blocs à aligner** (règles de ligne pleine) qui tombent entre les paires.
- Variante **Échange** : toutes les 25 s, on bascule entre la grille Pokos et la grille Blocs ; les attaques des deux comptent.
- À valider très tard : gros chantier.

### 9.9 Couche eSport
- **Règle Classique figée** et publiée (version, valeurs exactes) ; tout changement est annoncé.
- **Même graine** pour les deux joueurs, résultat **vérifié par le serveur**.
- **Replays** de chaque match classé, mode **spectateur** avec l'aperçu des paires suivantes des deux joueurs.
- **Premier à 2 / 3 / 7 manches** au choix pour les tournois.
- **Saisons** de classement avec réinitialisation douce.

### 9.10 À éviter (vient de la franchise mais déconseillé)
- **Personnages ou voix** ressemblant à ceux de SEGA.
- **Tirage de cartes payant** (modèle Puyo Puyo!! Quest) : contraire à la section 8.
- **Énergie / endurance** qui limite le nombre de parties.

### 9.11 Donjon (mode RPG)
- Suite de monstres à vaincre : chaque éclatement attaque le monstre (dégâts = points du maillon ÷ 10, de la couleur éclatée).
- Le monstre riposte toutes les N poses en envoyant des grumeaux.
- Équipe de Compagnons originaux avec leurs Signatures (9.4) et Formes (9.5), débloqués **en jouant** (pas de tirage payant).
- Progression limitée au Donjon : n'affecte jamais le versus ni le classé.

### 9.12 Ordre de développement conseillé
1. **Versus IA** avec grumeaux, contre-attaque et grille vide (section 4) : c'est le cœur du genre.
2. **Tournée** (9.2) : donne un objectif solo.
3. **Formes de paires** (9.5) et **Signatures** (9.4) : rendent chaque Compagnon unique.
4. **Fièvre** (5.3) puis **Méga** (9.6).
5. **Fêtes** (9.7), **eSport** (9.9) avec le versus en ligne.
6. **Donjon** (9.11), puis **Mash-up** (9.8) en dernier.

---

## 10. Les Pokos et les Compagnons

### 10.1 Les 5 Pokos ✅
Chaque couleur de Poko est un **élément** avec une **émotion**, visible sur son visage.

| Poko | Couleur | Élément | Personnalité | Visage |
|---|---|---|---|---|
| **Aqua** | Bleu | Eau | Confiant et courageux | Yeux ronds décidés, sourcils froncés, sourire assuré |
| **Blaze** | Rouge | Feu | Agressif et arrogant | Yeux mi-clos en biais, sourire en coin |
| **Leaf** | Vert | Plante | Calme et doux | Yeux fermés détendus, petit sourire |
| **Sunny** | Jaune | Lumière | Joyeux et enjoué | Yeux en « ^ ^ », grand sourire ouvert |
| **Nova** | Violet | Ombre | Apathique et mystérieux (*kuudere*) | Yeux plats à demi fermés, bouche neutre |

- Nova n'apparaît qu'en mode **5 éléments** : il est le plus rare, ce qui colle à son côté mystérieux.
- 🔜 Animations par émotion : Blaze tremble d'impatience, Leaf se balance doucement, Sunny sautille en tombant, Aqua bombe le torse à la pose, Nova cligne lentement des yeux.
- 🔜 Son d'éclatement propre à chaque élément (goutte, crépitement, froissement, tintement, souffle grave).

### 10.2 Les 5 Compagnons 💡

| Compagnon | Élément d'origine | Thème |
|---|---|---|
| **Mizuki** | Aqua (eau) | Confiance, courage |
| **Homura** | Blaze (feu) | Agressivité, arrogance |
| **Kaede** | Leaf (plante) | Calme, douceur |
| **Hikari** | Sunny (lumière) | Joie, bonne humeur |
| **Kuroha** | Nova (ombre) | Apathie, mystère (*kuudere*) |

### 10.3 Compagnons et Pokos sont indépendants
- Un Compagnon **n'est pas lié** aux Pokos de son élément : **n'importe quel Compagnon** joue avec **tous les Pokos** de la partie.
- Son élément d'origine définit seulement sa **personnalité**, son **apparence** et l'**ambiance** de sa Signature (9.4) et de sa série de Formes (9.5).
- Exemples de Signatures (à équilibrer) :

| Compagnon | Signature (idée) | Formes (idée) |
|---|---|---|
| Mizuki | Courage : sa 1ʳᵉ contre-attaque de la partie annule +6 grumeaux | Paires et trios équilibrés |
| Homura | Arrogance : +1 maillon de puissance sur ses chaînes de 5+, mais ses grumeaux en attente tombent 1 pose plus tôt | Beaucoup de carrés (rapide, risqué) |
| Kaede | Calme : temps de grâce allongé (0,8 s au lieu de 0,5 s) | Presque que des paires (facile) |
| Hikari | Joie : la grille vide donne +50 % de bonus | Paires et gros Pokos |
| Kuroha | Mystère : l'adversaire voit ses paires suivantes en silhouette seulement | Formes imprévisibles |

- En **Classique / classé** : les Compagnons ne sont que **cosmétiques** (portrait, voix, réactions), aucune Signature ni Forme.
