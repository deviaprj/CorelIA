# Projections Financières — Corely

## Résumé exécutif

Ce document présente deux scénarios (optimiste et pessimiste) sur 1 an et 5 ans pour les revenus publicitaires (AdMob) et par abonnement (RevenueCat + Stripe) de l'application Corely.

---

## Hypothèses de base

| Métrique | Hypothèse |
|----------|-----------|
| Prix abonnement mensuel | 9,99 € |
| Prix abonnement annuel | 79,99 € (économie 33%) |
| Revenu moyen par utilisateur gratuit (ARPU ads) | 0,015 € / jour = ~0,45 € / mois |
| Taux de conversion free → Pro | Optimiste : 3% · Pessimiste : 0,8% |
| Coût acquisition utilisateur (CAC) | 0,30 € (organique + contenu) · 1,50 € (paid social) |
| Revenu AdMob par pub visionnée (RPM moyen France) | ~2,50 € CPM → ~0,0025 € / impression |
| Pub récompensée / utilisateur / jour (quota épuisé) | ~1,2 en moyenne |

---

## Analyse des coûts API post-optimisation (V16)

### Pourquoi le prix doit changer : 4,99 € était une perte

L'optimisation des modèles IA (session V16) change radicalement les coûts, mais révèle aussi que **4,99 €/mois ne couvrait pas les frais réels**.

| Modèle | Usage | Coût |
|--------|-------|------|
| **deepseek-v4-flash** | Texte général, 70-80 % des requêtes | **Gratuit** |
| **deepseek-v4-pro** | Documents, extraction, multi-step (15-20 %) | ~0,50 $ / M tokens |
| **deepseek-reasoner** | Raisonnement profond (5-10 %) | ~2,00 $ / M tokens |
| **OpenRouter Pro** | Mistral-Large, GPT-4o-mini, vocal | ~2-8 $ / M tokens |

### Coût réel par utilisateur Pro (mensuel)

Un utilisateur Pro moyen envoie ~60 messages/jour (usage illimité = plus intensif) :

| Poste | Calcul | Montant |
|-------|--------|---------|
| Tokens API / mois | 60 msg × 30j × 2000 tokens | 3,6 M tokens |
| Coût API OpenRouter (50 %) | 1,8 M tokens × 4 $/M | **~6,70 €** |
| Coût API DeepSeek Pro (50 %) | 1,8 M tokens × 0,80 $/M | **~1,35 €** |
| Infrastructure Firebase | Bande passante, stockage, functions | **~1,50 €** |
| Support & opérations | Amorti (serveur, monitoring) | **~0,50 €** |
| **Coût total par Pro user** | | **~10,05 €/mois** |

**Verdict à 4,99 € : perte de ~5 € par utilisateur Pro/mois.**
**Verdict à 9,99 € : marge de ~0 € (seuil de rentabilité, utilisateur moyen).**
**Verdict à 12,99 € : marge de ~3 €/mois (30 %).**

> **Décision** : Le prix de 4,99 € était irréaliste. À ce tarif, chaque nouvel abonné Pro creuse un trou financier. Le prix minimum viable est **9,99 €/mois** (seuil de rentabilité sur l'utilisateur moyen). Le prix cible pour une marge saine est **12,99 €/mois**, positionné comme 35 % moins cher que ChatGPT Plus (22,99 €).

### Impact post-optimisation sur les coûts globaux

| Poste | Avant (€) | Après (€) | Réduction |
|-------|-----------|-----------|-----------|
| DeepSeek API | 120 000 | **28 000** | -77 % (flash gratuit) |
| OpenRouter API | 85 000 | **55 000** | -35 % (meilleur routing vocal) |
| Infra Firebase | 15 000 | **22 000** | +47 % (plus d'users, stockage images) |
| **Total coûts API** | **220 000** | **105 000** | **-52 %** |

L'optimisation divise les coûts API par deux, mais le vrai levier économique reste le **prix d'abonnement correct**.

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
| M1   | 500                | 4                | 575            | 40                     | 615              |
| M2   | 800                | 6                | 920            | 60                     | 980              |
| M3   | 1 200              | 10               | 1 380          | 100                    | 1 480            |
| M4   | 1 800              | 14               | 2 070          | 140                    | 2 210            |
| M5   | 2 500              | 20               | 2 875          | 200                    | 3 075            |
| M6   | 3 200              | 26               | 3 680          | 260                    | 3 940            |
| M7   | 4 000              | 32               | 4 600          | 320                    | 4 920            |
| M8   | 4 800              | 38               | 5 520          | 380                    | 5 900            |
| M9   | 5 500              | 44               | 6 325          | 440                    | 6 765            |
| M10  | 6 200              | 50               | 7 130          | 500                    | 7 630            |
| M11  | 6 800              | 54               | 7 820          | 540                    | 8 360            |
| M12  | 7 300              | 58               | 8 395          | 580                    | 8 975            |

- **Total Année 1 (pessimiste)** : ~47 900 €
- ** dont Abonnements** : ~3 560 € / an (taux conversion 0,8%, prix 9,99 €)
- ** dont Publicité** : ~44 590 € / an (ARPU ads 1,15 €/mois avec algorithme progressif)
- **Marge** : ~38 300 € après coûts API + infra (vs 33 000 € à 4,99 €)

### Année 5 (pessimiste)

Croissance organique limitée, rétention faible (~15% à 24 mois), viralité quasi nulle.

| Année | Utilisateurs actifs | Utilisateurs Pro | Revenu Ads (€) | Revenu Abonnements (€) | Total (€) |
|-------|--------------------|------------------|----------------|------------------------|-----------|
| Y1    | 7 300              | 58               | 44 590         | 3 560                  | 48 150    |
| Y2    | 12 000             | 96               | 73 200         | 5 890                  | 79 090    |
| Y3    | 16 000             | 128              | 97 600         | 7 850                  | 105 450   |
| Y4    | 19 000             | 152              | 115 900        | 9 320                  | 125 220   |
| Y5    | 21 000             | 168              | 128 100        | 10 300                 | 138 400   |

- **CAGR (pessimiste)** : ~24% / an
- **Total 5 ans (pessimiste)** : ~496 310 €

---

## Scénario Optimiste

### Année 1

| Mois | Utilisateurs actifs | Utilisateurs Pro | Revenu Ads (€) | Revenu Abonnements (€) | Revenu Total (€) |
|------|--------------------|------------------|----------------|------------------------|------------------|
| M1   | 2 000              | 60               | 4 600          | 600                    | 5 200            |
| M2   | 5 000              | 150              | 11 500         | 1 500                  | 13 000           |
| M3   | 10 000             | 300              | 23 000         | 3 000                  | 26 000           |
| M4   | 18 000             | 540              | 41 400         | 5 400                  | 46 800           |
| M5   | 30 000             | 900              | 69 000         | 9 000                  | 78 000           |
| M6   | 50 000             | 1 500            | 115 000        | 15 000                 | 130 000          |
| M7   | 80 000             | 2 400            | 184 000        | 24 000                 | 208 000          |
| M8   | 120 000            | 3 600            | 276 000        | 36 000                 | 312 000          |
| M9   | 170 000            | 5 100            | 391 000        | 51 000                 | 442 000          |
| M10  | 230 000            | 6 900            | 529 000        | 69 000                 | 598 000          |
| M11  | 300 000            | 9 000            | 690 000        | 90 000                 | 780 000          |
| M12  | 400 000            | 12 000           | 920 000        | 120 000                | 1 040 000        |

- **Total Année 1 (optimiste)** : ~3 518 000 €
- ** dont Abonnements** : ~424 500 € / an (taux conversion 3%, prix 9,99 €)
- ** dont Publicité** : ~2 094 900 € / an (ARPU ads 2,30 €/mois avec algorithme progressif)
- **Marge** : ~2 720 000 € après coûts API + infra (vs 2 534 000 € à 4,99 €)

### Année 5 (optimiste)

Viralité forte (partage de conversations, screenshots), rétention élevée (~45% à 24 mois), expansion internationale. Prix maintenu à 9,99 € avec offre annuelle à 79,99 €.

| Année | Utilisateurs actifs | Utilisateurs Pro | Revenu Ads (€) | Revenu Abonnements (€) | Total (€) |
|-------|--------------------|------------------|----------------|------------------------|-----------|
| Y1    | 400 000            | 12 000           | 11 040 000     | 424 500                | 11 464 500 |
| Y2    | 1 200 000          | 48 000           | 33 120 000     | 1 698 000              | 34 818 000 |
| Y3    | 3 000 000          | 150 000          | 82 800 000     | 5 306 250              | 88 106 250 |
| Y4    | 6 000 000          | 360 000          | 165 600 000    | 12 735 000             | 178 335 000|
| Y5    | 10 000 000         | 700 000          | 276 000 000    | 24 745 000             | 300 745 000|

- **CAGR (optimiste)** : ~128% / an
- **Total 5 ans (optimiste)** : ~614 469 000 € (~614 M€)

---

## Répartition Revenue Année 1 (Optimiste)

```
Abonnements  ██░░░░░░░░░░░░░░░░░░  12%
Publicités    ███████████████████░  88%
```

## Répartition Revenue Année 5 (Optimiste)

```
Abonnements  ███░░░░░░░░░░░░░░░░░   8%
Publicités    ███████████████████░  92%
```

> **Note** : Le passage de 4,99 € à 9,99 € double la part des abonnements (de 4 % à 12 % en Y1) sans réduire significativement la conversion, car le free tier reste très généreux (10 messages + pub récompensée). Les abonnements deviennent un revenu significatif si le taux de conversion free→Pro dépasse 5 % — ce qui est réalisable avec les features Pro différenciantes (mode vocal avancé, scraping illimité, API personnelle).

> **Note coûts** : À 4,99 €, chaque utilisateur Pro était potentiellement déficitaire (~10 € de coûts API + infra vs 4,99 € de revenu). À 9,99 €, l'utilisateur Pro moyen devient rentable. Le free tier (publicité) finance l'acquisition ; le Pro finance la marge.

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
- **Freemium agressif** : 10 messages/jour gratuit, puis pub récompensée OU passage Pro
- **A/B testing prix** : test de 7,99 € vs 9,99 € vs 12,99 € sur cohortes (NE PAS tester en dessous de 7,99 €)
- **Offre lancement** : "9,99 € les 3 premiers mois, puis 12,99 €" (ancrage prix)
- **Annual push** : 79,99 €/an affiché comme "économisez 40 €" (vs mensuel)
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

## Monétisation des Insights de Données (Nouveau — Modèle Consenti)

### Principe : vendre des tendances, pas des individus

Avec le consentement explicite des utilisateurs (opt-in RGPD), Corely collecte des **insights agrégés et anonymisés** :
- Tendances de recherche par région/semaine (ex: "vols Paris-Londres en hausse de 30% cette semaine")
- Usage des features (ex: "65% des utilisateurs utilisent le mode vocal après 7 jours")
- Mapping intent-action (ex: "80% des requêtes 'résume' mènent à `/summarize`")
- Saisonnalité (ex: "pic d'usage à 21h le week-end")

### Tarification par utilisateur actif consentant

| Niveau d'insight | Prix / user / mois | Description |
|------------------|-------------------|-------------|
| Insights de base | **0,05 €** | Tendances de recherche + usage features (agrégées) |
| Insights avancés | **0,15 €** | + démographie (langue, device, heures de pic) |
| Insights premium | **0,30 €** | + intent mapping détaillé + rapports hebdomadaires |

### Hypothèses d'opt-in

| Hypothèse | Taux |
|-----------|------|
| Utilisateurs actifs consentant (Niveau 1) | **25%** de la base |
| Utilisateurs actifs consentant (Niveau 2) | **10%** de la base |
| Moyenne pondérée de revenu data / user / mois | **~0,08 €** |

### Projections Revenus Data

#### Scénario Pessimiste

| Année | Utilisateurs actifs | Consentants (25%) | Revenu Data (€) |
|-------|--------------------|-------------------|-----------------|
| Y1    | 7 300              | 1 825             | 1 752           |
| Y2    | 12 000             | 3 000             | 2 880           |
| Y3    | 16 000             | 4 000             | 3 840           |
| Y4    | 19 000             | 4 750             | 4 560           |
| Y5    | 21 000             | 5 250             | 5 040           |

**Total 5 ans (pessimiste)** : ~18 072 €

#### Scénario Optimiste

| Année | Utilisateurs actifs | Consentants (25% N1 + 10% N2) | Revenu Data (€) |
|-------|--------------------|-------------------------------|-----------------|
| Y1    | 400 000            | 100 000 (25%) + 40 000 (10%) | 96 000          |
| Y2    | 1 200 000          | 300 000 + 120 000             | 288 000         |
| Y3    | 3 000 000          | 750 000 + 300 000             | 720 000         |
| Y4    | 6 000 000          | 1 500 000 + 600 000           | 1 440 000       |
| Y5    | 10 000 000         | 2 500 000 + 1 000 000         | 2 400 000       |

**Total 5 ans (optimiste)** : ~4 944 000 € (~4,9 M€)

> **Note** : Les revenus data représentent **~0,8% du revenu total** en scénario optimiste. Ce n'est pas un levier majeur de revenu, mais c'est un **levier de marge** à coût quasi nul (infrastructure déjà amortie par les autres services) et un **différenciateur B2B** : les insights Corely peuvent être vendus comme API à des entreprises françaises qui n'ont pas accès aux données Google/Apple.

### Acheteurs cibles

| Segment | Besoin | Prix annuel |
|---------|--------|-------------|
| Agences médias | Tendances search pour ciblage | 5 000 € |
| Instituts de sondage | Données comportementales IA | 10 000 € |
| E-commerçants | Intent mapping produits | 3 000 € |
| Editeurs d'apps | Benchmark usage features | 2 000 € |

### Coût et marge

- **Coût marginal** : ~0 € (données déjà collectées pour l'apprentissage de Corely)
- **Marge brute** : **~95%** (seuls les coûts API backend de servage des données)
- **Investissement initial** : développement du backend data_insights.py (~2 jours)

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
