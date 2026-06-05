# Guide Utilisateur — Corely Extension Chrome

> **Version** : 2.0 | **Mise à jour** : 2026-05-14  
> **Plateforme** : Chrome / Chromium (Edge, Brave, Opera)

---

## Table des matières

1. [Installation](#installation)
2. [Premiers pas](#premiers-pas)
3. [Modes d'affichage](#modes-daffichage)
4. [Chat avec l'IA](#chat-avec-lia)
5. [Interaction avec les pages web](#interaction-avec-les-pages-web)
6. [Commandes slash](#commandes-slash)
7. [Menu contextuel](#menu-contextuel)
8. [Paramètres](#paramètres)
9. [Limitations](#limitations)
10. [Astuces](#astuces)

---

## Installation

### Depuis le Chrome Web Store

1. Visite le [Chrome Web Store](https://chrome.google.com/webstore)
2. Cherche "Corely"
3. Clique sur "Ajouter à Chrome"

### Installation manuelle (développeur)

1. Téléchargez `corely-extension.zip` depuis [GitHub Releases](https://github.com/corelia/corely/releases)
2. Décompressez le ZIP
3. Dans Chrome, allez à `chrome://extensions`
4. Activez "Mode développeur" (coin supérieur droit)
5. Cliquez "Charger l'extension non empaquetée"
6. Sélectionnez le dossier décompressé

### Vérification de l'installation

L'icône Corely (C violet) apparaît dans la barre d'outils Chrome. Cliquez dessus pour ouvrir Corely.

---

## Premiers pas

### Au premier lancement

1. Cliquez sur l'icône Corely dans la barre d'outils Chrome
2. Le panneau latéral s'ouvre avec Corely
3. Corely détecte automatiquement qu'il est dans une extension
4. Le mode Démo est activé (pas besoin de compte Firebase)

### Écran de l'extension

```
┌─────────────────────┐
│ ≡ Corely       ⚙️   │  ← Barre supérieure
├─────────────────────┤
│                     │
│  [Chat messages]    │  ← Zone de conversation
│                     │
├─────────────────────┤
│ 🔍 Web  🎤 Vocal   │  ← Barre d'outils
├─────────────────────┤
│ [Saisie]     📎  ➤ │  ← Barre de saisie
└─────────────────────┘
```

---

## Modes d'affichage

Corely Extension propose 3 modes d'affichage :

### 1. Side Panel (recommandé)

Le panneau latéral reste ouvert pendant que vous naviguez.

- S'ouvre en cliquant sur l'icône Corely
- Largeur fixe (~400px)
- Persiste pendant la navigation
- Idéal pour les commandes slash sur la page active

### 2. Popup

Fenêtre popup qui se ferme quand vous cliquez ailleurs.

- S'ouvre en cliquant sur l'icône Corely (si le side panel est désactivé)
- Fenêtre flottante
- Se ferme automatiquement en cliquant hors de la popup
- Pratique pour une question rapide

### 3. Plein écran (onglet)

Ouvre Corely dans un nouvel onglet plein écran.

- Via clic droit sur l'icône → "Ouvrir dans un onglet"
- Mode plein écran
- Idéal pour de longues sessions

---

## Chat avec l'IA

Le chat fonctionne comme sur mobile, avec quelques différences :

### Ce qui est identique
- Mêmes modèles IA (DeepSeek, OpenRouter)
- Même personnalité Corely
- Recherche web automatique et manuelle
- Pièces jointes (images, documents)
- Prompt système personnalisable

### Ce qui est différent
- **Pas de compte Firebase** — Mode Démo en mémoire
- **Clé API intégrée** — Pas besoin de configurer
- **Pas de pub** — Pas d'AdMob sur web
- **Pas d'abonnement RevenueCat** — Abonnement via Stripe (web)

---

## Interaction avec les pages web

C'est LA fonctionnalité phare de l'extension : Corely peut interagir avec la page web active.

### Flux général

```
Vous tapez une commande → Corely l'exécute sur la page active → Résultat dans le chat
```

### Ce que Corely peut faire sur une page

| Action | Description | Commande |
|---|---|---|
| Extraire du texte | Récupère le contenu d'un élément | `/extract` |
| Extraire des liens | Liste tous les liens | `/links` |
| Extraire des médias | Images, vidéos, audio | `/media` |
| Extraire des formulaires | Liste les champs de formulaires | `/forms` |
| Extraire des tableaux | Données structurées | `/tables` |
| Résumer la page | Résumé IA du contenu | `/summarize` |
| Métadonnées | SEO, auteur, date, stats | `/metadata` |
| Rechercher dans la page | Trouver un terme | `/searchpage` |
| Cliquer | Cliquer sur un élément | `/click` |
| Remplir un champ | Saisir une valeur | `/fill` |
| Remplissage auto | Formulaire entier | `/autofill` |
| Défiler | Scroll programmatique | `/scroll` |
| Capture d'écran | Screenshot de l'onglet | `/screenshot` |
| Exporter | JSON, CSV, Markdown | `/export` |
| Traduire | Traduction IA | `/translate` |

### Exemple concret

Vous visitez une page e-commerce :

```bash
# 1. Vérifier les infos de la page
/metadata
# → Affiche le titre, l'auteur, les balises SEO...

# 2. Chercher le prix
/searchpage "€"
# → Trouve 8 occurrences de "€"

# 3. Extraire la description
/extract .product-description
# → Affiche le texte complet

# 4. Trouver les images produit
/media images
# → Liste 12 images avec leurs URLs

# 5. Télécharger la plus grande image
/download https://cdn.example.com/produit-hd.jpg
```

---

## Commandes slash

### Comment les utiliser

1. Tapez `/` dans la barre de saisie
2. La palette de commandes apparaît
3. Sélectionnez une commande ou continuez à taper
4. Ajoutez les paramètres
5. Envoyez

### Liste complète

Voir le [Guide des Commandes Slash](GUIDE_COMMANDES_SLASH.md) pour la référence exhaustive avec des exemples concrets et des combos.

### Commandes rapides

| Besoin | Commande |
|---|---|
| Résumer cette page | `/summarize` |
| Télécharger un PDF | `/download <url> <nom>.pdf` |
| Trouver des images | `/media images` |
| Remplir un formulaire | `/autofill` |
| Chercher un terme | `/searchpage <terme>` |
| Traduire la page | `/translate en` |
| Capturer l'écran | `/screenshot` |
| Exporter en CSV | `/export csv` |

---

## Menu contextuel

### "Demander à Corely"

1. Sur n'importe quelle page web, **sélectionnez du texte**
2. Clic droit → "Demander à Corely : ..."
3. Le side panel s'ouvre avec le texte sélectionné
4. Corely analyse le texte et répond

**Cas d'usage :**
- Comprendre un terme technique
- Traduire un paragraphe
- Expliquer un concept
- Analyser une citation

---

## Paramètres

Accessibles via l'icône ⚙️ dans Corely.

### Paramètres disponibles dans l'extension

- **Prompt système** — Personnaliser la personnalité de Corely
- **Thème** — Sombre / Clair / Système
- **Recherche web** — Activer/désactiver par défaut
- **Vitesse TTS** — Vitesse de la voix (si TTS disponible)

### Limitations des paramètres extension

- Pas de synchronisation cloud (mode Démo)
- Les préférences sont locales au navigateur
- Pas de quota utilisateur (API key intégrée)

---

## Limitations

### Limitations techniques

| Limitation | Détail |
|---|---|
| **TTS audio** | Pas de lecture audio native en Manifest V3 (pas de offscreen document) |
| **Vision IA** | Supportée (GPT-4o-mini via OpenRouter) |
| **Formats de fichiers** | Mêmes que mobile (PDF, DOCX, XLSX, TXT, CSV, MD) |
| **Stockage** | En mémoire uniquement (pas de persistance après fermeture) |
| **Multi-fenêtres** | Une seule instance Corely à la fois |

### Ce qui ne fonctionne PAS

- ❌ **Résumé de page automatique** — Il faut utiliser `/summarize`
- ❌ **Extraction média automatique** — Il faut utiliser `/media`
- ❌ **Autofill intelligent** — Les données injectées sont des données de test
- ❌ **OCR** — Pas de reconnaissance de texte dans les images
- ❌ **Téléchargement de vidéos streaming** — Uniquement les fichiers directs

### Ce qui fonctionne

- ✅ Chat IA avec DeepSeek et OpenRouter
- ✅ Toutes les commandes slash (22 commandes)
- ✅ Recherche web intégrée
- ✅ Pièces jointes (images et documents)
- ✅ Menu contextuel "Demander à Corely"
- ✅ Capture d'écran
- ✅ Navigation (ouvrir, back, forward, scroll)
- ✅ Interaction DOM (click, fill, autofill)
- ✅ Export données (JSON, CSV, Markdown)
- ✅ Traduction IA
- ✅ Mode vocal (dictée via Web Speech API)

---

## Astuces

### Pour les power users

1. **Utilisez le side panel** plutôt que le popup — il persiste pendant la navigation

2. **Enchaînez les commandes** pour des workflows complexes :
   ```bash
   /links document
   /download https://example.com/doc.pdf
   /summarize
   /export md
   ```

3. **Inspectez avant d'interagir** :
   ```bash
   /inspect .suspicious-button
   /highlight .suspicious-button
   /click .suspicious-button
   ```

4. **Capturez pour documenter** :
   ```bash
   /scroll down 500
   /screenshot
   ```

5. **Utilisez le menu contextuel** pour analyser rapidement une sélection

### Raccourcis clavier

| Raccourci | Action |
|---|---|
| `Ctrl+Shift+K` | Ouvrir Corely (configurable dans `chrome://extensions/shortcuts`) |
| `Ctrl+Enter` | Envoyer le message |
| `Escape` | Fermer la popup (mode popup uniquement) |

### Pour les développeurs

- Les sélecteurs CSS sont votre meilleur ami : `/click`, `/fill`, `/extract`, `/inspect`, `/highlight`, `/waitfor`
- Inspectez le DOM avec `/inspect` pour trouver les bons sélecteurs
- Utilisez `/export json` pour récupérer des données structurées
- Combinez `/waitfor` avec `/click` pour les SPAs

---

## Résolution de problèmes

### L'extension ne s'ouvre pas

- Vérifiez que l'extension est activée dans `chrome://extensions`
- Essayez de la désactiver/réactiver
- Rechargez l'extension (bouton 🔄 dans `chrome://extensions`)

### Les commandes slash ne fonctionnent pas

- Vérifiez qu'un onglet web est actif
- Vérifiez que l'URL n'est pas une page chrome:// (restreinte)
- Actualisez la page cible

### Erreur "Extension not available"

- Vérifiez que vous êtes dans l'extension Corely
- Rechargez l'extension

### Le contenu de page n'est pas extrait

- La page peut bloquer les content scripts
- Essayez sur une autre page
- Vérifiez que le sélecteur CSS est correct avec `/inspect`

---

> **Support** : contact@corely.app | **Documentation** : docs.corely.app
