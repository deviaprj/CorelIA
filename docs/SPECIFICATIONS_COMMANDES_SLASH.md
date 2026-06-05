# Corely — Spécifications Fonctionnelles : Exécution Robuste des Commandes Slash

**Date** : 2026-06-05  
**Version** : 1.0  
**Statut** : Proposition d'architecture  
**Contexte** : Garantir la réussite de toutes les commandes slash dans l'extension Chrome, sur mobile, et sur le web, via une architecture hybride mêlant scripts Python/Node.js locaux, backend cloud, et routage LLM intelligent.

---

## 1. Diagnostic de l'Existant

### 1.1 État des 26 commandes slash

| # | Commande | Extension | Mobile (avec URL) | Mobile (sans URL) | Dépendance critique |
|---|----------|-----------|-------------------|-------------------|---------------------|
| 1 | `/download` | ✅ DOM+Browser | ⚠️ Backend requis | ❌ | Backend yt-dlp |
| 2 | `/links` | ✅ DOM+Backend | ⚠️ Backend requis | ❌ | Backend scrape |
| 3 | `/pdf` | ✅ Browser API | ❌ | ❌ | Chrome API |
| 4 | `/summarize` | ✅ DOM+LLM | ⚠️ Backend requis | ❌ | Backend scrape |
| 5 | `/extract` | ✅ DOM+LLM | ⚠️ Backend requis | ❌ | Backend scrape |
| 6 | `/scroll` | ✅ DOM | ❌ | ❌ | Chrome DOM |
| 7 | `/open` | ✅ Browser API | ❌ | ❌ | Chrome Tabs API |
| 8 | `/click` | ✅ DOM | ❌ | ❌ | Chrome DOM |
| 9 | `/fill` | ✅ DOM | ❌ | ❌ | Chrome DOM |
| 10 | `/screenshot` | ✅ Browser API | ❌ | ❌ | Chrome API |
| 11 | `/back` | ✅ Browser API | ❌ | ❌ | Chrome API |
| 12 | `/forward` | ✅ Browser API | ❌ | ❌ | Chrome API |
| 13 | `/forms` | ✅ DOM | ❌ | ❌ | Chrome DOM |
| 14 | `/tables` | ✅ DOM | ❌ | ❌ | Chrome DOM |
| 15 | `/media` | ✅ DOM | ❌ | ❌ | Chrome DOM |
| 16 | `/metadata` | ✅ DOM+Backend | ⚠️ Backend requis | ❌ | Backend scrape |
| 17 | `/autofill` | ✅ DOM | ❌ | ❌ | Chrome DOM |
| 18 | `/inspect` | ✅ DOM | ❌ | ❌ | Chrome DOM |
| 19 | `/highlight` | ✅ DOM | ❌ | ❌ | Chrome DOM |
| 20 | `/waitfor` | ✅ DOM | ❌ | ❌ | Chrome DOM |
| 21 | `/export` | ✅ DOM+Backend | ⚠️ Backend requis | ❌ | Backend scrape |
| 22 | `/monitor` | ✅ DOM | ❌ | ❌ | Chrome DOM |
| 23 | `/translate` | ✅ DOM+LLM | ❌ | ❌ | Chrome DOM |
| 24 | `/searchpage` | ✅ DOM+LLM | ❌ | ❌ | Chrome DOM |
| 25 | `/docgen` | ✅ LLM | ✅ LLM | ✅ LLM | Aucune (LLM natif) |
| 26 | `/scrape` | ✅ Backend | ⚠️ Backend requis | ❌ | Backend scrape |
| 27 | `/crawl` | ✅ Backend | ⚠️ Backend requis | ❌ | Backend crawl |

**Légende** : ✅ Fonctionnel | ⚠️ Conditionnel (backend requis) | ❌ Non supporté

### 1.2 Problèmes racines

#### Problème #1 : Backend cloud non déployé
`api.aironbot.app` n'est pas déployé. Or, **7 commandes** (`scrape`, `crawl`, `download`, `links`, `summarize`, `extract`, `metadata`, `export`) dépendent du backend pour leur fonctionnement avec URL. Le code Dart vérifie :
```dart
if (_backendUrl.isEmpty || _backendUrl.contains('localhost')) {
  throw Exception('Backend URL not configured');
}
```
→ Même un backend local (`localhost:8000`) est bloqué.

#### Problème #2 : Bridge extension fragile (4 couches)
```
Dart → dart:js CustomEvent → extension_bridge.js → chrome.runtime.sendMessage
→ background.js → chrome.scripting.executeScript → dom_actions.js
```
Chaque couche a un timeout (8s), et une défaillance dans n'importe laquelle casse la chaîne. Les pages SPA (YouTube, Twitter, React apps) ne rendent pas leur DOM statique → `dom_actions.js` ne trouve pas les sélecteurs.

#### Problème #3 : Pas de fallback « userspace » pour les échecs DOM
Quand `bridge.executeAction()` échoue (timeout, sélecteur introuvable, page SPA), le handler retourne une erreur utilisateur sans tenter de contournement alternatif.

#### Problème #4 : Routage LLM sous-optimal pour le coût
Le routeur actuel (`ModelRouter`) privilégie `deepseek-v4-pro` (payant) pour les tâches document/code, alors que des modèles OpenRouter gratuits ou moins chers pourraient suffire pour 80% des cas.

---

## 2. Architecture Cible : Le « Triangle de Réussite »

```
┌─────────────────────────────────────────────────────────────────┐
│                     CORE (Dart/Flutter)                         │
│  ┌─────────────┐  ┌──────────────────┐  ┌────────────────────┐ │
│  │ Extension   │  │ Backend Cloud    │  │ Scripts Locaux     │ │
│  │ Bridge      │  │ api.aironbot.app │  │ (Python/Node.js)   │ │
│  │ (DOM/API)   │  │ (FastAPI)        │  │                    │ │
│  └──────┬──────┘  └────────┬─────────┘  └─────────┬──────────┘ │
│         │                  │                       │            │
│         ▼                  ▼                       ▼            │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              STRATEGIC FALLBACK CHAIN                       ││
│  │  1. Script local (Python/Node) — immédiat, 0 coût réseau   ││
│  │  2. Backend cloud — si déployé, avec cache                 ││
│  │  3. Extension DOM — pour les pages déjà ouvertes           ││
│  │  4. LLM direct — interprétation + génération               ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

### 2.1 Principe fondamental

**Toute commande doit avoir 2 à 3 chemins de fallback**, ordonnés du plus fiable au plus créatif :

1. **Chemin direct** : Script local ou DOM → résultat déterministe
2. **Chemin cloud** : Backend `api.aironbot.app` → scraping/crawling
3. **Chemin LLM** : Interprétation par IA (DeepSeek V4 Flash ou OpenRouter) → réponse générée

### 2.2 Scripts Python/Node.js locaux (nouveau)

Les scripts locaux résolvent le problème du backend non déployé ET offrent une latence nulle. Ils s'exécutent côté client (extension ou desktop) et communiquent avec le Flutter via :

- **Extension Chrome** : `chrome.runtime.sendNativeMessage()` (native messaging host)
- **Desktop (Linux)** : Process spawning (`Process.run()`) 
- **Mobile** : Non applicable (les stores interdisent l'exécution de scripts arbitraires) → fallback cloud

#### Catalogue de scripts proposés

| Script | Langage | Rôle | Dépendances |
|--------|---------|------|-------------|
| `scraper.py` | Python 3 | Scraping HTML, extraction prix/titres/liens | `httpx`, `beautifulsoup4` |
| `downloader.py` | Python 3 | Téléchargement média (yt-dlp wrapper) | `yt-dlp` |
| `crawler.py` | Python 3 | Crawling BFS récursif | `httpx`, `beautifulsoup4` |
| `pdf_generator.js` | Node.js | Génération PDF via Puppeteer | `puppeteer` |
| `exporter.js` | Node.js | Export JSON/CSV/Markdown structuré | Aucune (vanilla) |
| `translator.py` | Python 3 | Traduction via LLM local ou API | `httpx` |
| `summarizer.py` | Python 3 | Résumé (extractif + abstractif) | `httpx` |

#### Exemple : `scraper.py`

```python
#!/usr/bin/env python3
"""Corely Local Scraper — extraction de contenu web autonome."""
import sys, json, httpx
from bs4 import BeautifulSoup

def scrape(url: str, selectors: dict | None = None) -> dict:
    headers = {"User-Agent": "Mozilla/5.0 CorelyBot/2.0"}
    resp = httpx.get(url, headers=headers, timeout=15, follow_redirects=True)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, 'html.parser')
    
    # Nettoyage
    for tag in soup(['script', 'style', 'nav', 'footer', 'header', 'noscript']):
        tag.decompose()
    
    result = {"title": soup.title.string if soup.title else "", "url": url}
    
    if selectors:
        for name, sel in selectors.items():
            els = soup.select(sel)
            result[name] = [e.get_text(strip=True)[:500] for e in els[:10]]
    else:
        # Auto-extraction
        result["prices"] = extract_prices(soup)
        result["links"] = [{"text": a.get_text(strip=True)[:200], "url": a.get("href")} 
                          for a in soup.find_all("a", href=True)][:50]
        result["headings"] = [h.get_text(strip=True) for h in soup.find_all(['h1','h2','h3'])]
        result["text"] = soup.get_text(separator=' ', strip=True)[:8000]
    
    return result

def extract_prices(soup):
    import re
    prices = []
    price_pattern = re.compile(r'\d[\d\s]*[.,]\d{2}\s?[€$£]')
    for text in soup.stripped_strings:
        for match in price_pattern.finditer(text):
            prices.append(match.group())
    return prices[:20]

if __name__ == "__main__":
    input_data = json.loads(sys.stdin.read())
    result = scrape(input_data["url"], input_data.get("selectors"))
    print(json.dumps(result, ensure_ascii=False))
```

#### Exemple : `downloader.py` (yt-dlp wrapper)

```python
#!/usr/bin/env python3
"""Corely Local Downloader — extraction média via yt-dlp."""
import sys, json, subprocess

def extract_media(url: str):

    cmd = ["yt-dlp", "--dump-json", "--no-playlist", "--flat-playlist",
           "-f", "best[height<=1080]/best", url]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if proc.returncode == 0:
            data = json.loads(proc.stdout)
            return {
                "success": True,
                "type": "video" if data.get("duration") else "playlist",
                "title": data.get("title", ""),
                "direct_url": data.get("url") or data.get("webpage_url", ""),
                "duration": data.get("duration"),
                "thumbnail": data.get("thumbnail", ""),
                "formats": data.get("formats", [])[:10]
            }
        return {"success": False, "error": proc.stderr[:500]}
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "Timeout: yt-dlp a mis trop de temps"}
    except FileNotFoundError:
        return {"success": False, "error": "yt-dlp non installé"}

if __name__ == "__main__":
    input_data = json.loads(sys.stdin.read())
    result = extract_media(input_data["url"])
    print(json.dumps(result, ensure_ascii=False))
```

#### Mécanisme d'intégration Dart ↔ Scripts

```dart
/// Exécute un script Python/Node.js local et retourne le résultat JSON.
/// Utilisé en fallback quand le backend cloud n'est pas disponible.
Future<Map<String, dynamic>> runLocalScript(
  String scriptName,
  Map<String, dynamic> input,
) async {
  final scriptPath = _resolveScriptPath(scriptName);
  if (scriptPath == null) {
    throw Exception('Script $scriptName non trouvé');
  }

  final interpreter = scriptName.endsWith('.py') ? 'python3' : 'node';
  final process = await Process.run(
    interpreter,
    [scriptPath],
    stdin: jsonEncode(input),
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  if (process.exitCode != 0) {
    throw Exception('${scriptName}: ${process.stderr}');
  }
  return jsonDecode(process.stdout) as Map<String, dynamic>;
}

String? _resolveScriptPath(String name) {
  // Cherche dans ~/.corely/scripts/ (Linux/Mac)
  // ou dans le dossier d'extension (Chrome)
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  final paths = [
    if (home != null) '$home/.corely/scripts/$name',
    'scripts/$name',
  ];
  for (final p in paths) {
    if (File(p).existsSync()) return p;
  }
  return null;
}
```

---

## 3. Routage LLM Stratégique : Performance vs Coût

### 3.1 Modèles disponibles et tarification

| Modèle | Provider | Coût Input ($/M tok) | Coût Output ($/M tok) | Forces |
|--------|----------|---------------------|----------------------|--------|
| `deepseek-v4-flash` | DeepSeek | Gratuit (quota) | Gratuit (quota) | Rapide, généraliste, fiable |
| `deepseek-v4-pro` | DeepSeek | ~0.55 | ~2.19 | Raisonnement profond, code, doc |
| `deepseek-reasoner` | DeepSeek | ~0.55 | ~2.19 | Mathématiques, logique |
| `deepseek-chat` | DeepSeek | ~0.14 | ~0.28 | Vision (images) |
| `mistral-7b-instruct:free` | OpenRouter | Gratuit | Gratuit | Fallback gratuit |
| `deepseek-r1:free` | OpenRouter | Gratuit | Gratuit | Raisonnement gratuit |
| `qwen3-coder:free` | OpenRouter | Gratuit | Gratuit | Code gratuit |
| `gemini-flash-1.5` | OpenRouter | ~0.075 | ~0.30 | Vision, rapide |
| `gpt-4o-mini` | OpenRouter | ~0.15 | ~0.60 | Polyvalent, vision |
| `mistral-large-2407` | OpenRouter | ~2.00 | ~6.00 | Pro, complexe |

### 3.2 Stratégie de routage proposée

**Principe cardinal** : DeepSeek V4 Flash d'abord (gratuit), OpenRouter gratuit ensuite, payant en dernier recours.

```
┌──────────────────────────────────────────────────────────────┐
│                  ARBRE DE DÉCISION LLM                       │
│                                                              │
│  Message utilisateur                                         │
│       │                                                      │
│       ├─ Commande slash ? ──── Oui ──► Commande spécifique  │
│       │                                  │                   │
│       │     ┌────────────────────────────┘                   │
│       │     │                                                │
│       │     ├─ /docgen ───────► deepseek-v4-pro (complexe)   │
│       │     ├─ /summarize ────► deepseek-v4-flash (simple)   │
│       │     ├─ /translate ────► deepseek-v4-flash (simple)   │
│       │     └─ /searchpage ───► deepseek-v4-flash (simple)   │
│       │                                                      │
│       ├─ Image attachée ? ──── Oui ──► gemini-flash-1.5      │
│       │                                  │                   │
│       │                                  └─► deepseek-chat    │
│       │                                                      │
│       ├─ Code / Raisonnement ? ──► deepseek-v4-pro           │
│       │                             │                        │
│       │                             ├─► qwen3-coder:free     │
│       │                             └─► deepseek-r1:free     │
│       │                                                      │
│       └─ Conversation générale ──► deepseek-v4-flash         │
│                                      │                       │
│                                      ├─► mistral-7b:free     │
│                                      └─► gpt-4o-mini         │
└──────────────────────────────────────────────────────────────┘
```

### 3.3 Table de routage optimisée

```dart
static const _routingTable = <TaskType, List<String>>{
  TaskType.general: [
    'deepseek-v4-flash',           // GRATUIT — 90% des requêtes
    'mistral/mistral-7b-instruct:free', // GRATUIT — fallback
    'openai/gpt-4o-mini',          // Payant — dernier recours
  ],
  TaskType.reasoning: [
    'deepseek/deepseek-r1:free',   // GRATUIT — raisonnement
    'deepseek-reasoner',           // Payant — fallback
  ],
  TaskType.vision: [
    'google/gemini-flash-1.5',     // Pas cher ($0.075/$0.30)
    'deepseek-chat',               // Pas cher ($0.14/$0.28)
    'openai/gpt-4o-mini',          // Fallback
  ],
  TaskType.document: [
    'deepseek-v4-flash',           // GRATUIT — pour documents simples
    'deepseek-v4-pro',             // Payant — documents complexes
  ],
  TaskType.code: [
    'qwen/qwen3-coder:free',       // GRATUIT — spécialisé code
    'deepseek-v4-flash',           // GRATUIT — fallback
    'deepseek-v4-pro',             // Payant — code complexe
  ],
  TaskType.longFile: [
    'deepseek-v4-flash',           // GRATUIT — fichiers texte
    'mistral/mistral-7b-instruct:free', // GRATUIT
  ],
};
```

### 3.4 Économies projetées

**Scénario actuel** (100 requêtes/jour) :
- 70% deepseek-v4-flash : **0 €** (gratuit)
- 20% deepseek-v4-pro : ~0.30 €/jour
- 10% vision : ~0.005 €/jour
- **Coût estimé actuel** : ~0.31 €/jour → ~9 €/mois

**Scénario optimisé** (100 requêtes/jour) :
- 85% deepseek-v4-flash : **0 €**
- 10% OpenRouter free : **0 €**
- 5% payant (deepseek-v4-pro, gemini-flash) : ~0.08 €/jour
- **Coût estimé optimisé** : ~0.08 €/jour → ~2.40 €/mois

**Économie** : ~73% de réduction des coûts LLM.

---

## 4. Plan d'Action par Commande

### 4.1 Commandes extension-only (DOM direct) — 18 commandes

Ces commandes fonctionnent **uniquement** dans l'extension Chrome car elles manipulent le DOM de la page courante. Le problème n'est pas le backend, mais la robustesse du bridge.

**Solution : Circuit breaker avec retry et fallback explicatif**

```dart
Future<BrowserActionResult> executeActionWithRetry(
  BrowserAction action, {
  int maxRetries = 2,
  Duration delay = const Duration(seconds: 1),
}) async {
  BrowserActionResult? lastResult;
  for (var i = 0; i <= maxRetries; i++) {
    final result = await bridge.executeAction(action);
    if (result.success) return result;
    lastResult = result;
    if (i < maxRetries) await Future.delayed(delay);
  }
  return lastResult!;
}
```

Pour les pages SPA (YouTube, Twitter, etc.), les commandes DOM qui échouent doivent **automatiquement basculer** vers le chemin backend ou LLM :

| Commande | Échec DOM → Fallback |
|----------|---------------------|
| `/forms` | Backend scrape → extraction formulaires |
| `/tables` | Backend scrape → extraction tableaux |
| `/media` | Backend download_media → yt-dlp |
| `/metadata` | Backend scrape → métadonnées |
| `/translate` | LLM direct → traduction du texte visible |
| `/searchpage` | Backend scrape → recherche dans le texte |

### 4.2 Commandes avec dépendance backend — 8 commandes

**Problème** : `api.aironbot.app` non déployé.

**Solution immédiate** : Scripts locaux Python/Node.js (cf. section 2.2).

**Solution pérenne** : Déploiement du backend (cf. section 5).

### 4.3 Commande `/docgen` — seule commande 100% LLM

C'est la seule commande qui fonctionne sur mobile sans URL. Elle utilise déjà le LLM pour générer des documents.

**Optimisation** : Pour les formats `markdown` et `text`, utiliser `deepseek-v4-flash` (gratuit). Pour `powerpoint`, `word`, `excel`, `pdf`, utiliser `deepseek-v4-pro` (qualité supérieure nécessaire).

---

## 5. Déploiement du Backend — Plan Prioritaire

Le backend `api.aironbot.app` est le nœud critique. Sans lui, 8 commandes sur 26 (~31%) sont inopérantes en mode « URL distante ».

### 5.1 Script de déploiement existant

```bash
bash scripts/deploy_backend.sh
```

Ce script existe déjà (`scripts/deploy_backend.sh`). Il faut l'exécuter depuis une machine avec Docker et accès internet.

### 5.2 Alternative : déploiement serverless (Vercel / Fly.io)

Si Docker n'est pas disponible, le backend FastAPI peut être déployé sur :
- **Fly.io** : `fly launch` → gratuit (3 VMs partagées)
- **Vercel** : avec `vercel.json` configuré pour Python
- **Railway** : $5/mois, déploiement git push

### 5.3 Contournement temporaire : backend local débloqué

**Action immédiate** : Supprimer le filtre `localhost` dans `search_service_global.dart` :

```dart
// AVANT (bloque localhost)
if (_backendUrl.isEmpty || _backendUrl.contains('localhost')) {
  throw Exception('Backend URL not configured');
}

// APRÈS (accepte localhost en dev)
if (_backendUrl.isEmpty) {
  throw Exception('Backend URL not configured');
}
```

Avec cette modification, un `python backend/main.py` local devient utilisable pour les tests.

---

## 6. Architecture Complète des Fallbacks

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     EXÉCUTION D'UNE COMMANDE SLASH                       │
│                                                                         │
│  Entrée: /commande [args]                                               │
│       │                                                                 │
│       ▼                                                                 │
│  ┌──────────────────────┐                                               │
│  │ 1. ANALYSE           │ Parsing des arguments, détection d'URL        │
│  └─────────┬────────────┘                                               │
│            │                                                            │
│            ▼                                                            │
│  ┌──────────────────────────────────────────────┐                       │
│  │ 2. SÉLECTION DU CHEMIN                        │                      │
│  │                                              │                       │
│  │  URL fournie ?                                │                       │
│  │    ├─ Oui → Chemin A: Script local (scraper.py)                      │
│  │    │         │ échec → Chemin B: Backend cloud (/scrape)             │
│  │    │         │ échec → Chemin C: LLM (fetch_url + analyse)           │
│  │    │                                                                 │
│  │    └─ Non → Extension Chrome ?                                       │
│  │              ├─ Oui → Chemin D: Bridge DOM (dom_actions.js)          │
│  │              │         │ échec → Message explicatif + suggestion     │
│  │              │                                                       │
│  │              └─ Non → Mobile ?                                       │
│  │                       └─ Oui → Chemin E: Message d'aide              │
│  │                                (sauf /docgen → Chemin F: LLM direct) │
│  └──────────────────────────────────────────────┘                       │
│            │                                                            │
│            ▼                                                            │
│  ┌──────────────────────┐                                               │
│  │ 3. EXÉCUTION          │ Le chemin choisi s'exécute                   │
│  └─────────┬────────────┘                                               │
│            │                                                            │
│            ▼                                                            │
│  ┌──────────────────────┐                                               │
│  │ 4. FORMATAGE          │ Résultat formaté en Markdown                 │
│  └─────────┬────────────┘                                               │
│            │                                                            │
│            ▼                                                            │
│  ┌──────────────────────┐                                               │
│  │ 5. PERSISTANCE        │ Message sauvegardé dans Firestore            │
│  └──────────────────────┘                                               │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 7. Implémentation Prioritaire

### Phase 1 — Déblocage immédiat (1-2 jours)

| # | Action | Impact |
|---|--------|--------|
| 1 | Supprimer le blocage `localhost` dans `search_service_global.dart` | Débloque le backend local |
| 2 | Créer `scraper.py` et `downloader.py` dans `scripts/` | Fallback local pour /scrape, /download |
| 3 | Ajouter `runLocalScript()` dans un nouveau service `local_script_service.dart` | Intégration Dart ↔ scripts |
| 4 | Ajouter le retry (3 tentatives) dans `ExtensionBridge.executeAction()` | Robustesse DOM |

### Phase 2 — Backend cloud (1 jour)

| # | Action | Impact |
|---|--------|--------|
| 5 | Déployer le backend sur Fly.io (gratuit) | Active toutes les commandes URL |
| 6 | Configurer `BACKEND_URL=api.aironbot.app` dans les builds | Production ready |
| 7 | Ajouter un healthcheck `/ping` et un fallback explicite | Détection panne backend |

### Phase 3 — Routage LLM optimisé (1 jour)

| # | Action | Impact |
|---|--------|--------|
| 8 | Remplacer la table de routage dans `ModelRouter` par la version optimisée (cf. §3.3) | -73% coûts LLM |
| 9 | Ajouter un compteur de coûts estimés dans le `ChatNotifier` | Visibilité budget |
| 10 | Ajouter les modèles gratuits OpenRouter manquants dans le registre | Plus de fallbacks |

### Phase 4 — Robustesse mobile (2 jours)

| # | Action | Impact |
|---|--------|--------|
| 11 | Permettre `/scrape <url>` sur mobile (backed cloud uniquement) | 7 commandes mobile |
| 12 | Ajouter `/summarize <url>`, `/extract <url>`, `/links <url>` sur mobile | Parité extension |
| 13 | Interface de sélection de modèle dans les paramètres | Choix utilisateur |

---

## 8. Conclusion

### 8.1 Résumé des choix d'architecture

1. **Scripts Python/Node.js locaux** comme premier niveau de fallback pour les opérations de scraping, téléchargement, et crawling. Ils sont :
   - **Immédiats** : pas de latence réseau
   - **Gratuits** : pas de coût serveur
   - **Robustes** : pas de dépendance à un backend distant
   - **Maintenables** : scripts isolés, testables unitairement

2. **Backend cloud** (`api.aironbot.app`) comme second niveau, déployé sur Fly.io (gratuit) ou via le script Docker existant. Il offre :
   - **Disponibilité 24/7** : accessible depuis mobile et extension
   - **Cache** : les résultats de scrape peuvent être cachés (TTL 15 min)
   - **yt-dlp** : extraction vidéo complète (1000+ sites)

3. **LLM DeepSeek V4 Flash en priorité** pour 85% des requêtes (gratuit), avec fallback OpenRouter gratuit, et modèles payants uniquement pour les tâches complexes (vision, code avancé, génération de documents). Cette stratégie :
   - **Réduit les coûts de 73%** (9 € → 2.40 €/mois pour 100 req/jour)
   - **Maintient la qualité** grâce au fallback pro quand nécessaire
   - **Utilise les quotas gratuits** de DeepSeek et OpenRouter au maximum

### 8.2 Prochaines étapes immédiates

1. **Débloquer le backend local** : supprimer le filtre `localhost` dans `search_service_global.dart`
2. **Créer `scraper.py`** : premier script local pour /scrape, /metadata, /extract
3. **Déployer le backend** : exécuter `bash scripts/deploy_backend.sh` ou configurer Fly.io
4. **Optimiser le ModelRouter** : appliquer la table de routage §3.3

---

*Document rédigé par DeepSeek V4 Pro (CodeWhale) — Session du 2026-06-05*
