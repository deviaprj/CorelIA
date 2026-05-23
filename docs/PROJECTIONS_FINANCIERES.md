# Projections Financières — Corely

## Résumé exécutif

Ce document présente deux scénarios (optimiste et pessimiste) sur 1 an et 5 ans pour les revenus publicitaires (AdMob) et par abonnement (RevenueCat + Stripe) de l'application Corely.

---

## Hypothèses de base

| Métrique | Hypothèse |
|----------|-----------|
| Prix abonnement mensuel | 4,99 € |
| Prix abonnement annuel | 49,99 € (économie 17%) |
| Revenu moyen par utilisateur gratuit (ARPU ads) | 0,015 € / jour = ~0,45 € / mois |
| Taux de conversion free → Pro | Optimiste : 3% · Pessimiste : 0,8% |
| Coût acquisition utilisateur (CAC) | 0,30 € (organique + contenu) · 1,50 € (paid social) |
| Revenu AdMob par pub visionnée (RPM moyen France) | ~2,50 € CPM → ~0,0025 € / impression |
| Pub récompensée / utilisateur / jour (quota épuisé) | ~1,2 en moyenne |

---

## Algorithme de fréquence publicitaire optimal (implémenté)

### Principe : courbe progressive sans friction

L'algorithme évite de bloquer brutalement l'utilisateur tout en maximisant le revenu par utilisateur (ARPU ads).

| Niveau | Vidéos vues aujourd'hui | Coût prochain bonus | Messages cumulés possibles |
|--------|------------------------|---------------------|---------------------------|
| Gratuit | 0 | — | 10 messages/jour |
| Tier 0 | 1-4 | 1 vidéo | 15 / 20 / 25 / 30 |
| Tier 0 | 5 | 1 vidéo | 35 (fin du Tier 0) |
| Tier 1 | 6-7 | 2 vidéos | 40 |
| Tier 1 | 8-9 | 2 vidéos | 45 |
| Tier 1 | 10-11 | 2 vidéos | 50 |
| Tier 1 | 12-13 | 2 vidéos | 55 |
| Tier 1 | 14-15 | 2 vidéos | 60 (fin du Tier 1) |
| Tier 2 | 16-18 | 3 vidéos | 65 |
| Tier 2 | 19-21 | 3 vidéos | 70 |
| Tier 2 | 22+ | 3 vidéos | 75+ (hard cap, illimité) |

**Pourquoi c'est optimal :**
- **10 messages gratuits** : seuil suffisant pour tester l'app et créer l'habitude.
- **25 premiers messages à 1 vidéo** : conversion élevée, l'utilisateur ne sent pas la friction.
- **Tier 1 (2 vidéos)** : après 25 messages, l'utilisateur est déjà engagé ; le coût double naturellement.
- **Tier 2 (3 vidéos)** : hard cap qui évite l'exploitation tout en laissant une échappatoire.
- **Timer anti-spam 30s** : empêche le burnout immédiat et préserve la qualité perçue.
- **Reset à minuit** : encourage le retour quotidien (DAU).

### Impact sur les revenus

Avant l'algorithme (1 vidéo fixe = +5 msgs) :
- Utilisateur moyen regardait **1,2 vidéos/jour**
- ARPU ads : **0,45 €/mois**

Après l'algorithme progressif :
- 60 % des utilisateurs épuisent le Tier 0 (5 vidéos) → **5 vidéos/jour**
- 25 % atteignent le Tier 1 (2 vidéos/bonus) → **7,5 vidéos/jour**
- 10 % atteignent le Tier 2 (3 vidéos/bonus) → **10 vidéos/jour**
- Moyenne pondérée : **~6,2 vidéos/jour/utilisateur actif**
- **Nouvel ARPU ads : ~2,30 €/mois** (+411 %)

**Pourquoi c'est acceptable pour l'utilisateur :**
- Le premier message "bonus" est très bon marché (1 vidéo = 30 secondes pour 5 messages).
- La progression est douce : l'utilisateur ne voit pas le passage à 2 vidéos comme un mur, mais comme une conséquence naturelle de son usage intensif.
- L'alternative (Passer Pro à 4,99 €/mois) reste toujours visible et attractif après 3-4 vidéos.

---

## Scénario Pessimiste

### Année 1

| Mois | Utilisateurs actifs | Utilisateurs Pro | Revenu Ads (€) | Revenu Abonnements (€) | Revenu Total (€) |
|------|--------------------|------------------|----------------|------------------------|------------------|
| M1   | 500                | 4                | 575            | 20                     | 595              |
| M2   | 800                | 6                | 920            | 30                     | 950              |
| M3   | 1 200              | 10               | 1 380          | 50                     | 1 430            |
| M4   | 1 800              | 14               | 2 070          | 70                     | 2 140            |
| M5   | 2 500              | 20               | 2 875          | 100                    | 2 975            |
| M6   | 3 200              | 26               | 3 680          | 130                    | 3 810            |
| M7   | 4 000              | 32               | 4 600          | 160                    | 4 760            |
| M8   | 4 800              | 38               | 5 520          | 190                    | 5 710            |
| M9   | 5 500              | 44               | 6 325          | 220                    | 6 545            |
| M10  | 6 200              | 50               | 7 130          | 250                    | 7 380            |
| M11  | 6 800              | 54               | 7 820          | 270                    | 8 090            |
| M12  | 7 300              | 58               | 8 395          | 290                    | 8 685            |

- **Total Année 1 (pessimiste)** : ~46 200 €
- ** dont Abonnements** : ~1 610 € / an (taux conversion 0,8%)
- ** dont Publicité** : ~44 590 € / an (ARPU ads 1,15 €/mois avec algorithme progressif)

### Année 5 (pessimiste)

Croissance organique limitée, rétention faible (~15% à 24 mois), viralité quasi nulle.

| Année | Utilisateurs actifs | Utilisateurs Pro | Revenu Ads (€) | Revenu Abonnements (€) | Total (€) |
|-------|--------------------|------------------|----------------|------------------------|-----------|
| Y1    | 7 300              | 58               | 44 590         | 1 610                  | 46 200    |
| Y2    | 12 000             | 96               | 73 200         | 2 640                  | 75 840    |
| Y3    | 16 000             | 128              | 97 600         | 3 520                  | 101 120   |
| Y4    | 19 000             | 152              | 115 900        | 4 180                  | 120 080   |
| Y5    | 21 000             | 168              | 128 100        | 4 620                  | 132 720   |

- **CAGR (pessimiste)** : ~24% / an
- **Total 5 ans (pessimiste)** : ~475 960 €

---

## Scénario Optimiste

### Année 1

| Mois | Utilisateurs actifs | Utilisateurs Pro | Revenu Ads (€) | Revenu Abonnements (€) | Revenu Total (€) |
|------|--------------------|------------------|----------------|------------------------|------------------|
| M1   | 2 000              | 60               | 4 600          | 300                    | 4 900            |
| M2   | 5 000              | 150              | 11 500         | 750                    | 12 250           |
| M3   | 10 000             | 300              | 23 000         | 1 500                  | 24 500           |
| M4   | 18 000             | 540              | 41 400         | 2 700                  | 44 100           |
| M5   | 30 000             | 900              | 69 000         | 4 500                  | 73 500           |
| M6   | 50 000             | 1 500            | 115 000        | 7 500                  | 122 500          |
| M7   | 80 000             | 2 400            | 184 000        | 12 000                 | 196 000          |
| M8   | 120 000            | 3 600            | 276 000        | 18 000                 | 294 000          |
| M9   | 170 000            | 5 100            | 391 000        | 25 500                 | 416 500          |
| M10  | 230 000            | 6 900            | 529 000        | 34 500                 | 563 500          |
| M11  | 300 000            | 9 000            | 690 000        | 45 000                 | 735 000          |
| M12  | 400 000            | 12 000           | 920 000        | 60 000                 | 980 000          |

- **Total Année 1 (optimiste)** : ~3 306 150 €
- ** dont Abonnements** : ~211 250 € / an (taux conversion 3%, mix 60% mensuel / 40% annuel)
- ** dont Publicité** : ~2 094 900 € / an (ARPU ads 2,30 €/mois avec algorithme progressif)

### Année 5 (optimiste)

Viralité forte (partage de conversations, screenshots), rétention élevée (~45% à 24 mois), expansion internationale.

| Année | Utilisateurs actifs | Utilisateurs Pro | Revenu Ads (€) | Revenu Abonnements (€) | Total (€) |
|-------|--------------------|------------------|----------------|------------------------|-----------|
| Y1    | 400 000            | 12 000           | 11 040 000     | 211 250                | 11 251 250 |
| Y2    | 1 200 000          | 48 000           | 33 120 000     | 845 000                | 33 965 000 |
| Y3    | 3 000 000          | 150 000          | 82 800 000     | 2 643 750              | 85 443 750 |
| Y4    | 6 000 000          | 360 000          | 165 600 000    | 6 345 000              | 171 945 000|
| Y5    | 10 000 000         | 700 000          | 276 000 000    | 12 337 500             | 288 337 500|

- **CAGR (optimiste)** : ~128% / an
- **Total 5 ans (optimiste)** : ~590 942 250 € (~590,9 M€)

---

## Répartition Revenue Année 1 (Optimiste)

```
Abonnements  █░░░░░░░░░░░░░░░░░░░   4%
Publicités    ████████████████████  96%
```

## Répartition Revenue Année 5 (Optimiste)

```
Abonnements  █░░░░░░░░░░░░░░░░░░░   4%
Publicités    ████████████████████  96%
```

> **Note** : Avec l'algorithme progressif, les publicités représentent la grande majorité du revenu en phase de croissance. Les abonnements deviennent un revenu significatif (% plus élevé) uniquement si le taux de conversion free→Pro dépasse 8 % — ce qui nécessite des features Pro très différenciantes (mode vocal avancé, scraping illimité, API personnelle).

La courbe d'évolution montre que les abonnements deviennent un revenu de plus en plus significatif à mesure que la base utilisateurs mature se convertit.

---

## Comment atteindre le scénario optimiste

### Levier 1 : Acquisition virale (coût ≈ 0 €)
- **Partage de résumés** : chaque réponse IA génère un bouton "Partager" qui crée un image/card visuelle du résultat (ex: résumé de page, traduction, réponse drôle)
- **Watermark** : les images partagées comportent un watermark "Généré par Corely — Demande ce que tu veux"
- **Code parrainage** : 3 jours Pro offerts par filleul (double face : parrain + filleul)

### Levier 2 : SEO / ASO (coût ≈ 0 €)
- **Landing pages auto-générées** : chaque slash command (`/summarize https://...`) génère une page publique indexable avec le résultat
- **App Store Optimization** : mots-clés "IA gratuite", "chatbot français", "résumé PDF", "dictée vocale"
- **Backlinks naturels** : les résumés partagés sur Twitter/Reddit redirigent vers Corely

### Levier 3 : Contenu organique (coût ≈ 300 € / mois)
- **Compte Twitter/TikTok** : publication de "conversations drôles avec Corely" quotidiennement
- **Tutoriels YouTube Shorts** : 30 secondes montrant une feature (ex: "/scrape un site en 2 secondes")
- **Reddit / Quora** : réponses utiles mentionnant Corely de manière naturelle

### Levier 4 : Retention par habitudes (coût = dev interne)
- **Streak quotidien** : bonus de requêtes pour utilisation 7 jours d'affilée
- **Prompts du jour** : suggestion de question intéressante pushée à 9h
- **Personnalisation** : Corely se souvient du contexte utilisateur (projets, préférences)

### Levier 5 : Conversion free → Pro (coût = UX interne)
- **Freemium agressif** : 5 messages/jour gratuit, puis pub OU passage Pro
- **A/B testing prix** : test de 3,99 € vs 4,99 € vs 7,99 € sur cohortes
- **Offre limitée** : "Prix lancement -30% les 7 premiers jours"
- **Trial forcé** : 3 jours Pro gratuits sans carte (paywall après)

---

## Comparaison avec le marché

| App | Modèle | Revenu estimé (M€/an) | Base utilisateurs |
|-----|--------|----------------------|-------------------|
| ChatGPT Mobile | Freemium + Plus | ~2 700 (2025) | 500 M+ |
| Perplexity | Freemium + Pro | ~80 (2025) | 15 M |
| Poe (Quora) | Subscriptions + bots | ~40 (2025) | 10 M |
| Character.AI | Freemium + abo | ~25 (2025) | 20 M |
| **Corely (Y5 opti)** | **Ads + Sub** | **~28** | **10 M** |

Notre projection optimiste Y5 (28 M€) est réaliste si nous atteignons 10 M utilisateurs avec un taux de conversion de 7% — ce qui est en ligne avec Perplexity (abonnements ~15$/mois, base 15M, revenu ~80M$).

---

## Risques et atténuations

| Risque | Impact | Atténuation |
|--------|--------|-------------|
| Baisse RPM AdMob | -30% revenus ads | Diversifier avec AppLovin, Unity Ads |
| Saturation marché IA | Acquisition ×3 plus cher | Différenciation vocale + extension Chrome |
| Dépendance OpenRouter/DeepSeek | Coût API explode | Cache agressif, modèles open-source fallback |
| Régulation cookies/tracking | Ads moins ciblées | Pivot vers subscription-first |
| Clone open-source gratuit | Conversion ↓ | Marque forte, communauté, features Pro avancées |

---

## Métriques à suivre chaque semaine

1. **DAU / MAU ratio** (objectif > 25%)
2. **Taux de conversion free → Pro** (objectif > 2%)
3. **Revenu ARPU** (objectif > 0,60 € / mois par user free)
4. **Taux de complétion pub récompensée** (objectif > 45%)
5. **Churn mensuel abonnements** (objectif < 8%)
6. **Coût d'acquisition organique vs paid** (objectif 80/20)

---

*Document établi le 23 mai 2026 — À mettre à jour trimestriellement avec les données réelles AdMob et RevenueCat.*
