# Notes de présentation : Résolution du jeu Mosaic

Ce document résume les points clés de l'implémentation du jeu Mosaic pour la soutenance, conformément aux attentes.

## 1. Génération des instances
- **Principe** : L'algorithme part de la solution pour créer un problème valide.
- **Étapes** :
  1. On génère aléatoirement une grille complète composée uniquement de cases noires (1) et blanches (0).
  2. Pour chaque case de la grille, on calcule la valeur de son "indice" (le nombre de cases noires présentes dans son voisinage $3 \times 3$, incluant la case elle-même).
  3. On applique ensuite un "masque" basé sur un paramètre de **densité** (ex: 0.5) : chaque indice a une probabilité d'être conservé ou effacé. La grille finale obtenue est l'instance à résoudre.

## 2. Choix de modélisation (PLNE)
La modélisation de Mosaic est très directe car toutes les contraintes sont purement locales et linéaires.
- **Variables de décision** : 
  - $x_{i,j} \in \{0, 1\}$ pour chaque case, valant 1 si la case est noire, 0 si elle est blanche.
- **Contraintes** : 
  - Pour chaque case contenant un indice $v_{i,j}$, la somme des variables de son voisinage $3 \times 3$ doit être strictement égale à $v_{i,j}$.
  - $\sum_{k=\max(1, i-1)}^{\min(n, i+1)} \sum_{l=\max(1, j-1)}^{\min(m, j+1)} x_{k,l} = v_{i,j}$
- **Objectif** : $\min 0$ (C'est un pur problème de satisfaction/faisabilité, il n'y a pas de fonction de coût à minimiser).

*(Note : Le jeu Mosaic n'implique aucune notion de connexité, un callback n'est donc pas nécessaire ici).*

## 3. Fonctionnement de l'heuristique
L'heuristique est basée sur un algorithme de **propagation de contraintes locales**.
- **Algorithme** :
  - La grille commence avec toutes ses cases dans l'état "inconnu".
  - À chaque itération, pour chaque case contenant un indice, on compte ses voisins déjà confirmés "noirs" et ses voisins restants "inconnus".
  - **Déduction 1** : Si le nombre de cases noires *restantes à placer* correspond exactement au nombre de voisins *inconnus*, on force tous ces voisins inconnus à l'état "noir".
  - **Déduction 2** : Si le quota de cases noires est déjà atteint pour l'indice (le reste à placer est de 0), tous les voisins *inconnus* deviennent "blancs".
- On itère ces déductions jusqu'à ce que plus aucun changement ne soit possible. Si la grille n'est pas encore résolue, on effectue des choix aléatoires (greedy fallback) pour débloquer la situation.

## 4. Résultats obtenus
- **CPLEX** : Trouve la solution optimale quasi-instantanément. Le solveur est très à l'aise grâce à la forte densité des contraintes linéaires très locales.
- **Heuristique** : Extrêmement rapide et performante sur Mosaic. La propagation de contraintes permet de résoudre la grande majorité des grilles naturellement, de manière similaire à un humain.

## 5. Difficultés rencontrées
- La modélisation mathématique de Mosaic n'a pas présenté de difficultés majeures, la formulation étant naturelle.
- La principale subtilité se situe au niveau de l'heuristique pour les instances générées avec une très faible densité d'indices. Sur ces grilles, la propagation locale seule peut se retrouver bloquée, forçant l'heuristique à deviner. Ne disposant pas d'un système de *backtracking* profond, l'heuristique peut parfois échouer sur les grilles très complexes/vides dans le temps imparti.
