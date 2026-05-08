# Notes de présentation : Résolution du jeu Galaxies

Ce document résume les points clés de l'implémentation du jeu Galaxies pour la soutenance. Étant noté de difficulté 9, c'est le jeu le plus complexe du projet, exigeant une gestion fine de la symétrie centrale et l'utilisation impérative de callbacks pour garantir la connexité des régions.

## 1. Génération des instances
- **Principe** : Construire progressivement une grille valide et symétrique, puis extraire la position des noyaux (points) pour l'instance.
- **Étapes** :
  1. La grille commence entièrement "vide". On sélectionne une case vide au hasard.
  2. On place un nouveau point ("galaxie") autour de cette case (au centre, sur une arête ou sur un coin).
  3. On effectue une **croissance de région symétrique** : on ajoute itérativement des paires de cases (une case et son image symétrique) adjacentes à la région, tant qu'elles sont libres.
  4. On répète l'opération jusqu'à ce que la grille soit entièrement couverte.
  5. Une vérification finale garantit que chaque région générée est bien d'un seul tenant (connexe).
  6. L'instance produite est simplement la grille avec la coordonnée des points (l'affectation générée devient la solution unique).

## 2. Choix de modélisation (Modèles PLNE)
La difficulté majeure de Galaxies est que les points de symétrie peuvent se situer entre deux cases ou à l'intersection de quatre cases. Nous avons utilisé un système de **coordonnées doublées** pour ne manipuler que des entiers.

- **Variables de décision** : 
  - $x_{i,j,k} \in \{0, 1\}$, valant 1 si la case $(i,j)$ appartient à la galaxie $k$, et 0 sinon.
- **Contraintes partagées** : 
  - (C1) **Partition complète** : Chaque case appartient à exactement une galaxie ($\sum_k x_{i,j,k} = 1$).
  - (C2) **Ancrage** : Les cases qui "touchent" le point central d'une galaxie $k$ lui appartiennent obligatoirement.
  - (C3) **Symétrie rotationnelle** : Pour chaque galaxie $k$, si une case $(i,j)$ possède une image symétrique $(i',j')$ dans la grille par rapport au point $k$, alors $x_{i,j,k} = x_{i',j',k}$ (si l'image tombe en dehors de la grille, $x_{i,j,k}$ est forcé à 0).
- **Objectif** : $\min 0$ (C'est un problème de faisabilité).

*(La connexité est omise du modèle de base et gérée dynamiquement).*

## 3. Fonctionnement du Callback (Lazy Constraints)
Comme pour Range, la connexité des galaxies ne peut pas s'exprimer par un nombre polynomial de contraintes de base sans variables complexes.
- **Algorithme** :
  1. Lorsqu'une solution candidate entière est proposée, on vérifie la connexité de *chaque galaxie séparément* à l'aide d'un parcours BFS depuis sa case d'ancrage.
  2. Si des cases attribuées à la galaxie $k$ ne sont pas atteignables, elles forment une **composante isolée** $S$.
  3. **Coupe de séparation (Separator Cut)** : On ajoute une contrainte interdisant cette configuration isolée :
     $\sum_{(i,j) \in S} (1 - x_{i,j,k}) + \sum_{(i,j) \in N(S)} x_{i,j,k} \ge 1$
     *Signification : La composante $S$ doit perdre au moins une case, ou son voisinage direct $N(S)$ doit gagner au moins une case pour la galaxie $k$.*
  4. **Optimisation** : Si la composante isolée $S$ possède une image symétrique valide $S'$ par rapport au noyau $k$, on ajoute instantanément la même coupe pour la zone $S'$ afin d'aider CPLEX.

## 4. Fonctionnement de l'heuristique
Contrairement à Range, l'heuristique de Galaxies repose sur une **propagation de symétrie**.
- **Logique** : Pour chaque case, on conserve une liste des galaxies "candidates".
- **Déduction** : On regarde l'image symétrique de la case par rapport au centre d'un candidat $k$. Si cette case image est déjà affectée à une *autre* galaxie, alors la galaxie $k$ est éliminée des candidats.
- **Affectation** : Dès qu'une case n'a plus qu'un seul candidat valide, on l'affecte (ainsi que son image symétrique).
- **Greedy Fallback** : Si la propagation est bloquée, on affecte en priorité la case qui possède le moins de candidats restants. Ce cycle est répété jusqu'à la résolution.

## 5. Résultats obtenus
- **CPLEX (avec Callback)** : Excellentes performances. Le solveur résout **100%** des instances instantanément (en moyenne $< 0.05$s, avec un maximum de $0.066$s sur les grilles $10 \times 10$).
- **Heuristique** : Performances spectaculaires. L'heuristique parvient à résoudre **94% (17 sur 18)** des grilles complexes quasi-instantanément, et n'a échoué que sur une seule grille de taille $10 \times 10$. Cela démontre que la symétrie centrale de Galaxies est une contrainte locale beaucoup plus "forte" et contraignante que les lignes de visibilité de Range.

## 6. Difficultés rencontrées
- **Gestion des points centraux non-entiers** : Manipuler des symétries dont le centre est au coin d'une case impliquait des calculs sur des demi-entiers. La création d'un référentiel à "coordonnées doublées" a permis d'esquiver cette complexité.
- **Volume des variables PLNE** : Le modèle nécessite 3 dimensions ($x_{i,j,k}$), créant un grand volume de variables pour CPLEX. La simplification consistant à forcer à 0 toutes les variables dont la symétrie "sort" de la grille a été cruciale pour réduire l'espace de recherche.
- **Heuristique sur la connexité** : L'heuristique locale se fie uniquement à la symétrie et ne sait pas anticiper la connexité. Son succès prouve que sur les grilles générées de manière valide, la symétrie contraint tellement la disposition que la connexité en découle naturellement sans avoir à l'expliciter de façon complexe dans l'heuristique.
