# 🎨 Templates & Prompts — CorelIA Design Studio

Ressource de prompts et templates pour générer des sites web, landing pages,
dashboards et applications via CorelIA + DeepSeek (gratuit) ou Open Design.

---

## 🚀 Open Design (installé)

```bash
# Accès local
http://localhost:7456

# Commandes Docker
cd /home/geekai/Documents/open-design/deploy
docker compose up -d      # Démarrer
docker compose logs -f     # Logs
docker compose down        # Arrêter
```

**155 skills** + **150 DESIGN.md** templates intégrés.
Modes : Prototype, Deck, Template, Design System.

---

## 🌐 Landing Page — Prompts

### Hero Section
```
Crée une landing page moderne pour [PRODUIT] avec:
- Hero section: titre accrocheur, sous-titre, CTA bouton
- Dégradé sombre (#001218 → #003F5C) — thème Cofely
- Illustration ou animation légère
- 3 preuves sociales (logos clients, chiffres)
- Formulaire email minimal
```

### SaaS Landing
```
Génère une landing page SaaS complète pour [NOM]:
- Navigation sticky transparente
- Hero avec animation de produit
- Section features en grille 3 colonnes
- Pricing table 3 niveaux (Free/Pro/Enterprise)
- Témoignages clients avec photos
- Footer avec liens
Style: minimal, bleu sombre, typographie Inter
```

### Portfolio/Creative
```
Crée un portfolio créatif pour [NOM]:
- Plein écran, navigation minimaliste
- Grille de projets avec hover effects
- Page projet détaillée (images, description, technologies)
- Section "About" avec timeline
- Formulaire de contact
Style: dark mode, typographie bold, animations fluides
```

---

## 📱 Application Mobile — Prompts

### UI Kit Complet
```
Génère le design system complet pour une app mobile [TYPE]:
- Écran d'onboarding (3 slides)
- Écran de connexion/inscription
- Dashboard principal
- Liste avec recherche et filtres
- Profil utilisateur + paramètres
- Navigation bar inférieure (5 onglets)
Style: Material Design 3, couleurs Cofely (#003F5C, #58B4D1)
```

### Chat Interface
```
Crée une interface de chat moderne:
- Liste de conversations (avatar, dernier message, heure)
- Zone de chat avec bulles (utilisateur à droite, IA à gauche)
- Barre de saisie avec bouton micro et pièce jointe
- Header avec nom et statut en ligne
- Mode sombre/clair
Style: iOS-like, arrondi, ombres légères
```

---

## 📊 Dashboard / Admin — Prompts

### Analytics Dashboard
```
Génère un dashboard analytics:
- Sidebar navigation (icônes + labels)
- Cartes KPI (utilisateurs, revenus, conversion, churn)
- Graphique courbe (30 jours)
- Tableau de données avec tri et pagination
- Barre de recherche globale
- Mode sombre
Style: data-dense, polices mono pour chiffres, couleurs Cofely
```

### Admin Panel
```
Crée un panneau d'administration:
- Table CRUD avec recherche, filtres, pagination
- Formulaire modal pour ajout/édition
- Sidebar avec navigation hiérarchique
- Barre supérieure avec notifications + profil
- Page settings (onglets: général, sécurité, notifications)
Style: fonctionnel, propre, accessibilité AA
```

---

## 🎨 Design Systems

### Cofely (CorelIA)
```css
/* Thème officiel CorelIA — déjà implémenté */
Primary:    #003F5C
Accent:     #58B4D1
Background: #F8FAFC (light) / #0F172A (dark)
Surface:    #FFFFFF (light) / #1E293B (dark)
Font:       Inter (Regular 400, Medium 500, SemiBold 600, Bold 700)
```

### Templates Open Design compatibles Cofely
```
1. Neutral Modern (défaut Open Design)
2. Stripe Blueprint (SaaS)
3. Linear Design (Productivity)
4. Vercel Geist (Developer)
5. Notion Minimal (Productivity)
6. Figma Design (Design Tools)
```

---

## 🤖 Prompts CorelIA — Commands

### /docgen (génération document)
```
/docgen word Rapport d'analyse du marché IA 2026
/docgen powerpoint Présentation CorelIA — pitch investisseur
/docgen excel Tableau comparatif des modèles IA gratuits
/docgen pdf Guide utilisateur CorelIA v2.0
```

### /scrape-script (extraction IA)
```
/scrape-script https://leboncoin.fr "extraire les 20 premiers iPhone avec prix, état, vendeur"
/scrape-script https://github.com/trending "lister les 10 repos tendance avec étoiles et description"
/scrape-script https://news.ycombinator.com "extraire les titres et liens des 15 premiers articles"
```

### /summarize (résumé)
```
/summarize https://arxiv.org/abs/2401.xxxxx
/summarize https://blog.google/technology/ai/gemini-update-2026/
```

---

## 🔧 Open Design — Skills utiles pour CorelIA

| Skill | Usage |
|---|---|
| `saas-landing` | Landing page produit |
| `dashboard` | Dashboard analytics/admin |
| `mobile-app` | UI mobile |
| `pricing-page` | Page tarification |
| `docs-page` | Documentation produit |
| `blog-post` | Blog/article |
| `simple-deck` | Présentation simple |
| `magazine-web-ppt` | Présentation magazine |

---

## 🎯 Quick Start

```bash
# 1. Open Design
cd /home/geekai/Documents/open-design/deploy && docker compose up -d
# → http://localhost:7456

# 2. CorelIA (déjà déployé sur Xiaomi 12)
# APK: build/app/outputs/apk/debug/app-debug.apk

# 3. Prompt rapide dans Open Design
# Skill: saas-landing + Design System: Neutral Modern
# "Crée une landing page pour CorelIA — 
#  assistant IA gratuit, vocal, 27 commandes slash, 
#  extension Chrome, mode hors-ligne"
```
