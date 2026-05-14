# Guide des Combos — Corely Extension

> **Version** : 2.0 | **Mise à jour** : 2026-05-14  
> **Concept** : Enchaîner les commandes slash pour des workflows automatisés

---

## Table des matières

1. [Principe des combos](#principe-des-combos)
2. [Combos de recherche documentaire](#combos-de-recherche-documentaire)
3. [Combos e-commerce](#combos-e-commerce)
4. [Combos formulaires](#combos-formulaires)
5. [Combos médias](#combos-médias)
6. [Combos analyse et audit](#combos-analyse-et-audit)
7. [Combos export et sauvegarde](#combos-export-et-sauvegarde)
8. [Combos traduction](#combos-traduction)
9. [Combos surveillance](#combos-surveillance)
10. [Créer vos propres combos](#créer-vos-propres-combos)

---

## Principe des combos

Un combo est un enchaînement de commandes slash tapées séquentiellement. Chaque commande fait UNE chose, et leur combinaison crée un workflow puissant.

```
Commande 1 → résultat dans le chat → Commande 2 → résultat → Commande 3 → ...
```

### Règles

- Une commande à la fois (pas de syntaxe spéciale)
- Chaque commande voit le résultat de la précédente
- L'ordre compte — planifiez votre workflow à l'avance
- Vous pouvez utiliser le résultat d'une commande comme paramètre de la suivante

---

## Combos de recherche documentaire

### Combo 1 : Trouver, télécharger, résumer

**But** : Récupérer un document, le comprendre rapidement.

```bash
/links document
/download https://exemple.fr/rapport.pdf mon_rapport.pdf
/summarize
```

**Déroulé :**
1. `/links document` → liste tous les PDFs de la page
2. Vous repérez celui qui vous intéresse → `/download <son_url>`
3. `/summarize` → résumé du contenu

**Cas concret — Recherche académique :**
```bash
/open https://arxiv.org/search/?query=transformers
/links document
/download https://arxiv.org/pdf/2401.12345.pdf attention_paper.pdf
/summarize
/translate fr
```

---

### Combo 2 : Veille sur une page de documentation

**But** : Comprendre une doc technique.

```bash
/open https://docs.djangoproject.com/en/stable/topics/db/queries/
/metadata
/searchpage "aggregate"
/extract #aggregation
/translate fr
```

**Déroulé :**
1. `/metadata` → contexte de la page (version, auteur)
2. `/searchpage "aggregate"` → localise la section pertinente
3. `/extract #aggregation` → extrait la section complète
4. `/translate fr` → traduction en français

---

### Combo 3 : Collecter et exporter des références

**But** : Créer une bibliographie.

```bash
/open https://scholar.google.com/scholar?q=deep+learning
/links
/tables
/export csv
/export md
```

---

## Combos e-commerce

### Combo 4 : Analyse de fiche produit

**But** : Extraire toutes les infos d'un produit.

```bash
/open https://amazon.fr/produit
/metadata
/searchpage "€"
/extract #productDescription
/media images
/download https://cdn.exemple.fr/produit-large.jpg
/screenshot
```

**Déroulé :**
1. `/metadata` → titre, description SEO, catégorie
2. `/searchpage "€"` → localise le prix
3. `/extract` → description complète
4. `/media images` → toutes les images
5. `/download` → sauvegarde la meilleure image
6. `/screenshot` → capture pour référence

---

### Combo 5 : Comparaison de prix

**But** : Comparer un produit sur plusieurs sites.

```bash
# Site 1
/open https://site1.fr/produit
/monitor .price

# Site 2
/open https://site2.fr/produit
/monitor .price

# Site 3
/open https://site3.fr/produit
/monitor .price
```

---

### Combo 6 : Vérification de stock

**But** : Surveiller la disponibilité d'un produit.

```bash
/open https://ecommerce.fr/produit-indisponible
/searchpage "rupture"
/monitor #availability-badge 300
/waitfor ".badge:contains('En stock')" 300000
```

---

## Combos formulaires

### Combo 7 : Inscription rapide

**But** : Créer un compte test rapidement.

```bash
/open https://site.com/register
/forms
/autofill
/fill input[name="email"] mon.vrai@email.com
/fill input[name="password"] MonMotDePasse123!
/click button[type="submit"]
/waitfor .success-message
/screenshot
```

**Déroulé :**
1. `/forms` → repère les champs du formulaire
2. `/autofill` → remplit automatiquement (données de test)
3. `/fill` → corrige les champs importants (email, password)
4. `/click` → soumet le formulaire
5. `/waitfor` → attend la confirmation
6. `/screenshot` → preuve de succès

---

### Combo 8 : Formulaire complexe avec vérification

**But** : Remplir un formulaire multi-étapes.

```bash
/open https://site.com/checkout

# Étape 1 : Adresse
/forms
/autofill
/click button.next-step
/waitfor #step-2

# Étape 2 : Paiement
/forms
/inspect #card-number
/fill input[name="card"] 4242424242424242
/fill input[name="expiry"] 12/28
/fill input[name="cvc"] 123
/click button.confirm-payment
```

---

### Combo 9 : Recherche avec formulaire

**But** : Remplir un formulaire de recherche et capturer les résultats.

```bash
/open https://annonces.fr
/fill input[name="category"] Informatique
/fill input[name="city"] Paris
/fill input[name="max_price"] 500
/click button[type="submit"]
/waitfor .search-results
/extract .results-container
/tables
/export csv
```

---

## Combos médias

### Combo 10 : Collecte d'images

**But** : Trouver et télécharger des images.

```bash
/open https://unsplash.com/s/photos/montagne
/media images
/download https://images.unsplash.com/photo-xxx.jpg paysage_alpes.jpg
/download https://images.unsplash.com/photo-yyy.jpg lac_montagne.jpg
```

---

### Combo 11 : Extraction galerie

**But** : Récupérer une galerie complète.

```bash
/open https://example.com/gallery
/media images
# Copiez manuellement les URLs depuis le résultat de /media
/download https://example.com/img/001.jpg
/download https://example.com/img/002.jpg
/download https://example.com/img/003.jpg
```

---

### Combo 12 : Vidéo + résumé

**But** : Analyser une page de vidéo (YouTube, Vimeo).

```bash
/open https://youtube.com/watch?v=xxxxx
/metadata
/extract #description
/translate fr
/links
```

---

## Combos analyse et audit

### Combo 13 : Audit SEO complet

**But** : Analyser le référencement d'une page.

```bash
/open https://mon-site.com
/metadata
/searchpage "keyword principale"
/links
/export json
```

**Déroulé :**
1. `/metadata` → balises title, description, OG, auteur, date
2. `/searchpage "keyword"` → vérifie la présence du mot-clé cible
3. `/links` → structure de liens internes/externes
4. `/export json` → toutes les données en JSON structuré

---

### Combo 14 : Analyse de page concurrente

**But** : Comprendre la stratégie d'un concurrent.

```bash
/open https://concurrent.fr/page-importante
/metadata
/extract body
/summarize
/tables
/export csv
/screenshot
```

---

### Combo 15 : Audit accessibilité rapide

**But** : Vérifier les bases d'accessibilité.

```bash
/open https://mon-site.com
/metadata
/searchpage "alt=\"\""
/inspect h1
/forms
# Vérifier que les formulaires ont des labels
```

---

## Combos export et sauvegarde

### Combo 16 : Sauvegarder un article pour lecture offline

**But** : Archiver un article intéressant.

```bash
/open https://blog.exemple.com/article-interessant
/summarize
/export md
/pdf "" article_interessant
```

**Déroulé :**
1. `/summarize` → vérifier que l'article est pertinent
2. `/export md` → export Markdown à copier
3. `/pdf` → sauvegarde en PDF pour lecture offline

---

### Combo 17 : Export de données structurées

**But** : Récupérer des données pour analyse.

```bash
/open https://wikipedia.org/wiki/List_of_countries_by_GDP
/tables
/export csv
/metadata     # Pour créditer la source
```

---

### Combo 18 : Conversion page → documentation

**But** : Transformer une page web en document de référence.

```bash
/open https://docs.djangoproject.com/en/stable/topics/db/queries/
/summarize
/export md
/pdf
```

---

## Combos traduction

### Combo 19 : Traduction de documentation technique

**But** : Lire une doc en français.

```bash
/open https://docs.python.org/3/library/asyncio.html
/summarize
/translate fr
```

---

### Combo 20 : Traduction + sauvegarde

**But** : Traduire et archiver.

```bash
/open https://example.com/en/article
/translate fr
# Une fois la traduction affichée...
/export md
/pdf "" article_traduit
```

---

### Combo 21 : Recherche multilingue

**But** : Chercher un terme et comprendre le contexte.

```bash
/open https://de.wikipedia.org/wiki/Künstliche_Intelligenz
/translate fr
/searchpage "Neuronale Netze"
/extract p:has("Neuronale Netze")
```

---

## Combos surveillance

### Combo 22 : Alerte prix

**But** : Être notifié d'une baisse de prix.

```bash
/open https://ecommerce.fr/produit/cher
/monitor .current-price 1800
# Vérifier le prix toutes les 30 min
```

---

### Combo 23 : Surveillance de page statut

**But** : Suivre un statut de commande/livraison.

```bash
/open https://transporteur.fr/suivi/ABC123
/monitor .status-badge 600
/screenshot
```

---

### Combo 24 : Détection de changement de contenu

**But** : Savoir quand une page est mise à jour.

```bash
/open https://site.com/annonces
/monitor .last-updated 3600
/waitfor ".new-listing" 86400000
/screenshot
```

---

## Créer vos propres combos

### Méthodologie

1. **Définissez l'objectif** — Que voulez-vous accomplir ?
2. **Identifiez les étapes** — Quelles actions sont nécessaires ?
3. **Choisissez les commandes** — Quelle commande pour chaque étape ?
4. **Ordonnez** — Dans quel ordre les exécuter ?
5. **Testez** — Exécutez le combo et ajustez

### Patterns courants

#### Pattern "Observer → Agir"
```
/monitor ou /searchpage ou /inspect → /click ou /fill ou /download
```

#### Pattern "Collecter → Exporter"
```
/extract ou /links ou /tables ou /media ou /forms → /export
```

#### Pattern "Analyser → Traduire"
```
/metadata ou /summarize ou /extract → /translate
```

#### Pattern "Naviguer → Extraire → Sauvegarder"
```
/open → /extract ou /tables → /export ou /pdf ou /screenshot
```

#### Pattern "Remplir → Valider → Capturer"
```
/forms → /autofill → /fill → /click → /waitfor → /screenshot
```

### Template pour créer un combo

```bash
# [NOM DU COMBO] : [Description]

# Étape 1 : [Action initiale]
/commande1 parametres

# Étape 2 : [Action suivante basée sur le résultat]
/commande2 parametres

# Étape 3 : [Finalisation]
/commande3 parametres

# Résultat attendu : [Ce que vous obtenez]
```

---

## Index des combos par domaine

### Recherche & Documentation
- [Combo 1](#combo-1--trouver-télécharger-résumer) : Trouver, télécharger, résumer
- [Combo 2](#combo-2--veille-sur-une-page-de-documentation) : Veille documentation
- [Combo 3](#combo-3--collecter-et-exporter-des-références) : Collecter des références

### E-commerce
- [Combo 4](#combo-4--analyse-de-fiche-produit) : Analyse fiche produit
- [Combo 5](#combo-5--comparaison-de-prix) : Comparaison de prix
- [Combo 6](#combo-6--vérification-de-stock) : Vérification de stock

### Formulaires
- [Combo 7](#combo-7--inscription-rapide) : Inscription rapide
- [Combo 8](#combo-8--formulaire-complexe-avec-vérification) : Formulaire complexe
- [Combo 9](#combo-9--recherche-avec-formulaire) : Recherche avec formulaire

### Médias
- [Combo 10](#combo-10--collecte-dimages) : Collecte d'images
- [Combo 11](#combo-11--extraction-galerie) : Extraction galerie
- [Combo 12](#combo-12--vidéo--résumé) : Vidéo + résumé

### Analyse & Audit
- [Combo 13](#combo-13--audit-seo-complet) : Audit SEO complet
- [Combo 14](#combo-14--analyse-de-page-concurrente) : Analyse concurrente
- [Combo 15](#combo-15--audit-accessibilité-rapide) : Audit accessibilité

### Export & Sauvegarde
- [Combo 16](#combo-16--sauvegarder-un-article-pour-lecture-offline) : Sauvegarde article
- [Combo 17](#combo-17--export-de-données-structurées) : Export données structurées
- [Combo 18](#combo-18--conversion-page--documentation) : Conversion documentation

### Traduction
- [Combo 19](#combo-19--traduction-de-documentation-technique) : Traduction doc technique
- [Combo 20](#combo-20--traduction--sauvegarde) : Traduction + sauvegarde
- [Combo 21](#combo-21--recherche-multilingue) : Recherche multilingue

### Surveillance
- [Combo 22](#combo-22--alerte-prix) : Alerte prix
- [Combo 23](#combo-23--surveillance-de-page-statut) : Surveillance statut
- [Combo 24](#combo-24--détection-de-changement-de-contenu) : Détection changement

---

> **Rappel** : Les combos ne sont pas des commandes spéciales. Ce sont des séquences de commandes slash que vous tapez l'une après l'autre. Maîtrisez les commandes individuelles d'abord ([Guide des Commandes Slash](GUIDE_COMMANDES_SLASH.md)), puis combinez-les.
