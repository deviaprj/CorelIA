# Guide des Commandes Slash — Corely

> **Version** : 2.1 | **Mise à jour** : 2026-05-21  
> **Disponible sur** : Extension Chrome (contrôle du navigateur) + Mobile/Web (avec URL directe)

---

## Table des matières

1. [Introduction](#introduction)
2. [Navigation](#navigation)
3. [Extraction de contenu](#extraction-de-contenu)
4. [Analyse de page](#analyse-de-page)
5. [Scraping intelligent](#scraping-intelligent)
6. [Interaction DOM](#interaction-dom)
7. [Médias et fichiers](#médias-et-fichiers)
8. [Automatisation](#automatisation)
9. [Export et conversion](#export-et-conversion)
10. [Surveillance](#surveillance)
11. [Traduction et recherche](#traduction-et-recherche)
12. [Combos de commandes](#combos-de-commandes)
13. [Référence rapide](#référence-rapide)

---

## Introduction

Les commandes slash permettent de contrôler le navigateur et d'interagir avec les pages web directement depuis le chat Corely. Tapez `/` dans la zone de saisie pour voir la palette de commandes.

### Syntaxe générale

```
/commande <paramètre obligatoire> [paramètre optionnel]
```

### Règles importantes

- **Extension Chrome** — Les commandes de contrôle navigateur (`/click`, `/scroll`, `/fill`) nécessitent l'extension installée
- **Commandes universelles** — `/scrape`, `/summarize`, `/extract`, `/links`, `/metadata` fonctionnent sur **toutes les plateformes** (mobile, web, extension) lorsqu'une URL est fournie
- **Timeout de 10 secondes** — Si une action ne répond pas dans les 10s, elle est annulée
- **Une commande à la fois** — Chaque commande est exécutée séquentiellement
- **Les combos** — Enchaînez plusieurs commandes pour des workflows complexes

---

## Navigation

### `/open` — Ouvrir une URL

Ouvre un nouvel onglet avec l'URL spécifiée.

```
/open <url>
```

**Exemples :**
```bash
/open https://github.com/flutter/flutter
/open https://docs.python.org/3/
```

**Cas d'usage :**
- Accéder rapidement à une documentation
- Ouvrir un lien mentionné par Corely
- Naviguer vers une page pour l'analyser ensuite

**Combo naturel :**
```bash
/open https://news.ycombinator.com
/summarize            # Résumer la page d'accueil HN
```

---

### `/back` — Page précédente

Revient à la page précédente dans l'historique de l'onglet.

```
/back
```

**Cas d'usage :**
- Revenir après avoir suivi un lien
- Retour à une page de résultats de recherche

---

### `/forward` — Page suivante

Avance à la page suivante dans l'historique de l'onglet.

```
/forward
```

---

### `/scroll` — Défiler la page

Fait défiler la page courante.

```
/scroll [up|down] [pixels]
```

**Exemples :**
```bash
/scroll down 500      # Défile de 500px vers le bas
/scroll up 300        # Défile de 300px vers le haut
/scroll down          # Défile de 500px vers le bas (par défaut)
```

**Cas d'usage :**
- Parcourir de longs articles
- Positionner la vue avant une capture d'écran

**Combo :**
```bash
/scroll down 800
/screenshot           # Capturer la section visible après défilement
```

---

## Extraction de contenu

### `/extract` — Extraire le texte

Extrait le contenu texte d'un élément HTML via un sélecteur CSS, ou d'une URL distante.

```
/extract [url] [selector]
```

**Exemples :**
```bash
/extract article                          # Extrait le contenu de <article> (extension)
/extract .main-content                    # Extrait la classe main-content (extension)
/extract https://example.com .article     # Scrape + extrait sélecteur (toutes plateformes)
/extract https://example.com              # Scrape tout le contenu (toutes plateformes)
```

**Cas d'usage :**
- Extraire le texte d'un article pour le sauvegarder
- Récupérer le contenu d'une section spécifique
- Préparer du texte pour traduction

**Combo :**
```bash
/extract .recipe-ingredients
/translate en                              # Traduire les ingrédients en anglais
```

---

### `/links` — Extraire les liens

Extrait tous les liens d'une page (courante ou URL), avec filtrage par type.

```
/links [url] [all|video|image|audio|document]
```

**Exemples :**
```bash
/links                   # Tous les liens de la page courante (extension)
/links video             # Liens vidéo de la page courante (extension)
/links https://example.com document  # Liens document d'une URL (toutes plateformes)
/links https://example.com           # Tous les liens d'une URL (toutes plateformes)
```

**Cas d'usage :**
- Trouver tous les PDFs téléchargeables sur une page
- Lister les vidéos disponibles
- Auditer les liens d'un site

**Combo :**
```bash
/links document
/download https://example.com/rapport.pdf mon_rapport.pdf
```

---

### `/forms` — Extraire les formulaires

Liste tous les formulaires présents sur la page avec leurs champs.

```
/forms [index]
```

**Exemples :**
```bash
/forms                   # Lister tous les formulaires
/forms 0                 # Détails du premier formulaire
```

**Cas d'usage :**
- Comprendre la structure d'un formulaire avant de le remplir
- Identifier les champs obligatoires
- Préparer un autofill ciblé

**Combo :**
```bash
/forms                   # Voir les formulaires disponibles
/autofill                # Remplir automatiquement tous les champs
```

---

### `/tables` — Extraire les tableaux

Extrait les données des tableaux HTML.

```
/tables [index]
```

**Exemples :**
```bash
/tables                  # Tous les tableaux
/tables 2                # Affiche le 3ème tableau en détail
```

**Cas d'usage :**
- Extraire des données financières
- Récupérer des comparatifs
- Collecter des statistiques

**Combo :**
```bash
/tables
/export csv              # Exporter en CSV pour Excel
```

---

### `/media` — Extraire les médias

Liste les images, vidéos et fichiers audio de la page.

```
/media [images|videos|audio|all]
```

**Exemples :**
```bash
/media                   # Tous les médias
/media images            # Images uniquement (taille, dimensions)
/media videos            # Vidéos uniquement
```

**Cas d'usage :**
- Trouver l'URL d'une image pour la télécharger
- Identifier les vidéos intégrées
- Récupérer une galerie photo

**Combo :**
```bash
/media images
/download https://example.com/photo-hd.jpg
```

---

## Analyse de page

### `/summarize` — Résumer la page

Extrait le contenu principal et demande à l'IA de le résumer.

```
/summarize [url]
```

**Exemples :**
```bash
/summarize               # Résumer la page courante (extension uniquement)
/summarize https://example.com/article  # Résumer une URL (toutes plateformes)
```

**Cas d'usage :**
- Résumer un long article
- Avoir l'essentiel d'une page de documentation
- Synthétiser une page de résultats

**Combo :**
```bash
/summarize               # Résumer la page
/pdf                     # Imprimer le résumé en PDF
```

---

### `/metadata` — Métadonnées de la page

Affiche les métadonnées SEO, l'auteur, la date de publication, les titres, etc.

```
/metadata [url]
```

**Exemples :**
```bash
/metadata                # Métadonnées de la page courante (extension)
/metadata https://example.com  # Métadonnées d'une URL (toutes plateformes)
```

**Cas d'usage :**
- Vérifier la crédibilité d'un article
- Analyser le SEO d'une page
- Extraire la date de publication
- Obtenir les mots-clés d'une page

**Combo :**
```bash
/metadata                # Voir les infos de la page
/export json             # Exporter les métadonnées en JSON
```

---

### `/searchpage` — Rechercher dans la page

Recherche un terme dans le contenu textuel de la page.

```
/searchpage <terme>
```

**Exemples :**
```bash
/searchpage GDPR              # Trouver les mentions du RGPD
/searchpage prix              # Trouver toutes les mentions de prix
/searchpage "contact email"   # Chercher une expression
```

**Cas d'usage :**
- Vérifier rapidement si un sujet est mentionné
- Trouver une information spécifique dans une longue page
- Localiser une section pertinente

**Combo :**
```bash
/searchpage "API key"
/extract .api-reference          # Extraire la section trouvée
```

---

## Scraping intelligent

### `/scrape` — Scraper une URL

Scrape n'importe quelle page web via le backend Python et extrait automatiquement les données structurées (prix, liens, cartes, métadonnées). Fonctionne sur **toutes les plateformes**.

```
/scrape <url> [selectors_json]
```

**Exemples :**
```bash
/scrape https://www.skyscanner.fr/transport/flights/paris/marseille/        # Extrait les prix de vols
/scrape https://www.booking.com/searchresults.html?ss=Paris                   # Extrait les hôtels et prix
/scrape https://www.backmarket.fr/search?q=xiaomi+15+ultra                    # Extrait les produits reconditionnés
/scrape https://example.com '{"prix": ".price", "titre": "h1"}'            # Sélecteurs CSS personnalisés
```

**Cas d'usage :**
- Extraire des prix en temps réel depuis n'importe quel site
- Surveiller des disponibilités (vols, hôtels, produits)
- Collecter des données structurées sans extension Chrome
- Scraper avec des sélecteurs CSS personnalisés

**Combo :**
```bash
/scrape https://amazon.fr/s?k=iphone
/summarize https://amazon.fr/s?k=iphone     # Résumer les résultats
/export csv                                 # Exporter les prix extraits
```

---

## Interaction DOM

### `/click` — Cliquer sur un élément

Clique sur un élément HTML via son sélecteur CSS.

```
/click <selector>
```

**Exemples :**
```bash
/click button.submit              # Cliquer sur le bouton submit
/click #load-more                 # Charger plus de contenu
/click .cookie-accept             # Accepter les cookies
/click a[href="/next"]            # Aller à la page suivante
```

**Cas d'usage :**
- Accepter les bannières de cookies
- Charger du contenu en lazy loading
- Naviguer dans une pagination
- Déclencher des actions UI

**Combo :**
```bash
/click #show-more-button
/waitfor .new-content             # Attendre le chargement du nouveau contenu
/extract .new-content
```

---

### `/fill` — Remplir un champ

Remplit un champ de formulaire avec une valeur.

```
/fill <selector> <value>
```

**Exemples :**
```bash
/fill input[name="email"] jean@exemple.fr
/fill #search-keyword python async
/fill textarea.comment "Très bon article, merci !"
/fill select[name="country"] France
```

**Cas d'usage :**
- Remplir un champ de recherche
- Saisir une valeur spécifique
- Remplir un formulaire champ par champ

**Combo :**
```bash
/fill input[name="email"] moi@email.com
/fill input[name="password"] MonMotDePasse123
/click button[type="submit"]
```

---

### `/inspect` — Inspecter un élément

Affiche toutes les propriétés d'un élément HTML.

```
/inspect <selector>
```

**Exemples :**
```bash
/inspect .price-tag              # Voir le HTML et les attributs
/inspect meta[property="og:title"]
```

**Cas d'usage :**
- Déboguer un sélecteur CSS
- Comprendre la structure d'un élément
- Trouver le bon sélecteur pour d'autres commandes

**Combo :**
```bash
/inspect .product-card
/highlight .product-card         # Surligner pour voir l'élément
```

---

### `/highlight` — Surligner un élément

Surligne temporairement un élément (disparaît après 3 secondes).

```
/highlight <selector>
```

**Cas d'usage :**
- Vérifier visuellement qu'on cible le bon élément
- Montrer un élément à quelqu'un
- Déboguer une sélection CSS

**Combo :**
```bash
/inspect .product-title
/highlight .product-title        # Confirmer visuellement
/click .product-title            # Puis interagir
```

---

## Médias et fichiers

### `/download` — Télécharger un fichier

Télécharge un fichier depuis une URL.

```
/download <url> [filename]
```

**Exemples :**
```bash
/download https://example.com/doc.pdf
/download https://cdn.example.com/video.mp4 ma_video.mp4
/download https://example.com/image.png capture.png
```

**Cas d'usage :**
- Télécharger un PDF/document
- Sauvegarder une image
- Récupérer une vidéo

**Combo :**
```bash
/links document
/download https://example.com/rapport-2024.pdf
/summarize               # Résumer après téléchargement
```

---

### `/screenshot` — Capture d'écran

Capture la partie visible de l'onglet actif.

```
/screenshot
```

**Cas d'usage :**
- Sauvegarder une vue de la page
- Capturer un message d'erreur
- Documenter un bug visuel

**Combo :**
```bash
/scroll down 500
/screenshot               # Capturer une section spécifique
```

---

### `/pdf` — Imprimer en PDF

Ouvre la boîte de dialogue d'impression (Choisir "Enregistrer au format PDF").

```
/pdf [url] [filename]
```

**Exemples :**
```bash
/pdf                               # Page courante en PDF
/pdf https://example.com/article   # URL spécifique
/pdf "" mon_article                 # Page courante avec nom personnalisé
```

**Cas d'usage :**
- Archiver un article
- Sauvegarder une facture en PDF
- Exporter une page pour lecture hors-ligne

**Combo :**
```bash
/summarize               # Lire le résumé d'abord
/pdf                     # Puis exporter si intéressant
```

---

## Automatisation

### `/autofill` — Remplissage automatique

Remplit automatiquement tous les champs de formulaire avec des données de test.

```
/autofill [form_selector]
```

**Exemples :**
```bash
/autofill                      # Remplir tous les formulaires
/autofill #registration-form   # Remplir un formulaire spécifique
```

**Champs reconnus :**
| Type de champ | Valeur injectée |
|---|---|
| Nom, prénom | Jean Dupont |
| Email | jean.dupont@email.com |
| Téléphone | +33 6 12 34 56 78 |
| Adresse | 15 Rue de la Paix |
| Ville | Paris |
| Code postal | 75001 |
| Pays | France |
| Société | TechCorp SAS |
| Site web | https://jeandupont.fr |

**Cas d'usage :**
- Tester un formulaire rapidement
- Remplir des formulaires de test
- Vérifier la validation d'un formulaire

**Combo :**
```bash
/forms                         # Voir les formulaires
/autofill                      # Les remplir tous
/fill input[name="email"] mon.vrai@email.com  # Corriger un champ
```

---

### `/waitfor` — Attendre un élément

Attend qu'un élément apparaisse dans le DOM (utile pour les SPAs).

```
/waitfor <selector> [timeout_ms]
```

**Exemples :**
```bash
/waitfor .search-results              # Attendre des résultats de recherche
/waitfor .notification-success 15000  # Attendre 15 secondes max
/waitfor #dynamic-content
```

**Cas d'usage :**
- Attendre le chargement asynchrone
- Synchroniser avec une SPA (React, Vue, Angular)
- Attendre une notification de succès/erreur

**Combo :**
```bash
/click #search-button
/waitfor .results-loaded
/extract .results-loaded              # Extraire les résultats
```

---

### `/monitor` — Surveiller un élément

Vérifie la valeur actuelle d'un élément (prix, statut, disponibilité).

```
/monitor <selector> [interval_sec]
```

**Exemples :**
```bash
/monitor .product-price               # Vérifier un prix
/monitor .stock-status 60             # Vérifier le stock toutes les 60s
/monitor "#availability span" 30
```

**Cas d'usage :**
- Suivre un prix sur un e-commerce
- Vérifier la disponibilité d'un produit
- Surveiller un statut (livraison, score, etc.)

**Combo :**
```bash
/monitor .price-tag
/waitfor ".price-tag:below(50€)"      # Attendre une baisse de prix
/screenshot                           # Capturer la preuve
```

---

## Export et conversion

### `/export` — Exporter les données

Exporte les données de la page dans différents formats.

```
/export [json|csv|md]
```

**Exemples :**
```bash
/export json                 # Export JSON structuré
/export csv                  # Export CSV des tableaux
/export md                   # Export Markdown
```

**Cas d'usage :**
- Sauvegarder le contenu d'une page en JSON
- Exporter des tableaux pour Excel
- Convertir une page en Markdown pour documentation

**Combo :**
```bash
/tables
/export csv                  # Exporter les tableaux en CSV
/metadata
/export json                 # Exporter les métadonnées en JSON
```

---

## Traduction et recherche

### `/translate` — Traduire le contenu

Traduit le contenu de la page vers la langue cible en utilisant l'IA.

```
/translate [fr|en|es|de|it|pt|ja|zh|ar|ru|ko|nl]
```

**Exemples :**
```bash
/translate en                # Traduire en anglais
/translate fr                # Traduire en français
/translate ja                # Traduire en japonais
```

**Langues supportées :**
| Code | Langue |
|---|---|
| fr | Français |
| en | English |
| es | Español |
| de | Deutsch |
| it | Italiano |
| pt | Português |
| ja | 日本語 |
| zh | 中文 |
| ar | العربية |
| ru | Русский |
| ko | 한국어 |
| nl | Nederlands |

**Cas d'usage :**
- Lire un article en langue étrangère
- Traduire une documentation technique
- Comprendre une page e-commerce étrangère

**Combo :**
```bash
/extract .recipe-ingredients
/translate en                             # Traduire une section spécifique
```

---

## Combos de commandes

Les combos sont des enchaînements de commandes slash pour accomplir des tâches complexes. Tapez chaque commande l'une après l'autre.

### Workflow 1 : Recherche documentaire

```bash
/open https://scholar.google.com/scholar?q=machine+learning
/links document
/download https://example.com/paper.pdf
/summarize
/export md
```

### Workflow 2 : Analyse de concurrence

```bash
/open https://competiteur.com/pricing
/screenshot
/tables
/export csv
/metadata
```

### Workflow 3 : Formulaire complexe

```bash
/open https://site.com/inscription
/forms
/inspect form#signup
/autofill
/fill input[name="specific_field"] ma_valeur
/click button[type="submit"]
/waitfor .success-message
/screenshot
```

### Workflow 4 : Veille prix

```bash
/open https://ecommerce.fr/produit
/monitor .price-value 60
/screenshot
```

### Workflow 5 : Traduction de documentation

```bash
/open https://docs.python.org/3/library/asyncio.html
/summarize
/translate fr
```

### Workflow 6 : Collecte de médias

```bash
/open https://unsplash.com
/media images
/download https://images.unsplash.com/photo-xxx.jpg paysage.jpg
```

### Workflow 7 : Audit SEO

```bash
/open https://mon-site.com
/metadata
/export json
/links
/searchpage "keyword cible"
```

### Workflow 8 : Extraction de données structurées

```bash
/open https://wikipedia.org/wiki/List_of_programming_languages
/tables
/export csv
```

---

## Référence rapide

| Commande | Usage | Plateforme | Description |
|---|---|---|---|
| `/open` | `/open <url>` | Extension | Ouvrir une URL |
| `/back` | `/back` | Extension | Page précédente |
| `/forward` | `/forward` | Extension | Page suivante |
| `/scroll` | `/scroll [up\|down] [px]` | Extension | Défiler la page |
| `/extract` | `/extract [url] [selector]` | **Universel** | Extraire le texte |
| `/links` | `/links [url] [all\|video\|image\|audio\|document]` | **Universel** | Extraire les liens |
| `/forms` | `/forms [index]` | Extension | Lister les formulaires |
| `/tables` | `/tables [index]` | Extension | Extraire les tableaux |
| `/media` | `/media [images\|videos\|audio\|all]` | Extension | Extraire les médias |
| `/summarize` | `/summarize [url]` | **Universel** | Résumer la page |
| `/metadata` | `/metadata [url]` | **Universel** | Métadonnées SEO |
| `/searchpage` | `/searchpage <terme>` | Extension | Rechercher dans la page |
| `/click` | `/click <selector>` | Extension | Cliquer sur un élément |
| `/fill` | `/fill <selector> <valeur>` | Extension | Remplir un champ |
| `/inspect` | `/inspect <selector>` | Extension | Inspecter un élément |
| `/highlight` | `/highlight <selector>` | Extension | Surligner un élément |
| `/download` | `/download <url> [nom]` | Extension | Télécharger un fichier |
| `/screenshot` | `/screenshot` | Extension | Capture d'écran |
| `/pdf` | `/pdf [url] [nom]` | Extension | Imprimer en PDF |
| `/scrape` | `/scrape <url> [selectors]` | **Universel** | Scraper une URL |
| `/autofill` | `/autofill` | Extension | Remplissage auto |
| `/waitfor` | `/waitfor <selector> [ms]` | Extension | Attendre un élément |
| `/monitor` | `/monitor <selector> [sec]` | Extension | Surveiller un élément |
| `/export` | `/export [json\|csv\|md]` | Extension | Exporter les données |
| `/translate` | `/translate [langue]` | Extension | Traduire la page |

---

> **Astuce** : Tapez `/` dans la zone de saisie pour voir la palette de commandes.

> **Note** : Les combos ne sont pas des commandes spéciales — ce sont des enchaînements naturels. Chaque commande fait une chose, et en les combinant vous créez des workflows puissants.
