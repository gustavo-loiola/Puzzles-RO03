# Notes de présentation : Résolution du jeu Range

Ce document résume les points clés de l'implémentation du jeu Range pour la soutenance. Contrairement à Mosaic, la modélisation de Range est beaucoup plus riche en raison de la contrainte globale de connexité et de la définition de la visibilité.

## 1. Génération des instances
- **Principe** : Générer une solution valide et en déduire le problème.
- **Étapes** :
  1. On place aléatoirement des cases noires sur la grille en respectant la contrainte de non-adjacence.
  2. On effectue un **parcours en largeur (BFS)** pour s'assurer que les cases blanches forment une unique composante connexe. Si ce n'est pas le cas, on rejette la grille et on recommence.
  3. Pour chaque case blanche, on simule la vision dans les 4 directions et on compte le nombre de cases visibles pour obtenir une grille de valeurs complètes.
  4. On applique un masque aléatoire (basé sur une "densité") pour cacher une partie des indices et obtenir l'instance de jeu.

## 2. Choix de modélisation (Modèles PLNE)
Deux stratégies de modélisation ont été explorées, différant par leur gestion de la connexité (Règle 3). Les variables de base sont $b_{i,j} \in \{0,1\}$ (1 si noire).
- **Contraintes partagées** : 
  - (R1) Les cases contenant un nombre doivent être blanches.
  - (R2) Pas de cases noires adjacentes ($b_{i,j} + b_{i\pm1, j\pm1} \le 1$).
  - (R4) Visibilité : Modélisée en introduisant des variables binaires auxiliaires de "ligne de vue" pour chaque direction. Le statut visible d'une case à distance $d$ est contraint par l'absence de case noire sur son chemin.
- **Modèle 1 : Flux Multi-Commodité** (Implémentation de base)
  - Ajout de variables continues de flux dirigées sur chaque arête du graphe.
  - Une case source (blanche) produit du flux, et chaque case blanche consomme 1 unité.
  - L'écoulement n'est autorisé qu'à travers les cases blanches via des constantes de grande valeur (Grand-M, avec $M = n \times m$).

- **Modèle 2 : Génération de coupes (Callback)** (Implémentation avancée)
  - Ne contient aucune variable de flux ni aucune contrainte de connexité dans le modèle initial, ce qui réduit drastiquement la taille du problème.
  - La connexité est assurée de manière dynamique.

## 3. Fonctionnement du Callback (Lazy Constraints)
- **Principe** : Lorsqu'un nœud est évalué comme solution entière par CPLEX, le callback interrompt brièvement le solveur pour vérifier la validité de la connexité.
- **Algorithme** :
  1. On extrait la solution candidate (cases noires/blanches).
  2. On lance un **BFS** depuis notre case source pour trouver toutes les cases blanches connectées.
  3. S'il existe des cases blanches non visitées, elles forment une ou plusieurs **composantes isolées** $S$.
  4. Pour chaque composante isolée, on identifie son "voisinage extérieur" $N(S)$ (les cases qui l'entourent, qui sont obligatoirement noires dans la solution candidate).
  5. **Coupe de séparation (Separator Cut)** : On ajoute dynamiquement la contrainte :
     $\sum_{(i,j) \in S} b_{i,j} + \sum_{(i,j) \in N(S)} (1 - b_{i,j}) \ge 1$
     *Signification : "La prochaine solution doit soit colorer une case de la zone en noir pour la faire disparaître, soit colorer une case de la frontière en blanc pour ouvrir un passage."*

## 4. Fonctionnement de l'heuristique
L'heuristique utilise la propagation des contraintes de vision et de voisinage.
- On force d'abord tous les indices à être blancs.
- On observe le rayon d'action de chaque indice. On compte les cases garanties d'être vues et les cases "inconnues" au bout des lignes de vue.
- Si le nombre d'éléments garantis correspond déjà à l'indice, cela signifie que le rayon de vision doit s'arrêter là : on force les cases inconnues frontalières à devenir noires.
- En parallèle, si une case inconnue possède un voisin noir, on la force en blanc (règle de non-adjacence).

## 5. Résultats obtenus
- **Comparatif PLNE** : Le solveur avec **Callback** est systématiquement $2\times$ à $6\times$ plus rapide que la formulation en Flux. Il est plus performant car le modèle de base est plus petit et la relaxation continue (LP) est beaucoup plus serrée (absence des constantes Grand-M qui affaiblissent le modèle). Les instances sont résolues en quelques millisecondes.
- **Heuristique** : Bien moins performante que sur Mosaic. Les contraintes de Range sont globales (lignes de vue sur toute la grille, connexité), rendant la propagation purement locale rapidement inefficace. Sans moteur de backtracking, l'heuristique atteint souvent son "timeout" sur les grandes instances.

## 6. Difficultés rencontrées
- **Modélisation de la visibilité** : Transformer la règle de ligne de vue (qui est conditionnelle) en contraintes linéaires strictes a nécessité de créer un système complexe de bornes supérieures et inférieures avec de nombreuses variables booléennes auxiliaires.
- **Implémentation du Callback** : 
  - La définition mathématique exacte d'une "coupe de séparation" valide pour rejeter une composante non-connexe nécessitait de la précision théorique.
  - Coder ce système dans l'interface de JuMP (`MOI.LazyConstraintCallback`, vérification de l'état entier `CALLBACK_NODE_STATUS_INTEGER`) a exigé une attention particulière à la documentation et aux types Julia.
