# Guide Utilisateur — Corely Mobile

> **Version** : 2.0 | **Mise à jour** : 2026-05-14  
> **Plateforme** : Android / iOS

---

## Table des matières

1. [Premiers pas](#premiers-pas)
2. [Chat avec l'IA](#chat-avec-lia)
3. [Mode vocal](#mode-vocal)
4. [Pièces jointes](#pièces-jointes)
5. [Recherche web](#recherche-web)
6. [Paramètres](#paramètres)
7. [Abonnement Pro](#abonnement-pro)
8. [Astuces](#astuces)

---

## Premiers pas

### Installation

1. Téléchargez Corely depuis le Play Store (Android) ou l'App Store (iOS)
2. Ouvrez l'application
3. Acceptez les conditions d'utilisation et la politique de confidentialité
4. L'écran d'onboarding vous présente les fonctionnalités principales
5. Choisissez votre mode : **Gratuit** (DeepSeek V4 Flash) ou **Pro** (OpenRouter)

### Création de compte (optionnel)

Corely fonctionne sans compte. Pour synchroniser vos conversations entre appareils :

1. Appuyez sur l'icône de profil en haut à droite
2. Connectez-vous avec Google, Apple, ou email
3. Vos conversations sont sauvegardées dans le cloud Firebase

### Écran principal

```
┌──────────────────────────────┐
│ ☰ Conversations   ⚙️ Param. │  ← Barre supérieure
├──────────────────────────────┤
│                              │
│   [Messages du chat]         │  ← Zone de conversation
│                              │
├──────────────────────────────┤
│ 🔍 Web  🎤 Vocal  🖼️ Image │  ← Barre d'outils
├──────────────────────────────┤
│ [Saisie texte]         📎 ➤ │  ← Barre de saisie
└──────────────────────────────┘
```

---

## Chat avec l'IA

### Envoyer un message

1. Tapez votre message dans la barre de saisie en bas
2. Appuyez sur la flèche ➤ pour envoyer
3. La réponse de Corely s'affiche en streaming (mot par mot)

### Personnalité de Corely

Corely a une personnalité chaleureuse et directe. Il/elle :
- Te tutoie en français
- Est concis(e) et va droit au but
- S'excuse si il/elle se trompe
- Cite ses sources quand il/elle fait une recherche web

### Modèles IA

| Niveau | Modèle texte | Modèle vision |
|---|---|---|
| **Gratuit** | DeepSeek V4 Flash | DeepSeek Chat |
| **Pro** | Mistral Large (OpenRouter) | GPT-4o-mini (OpenRouter) |

Le modèle est automatiquement sélectionné selon :
- Ton abonnement (gratuit/pro)
- Le type de contenu (texte seul ou texte + image)

---

## Mode vocal

Deux modes vocaux sont disponibles :

### Mode Dictée (micro 🎤)

Transforme ta voix en texte pour l'envoyer comme message.

**Utilisation :**
1. Appuie sur le bouton 🎤 dans la barre d'outils
2. Parle clairement — le texte s'affiche en temps réel
3. Relâche pour arrêter la dictée
4. Le texte est inséré dans la barre de saisie
5. Tu peux le modifier avant d'envoyer

**Astuces :**
- Parle à un rythme normal
- Articule les mots techniques
- La dictée dure jusqu'à 2 minutes
- Le silence de 10 secondes arrête automatiquement

### Mode Conversation vocale (mains-libres)

Une conversation naturelle avec Corely, comme au téléphone.

**Activation :**
1. Active le toggle "Vocal ON/OFF" dans la barre d'outils
2. L'écran Aurora Splash apparaît (particules animées)
3. La boucle démarre : écoute → réflexion → réponse vocale → écoute...

**États visuels (Aurora Splash) :**
| Couleur | État | Signification |
|---|---|---|
| 🟢 Vert | Listening | Corely écoute |
| 🔵 Bleu | Thinking | Corely réfléchit |
| 🟠 Orange | Speaking | Corely parle |
| 🩵 Cyan | Processing | Traitement de la voix |

**Commandes vocales utiles :**
- "Stop" ou "Silence" — Arrêter la conversation
- "Répète" — Redire la dernière réponse
- "Plus lent" — Parler moins vite

**Limitations :**
- La conversation continue jusqu'à ce que tu l'arrêtes
- Maximum 3 échecs de reconnaissance consécutifs avant arrêt automatique
- L'écho est filtré (pause de 500ms après le TTS)
- Barge-in : tu peux interrompre Corely pendant qu'il parle

### Vitesse de la voix

La vitesse de synthèse vocale est réglable :
1. Va dans Paramètres ⚙️
2. Cherche "Vitesse TTS"
3. Ajuste le curseur (0.5 = lent, 2.0 = rapide)
4. Valeur par défaut : 0.65 (naturel)

---

## Pièces jointes

Tu peux joindre des fichiers et des images à tes messages.

### Types supportés

| Type | Formats | Limite gratuit | Limite Pro |
|---|---|---|---|
| Images | JPEG, PNG, WebP, GIF, BMP | 1 MB | 1 MB |
| Documents texte | PDF, DOCX, TXT, CSV, MD | 5 MB | 50 MB |
| Tableurs | XLSX | 5 MB | 50 MB |

### Envoyer une pièce jointe

1. Appuie sur 📎 dans la barre de saisie
2. Choisis "Image" ou "Document"
3. Sélectionne le fichier
4. Un chip s'affiche avec le nom du fichier
5. Tape ta question
6. Envoie — le fichier et le texte partent ensemble

### Analyse de document

Quand tu joins un document, Corely :
1. Extrait le texte du fichier
2. L'injecte comme contexte
3. Peut répondre à des questions sur le contenu

**Exemple :**
> [Tu joins `contrat.pdf`]
> "Quelles sont les clauses de résiliation ?"
>
> **Corely** analyse le PDF et répond en citant les clauses pertinentes.

**Limitations :**
- PDF scannés : extraction texte uniquement (pas d'OCR)
- Contenu tronqué à 15 000 caractères (gratuit) / 30 000 (Pro)
- Les images HEIC/HEIF ne sont pas supportées

### Analyse d'image

Envoie une photo et pose une question :

> [Photo d'une plante]
> "Quelle est cette plante et comment l'entretenir ?"
>
> **Corely** utilise le modèle de vision pour analyser l'image.

---

## Recherche web

### Recherche automatique

Corely détecte automatiquement quand une recherche web est nécessaire :
- Questions factuelles ("Quel est le cours du Bitcoin ?")
- Questions temporelles ("Qui a gagné le match hier ?")
- Actualités récentes

**Quand la recherche n'est PAS déclenchée :**
- Questions créatives ("Écris un poème sur...")
- Code/programmation
- Conversations générales
- Demandes d'opinion

### Recherche manuelle

1. Active le toggle 🔍 "Web" dans la barre d'outils
2. Pose ta question
3. Corely cherche sur DuckDuckGo et injecte les résultats
4. Les sources sont affichées avec la réponse

### Cache de recherche

Pour économiser les requêtes :
- Les résultats de recherche sont mis en cache pendant 15 minutes
- Deux recherches identiques dans cette fenêtre retournent le même résultat
- Jusqu'à 50 entrées en cache (LRU)

---

## Paramètres

Accède aux paramètres via l'icône ⚙️ en haut à droite.

### Prompt système personnalisé

Tu peux personnaliser la personnalité de Corely :

1. Va dans Paramètres
2. Cherche "Prompt système"
3. Modifie le texte
4. Sauvegarde

**Exemple de prompt personnalisé :**
```
Tu es un expert en programmation Python. Réponds de manière technique
avec des extraits de code. Utilise le vouvoiement.
```

### Thème

- 🌙 Mode sombre (défaut)
- ☀️ Mode clair
- 🔄 Système (suit le thème du téléphone)

### Vitesse TTS

Ajuste la vitesse de la voix de Corely entre 0.5× et 2.0×.

---

## Abonnement Pro

### Avantages Pro

| Fonctionnalité | Gratuit | Pro |
|---|---|---|
| Modèle texte | DeepSeek V4 Flash | Mistral Large |
| Modèle vision | DeepSeek Chat | GPT-4o-mini |
| Taille documents | 5 MB | 50 MB |
| Contexte document | 15 000 car. | 30 000 car. |
| Recherche web | ✅ | ✅ |
| Publicités | Oui | Non |

### Souscrire

1. Va dans Paramètres
2. Appuie sur "Passer à Pro"
3. Choisis ton plan (mensuel ou annuel)
4. Paiement via Google Play / App Store

### Récupération de quota

Si tu as épuisé ton quota gratuit (20 requêtes/jour) :
- Regarde une pub récompensée pour +5 requêtes
- Passe en Pro pour un quota illimité

---

## Astuces

### Pour de meilleures réponses

1. **Sois précis** dans tes questions
   ```
   ❌ "Parle-moi de Python"
   ✅ "Explique-moi les décorateurs Python avec un exemple concret"
   ```

2. **Donne du contexte**
   ```
   ❌ "Comment faire ça ?"
   ✅ "Je veux lire un fichier CSV avec pandas et filtrer les lignes où age > 30"
   ```

3. **Utilise les pièces jointes** pour les longs documents

4. **Active la recherche web** pour les infos récentes

5. **Enchaîne les questions** naturellement — Corely garde le contexte
   ```
   Toi : Quel est le meilleur framework Python pour une API REST ?
   Corely : FastAPI est excellent pour les API REST...
   Toi : Donne-moi un exemple de endpoint avec FastAPI
   Corely : Voici un exemple complet...
   ```

### Économiser les requêtes

- Le cache de recherche évite les doublons (15 min TTL)
- Les conversations gardent le contexte des 20 derniers messages
- Pose des questions complètes plutôt que fragmentées

### Confidentialité

- Les conversations en mode Démo restent sur ton appareil
- Les conversations avec compte sont chiffrées dans Firestore
- Les images ne sont PAS uploadées — elles sont envoyées en base64 aux API IA
- Tu peux effacer l'historique d'une conversation dans les paramètres

---

## Résolution de problèmes

### L'app est lente

- Vérifie ta connexion internet
- Ferme les conversations inutilisées
- Redémarre l'application

### La reconnaissance vocale ne fonctionne pas

- Vérifie que le microphone est autorisé (Paramètres Android/iOS)
- Parle plus fort ou rapproche-toi du micro
- Vérifie que tu n'es pas en mode silencieux

### Erreur "Limite de requêtes atteinte"

- Attends le lendemain (reset quotidien)
- Regarde une pub récompensée
- Passe à Pro

### Le fichier ne s'envoie pas

- Vérifie la taille (max 5 MB gratuit)
- Vérifie le format (PDF, DOCX, XLSX, TXT, CSV, MD)
- Les PDFs protégés par mot de passe ne sont pas supportés

---

> **Support** : contact@corely.app | **Documentation** : docs.corely.app
