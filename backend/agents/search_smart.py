"""Smart unified search engine that replaces per-method search with an
LLM-driven, learning-capable system."""

from __future__ import annotations

import asyncio
import json
import re
from typing import Any

import httpx
from bs4 import BeautifulSoup

from backend.core.config import settings
from backend.core.logging import get_logger

logger = get_logger(__name__)

# ── In-memory knowledge base (learned selectors per domain) ────────────────

_LEARNED_SELECTORS: dict[str, dict[str, str]] = {
    "www.google.com": {
        "result": "div[data-sokoban-container]",
        "title": "h3",
        "snippet": ".VwiC3b, .s3v94d",
        "price": "span, .U3iZVb",
    },
    "www.skyscanner.fr": {
        "price": "[data-testid='price'], .fqs-price, .Price_label",
        "flight": ".fqs-result, [data-testid='result-card']",
    },
    "www.booking.com": {
        "price": ".prco-valign-helper, .bd-highlight, [data-testid='price-and-discounted-price']",
        "hotel": ".sr_item, [data-testid='property-card']",
    },
    "www.backmarket.fr": {
        "price": ".price, [data-testid='product-price']",
        "product": ".product-card, [data-testid='product-card']",
    },
    "www.ebay.fr": {
        "price": ".s-item__price, .notranslate",
        "product": ".s-item",
    },
    "fr.shopping.rakuten.com": {
        "price": ".price, .c-price",
        "product": ".prd-product",
    },
    "www.leboncoin.fr": {
        "price": "[data-testid='price'], .text-xl",
        "product": "[data-testid='adcard']",
    },
}

# Mapping: intent → list of (domain, url_template, selectors_key)
_INTENT_SOURCES: dict[str, list[dict[str, str]]] = {
    "flights": [
        {"domain": "www.skyscanner.fr", "template": "https://www.skyscanner.fr/transport/flights/{from_iata}/{to_iata}/{depart}/{return}/", "key": "www.skyscanner.fr"},
        {"domain": "www.kayak.fr", "template": "https://www.kayak.fr/flights/{from_iata}-{to_iata}/{depart}/{return}", "key": "www.google.com"},
    ],
    "hotels": [
        {"domain": "www.google.com", "template": "https://www.google.com/search?q={query} hotel prix", "key": "www.google.com"},
        {"domain": "www.booking.com", "template": "https://www.booking.com/searchresults.fr.html?ss={city}", "key": "www.booking.com"},
    ],
    "products": [
        {"domain": "www.google.com", "template": "https://www.google.com/search?tbm=shop&q={query}", "key": "www.google.com"},
        {"domain": "www.amazon.fr", "template": "https://www.amazon.fr/s?k={query}", "key": "www.google.com"},
    ],
    "secondhand": [
        {"domain": "www.google.com", "template": "https://www.google.com/search?q={query} reconditionné prix", "key": "www.google.com"},
        {"domain": "www.backmarket.fr", "template": "https://www.backmarket.fr/search?q={query}", "key": "www.backmarket.fr"},
        {"domain": "www.ebay.fr", "template": "https://www.ebay.fr/sch/i.html?_nkw={query}", "key": "www.ebay.fr"},
        {"domain": "fr.shopping.rakuten.com", "template": "https://fr.shopping.rakuten.com/s/{query}", "key": "fr.shopping.rakuten.com"},
        {"domain": "www.leboncoin.fr", "template": "https://www.leboncoin.fr/recherche?text={query}", "key": "www.leboncoin.fr"},
    ],
    "restaurants": [
        {"domain": "www.google.com", "template": "https://www.google.com/search?q={query} restaurant avis prix", "key": "www.google.com"},
    ],
    "events": [
        {"domain": "www.google.com", "template": "https://www.google.com/search?q={query} billets prix date", "key": "www.google.com"},
    ],
    "general": [
        {"domain": "www.google.com", "template": "https://www.google.com/search?q={query}", "key": "www.google.com"},
    ],
}


# ── LLM Intent Classification ───────────────────────────────────────────

_INTENT_PROMPT = """Tu es un moteur d'analyse de requêtes utilisateur pour un assistant de recherche.
Analyse la requête suivante et retourne UNIQUEMENT un objet JSON au format :

{
  "intent": "flights|hotels|products|secondhand|restaurants|events|weather|general",
  "params": {
    "from": "ville départ (vols)",
    "to": "ville arrivée (vols)",
    "departDate": "YYYY-MM-DD",
    "returnDate": "YYYY-MM-DD ou null",
    "location": "ville ou lieu",
    "checkIn": "YYYY-MM-DD",
    "checkOut": "YYYY-MM-DD",
    "guests": nombre,
    "condition": "refurbished|used|null",
    "category": "catégorie produit",
    "color": "couleur",
    "priceRange": "cheapest|mid|premium|null"
  },
  "searchQuery": "la requête nettoyée optimisée pour un moteur de recherche"
}

Règles :
- Si la requête mentionne des dates comme "2 juin" ou "02/06", convertis en YYYY-MM-DD (année courante).
- "reconditionné", "refurbished", "occasion" → condition = refurbished/used
- "vol", "billet avion", "aller" → intent = flights
- "hotel", "logement", "hébergement" → intent = hotels
- "restaurant", "manger", "diner" → intent = restaurants
- "concert", "billet", "spectacle", "match" → intent = events
- "météo", "temps", "pleuvoir" → intent = weather
- Produits physiques (téléphone, ordinateur, etc.) avec "reconditionné/occasion" → secondhand
- Produits physiques sans condition → products
- Sinon → general

Réponds UNIQUEMENT avec le JSON, sans markdown, sans explication.
"""


async def _classify_intent(query: str) -> dict[str, Any]:
    """Use LLM to classify search intent and extract parameters."""
    api_key = settings.openrouter_api_key or settings.deepseek_api_key
    if not api_key:
        # Fallback to regex-based classification
        return _fallback_classify(query)

    messages = [
        {"role": "system", "content": _INTENT_PROMPT},
        {"role": "user", "content": f'Requête : "{query}"'},
    ]

    # Try DeepSeek first, then OpenRouter
    providers: list[tuple[str, str, str]] = []
    if settings.deepseek_api_key:
        providers.append((
            "deepseek",
            "https://api.deepseek.com/v1/chat/completions",
            settings.deepseek_api_key,
        ))
    if settings.openrouter_api_key:
        providers.append((
            "openrouter",
            "https://openrouter.ai/api/v1/chat/completions",
            settings.openrouter_api_key,
        ))

    for provider, url, key in providers:
        try:
            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {key}",
            }
            if provider == "openrouter":
                headers["HTTP-Referer"] = "https://zentic.fr"
                headers["X-Title"] = "CorelIA"

            payload = {
                "model": "deepseek-chat" if provider == "deepseek" else "mistralai/mistral-7b-instruct",
                "messages": messages,
                "temperature": 0.1,
                "max_tokens": 400,
            }

            async with httpx.AsyncClient(timeout=20.0) as client:
                response = await client.post(url, json=payload, headers=headers)
                response.raise_for_status()
                data = response.json()

            content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
            # Extract JSON from response
            json_match = re.search(r"\{.*\}", content, re.DOTALL)
            if json_match:
                parsed = json.loads(json_match.group())
                logger.info("Intent classified", extra={"provider": provider, "intent": parsed.get("intent"), "query": query})
                return parsed
        except Exception as exc:
            logger.warning(f"Intent classification failed for {provider}", extra={"error": str(exc)})
            continue

    return _fallback_classify(query)


def _fallback_classify(query: str) -> dict[str, Any]:
    """Regex-based fallback intent classification."""
    q_lower = query.lower()
    result: dict[str, Any] = {"intent": "general", "params": {}, "searchQuery": query}

    # Flight detection
    flight_terms = ["vol", "billet", "avion", "flight", "aller", "retour", "skyscanner", "kayak"]
    if any(t in q_lower for t in flight_terms):
        result["intent"] = "flights"
        # Extract cities
        city_pattern = r"([A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?)\s*(?:-|à|vers|pour)\s*([A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?)"
        match = re.search(city_pattern, query)
        if match:
            result["params"]["from"] = match.group(1).strip()
            result["params"]["to"] = match.group(2).strip()
        # Extract dates (simple DD/MM or text month)
        date_pattern = r"(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{2,4}))?"
        dates = re.findall(date_pattern, query)
        if dates:
            from datetime import datetime
            year = datetime.now().year
            d1 = dates[0]
            result["params"]["departDate"] = f"{year}-{int(d1[1]):02d}-{int(d1[0]):02d}"
            if len(dates) > 1:
                d2 = dates[1]
                result["params"]["returnDate"] = f"{year}-{int(d2[1]):02d}-{int(d2[0]):02d}"

    # Hotel detection
    hotel_terms = ["hotel", "hôtel", "logement", "hébergement", "booking", "airbnb"]
    if any(t in q_lower for t in hotel_terms):
        result["intent"] = "hotels"
        city_match = re.search(r"(?:hotel|hôtel|logement)\s+(?:à|de|pour|sur|in|en|a)?\s*([A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?)", query, re.IGNORECASE)
        if city_match:
            result["params"]["location"] = city_match.group(1).strip()

    # Product detection
    product_terms = ["acheter", "prix", "meilleur prix", "comparer", "shopping"]
    secondhand_terms = ["reconditionné", "refurbished", "occasion", "seconde main", "used"]
    if any(t in q_lower for t in secondhand_terms):
        result["intent"] = "secondhand"
        result["params"]["condition"] = "refurbished" if any(t in q_lower for t in ["reconditionné", "refurbished"]) else "used"
    elif any(t in q_lower for t in product_terms):
        result["intent"] = "products"

    # Restaurant detection
    restaurant_terms = ["restaurant", "manger", "diner", "déjeuner", "brasserie"]
    if any(t in q_lower for t in restaurant_terms):
        result["intent"] = "restaurants"

    # Event detection
    event_terms = ["concert", "spectacle", "billet", "match", "festival", "théâtre", "musee", "musée"]
    if any(t in q_lower for t in event_terms):
        result["intent"] = "events"

    # Weather detection
    weather_terms = ["météo", "meteo", "temps", "température", "pleuvoir", "weather"]
    if any(t in q_lower for t in weather_terms):
        result["intent"] = "weather"
        city_match = re.search(r"(?:météo|meteo|temps|weather)\s+(?:à|de|pour|sur|in|en|a)?\s*([A-ZÀ-Ÿ][a-zà-ÿ]+(?:\s[A-ZÀ-Ÿ][a-zà-ÿ]+)?)", query, re.IGNORECASE)
        if city_match:
            result["params"]["location"] = city_match.group(1).strip()

    return result


# ── Scraping Engine ──────────────────────────────────────────────────────

async def _scrape_page(
    url: str,
    domain_key: str | None = None,
    timeout: float = 15.0,
) -> dict[str, Any]:
    """Scrape a single page with learned selectors."""
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ),
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7",
        "Accept-Encoding": "gzip, deflate, br",
        "DNT": "1",
        "Connection": "keep-alive",
        "Upgrade-Insecure-Requests": "1",
        "Sec-Fetch-Dest": "document",
        "Sec-Fetch-Mode": "navigate",
        "Sec-Fetch-Site": "none",
        "Sec-Fetch-User": "?1",
        "Cache-Control": "max-age=0",
    }

    async with httpx.AsyncClient(timeout=timeout, follow_redirects=True) as client:
        try:
            response = await client.get(url, headers=headers)
            response.raise_for_status()
            html = response.text
        except Exception as exc:
            logger.warning(f"Scraping failed for {url}", extra={"error": str(exc)})
            return {"url": url, "title": "", "data": [], "error": str(exc)}

    soup = BeautifulSoup(html, "html.parser")
    for tag in soup(["script", "style", "nav", "footer", "header", "aside"]):
        tag.decompose()

    result: dict[str, Any] = {"url": url, "title": "", "data": []}
    title_tag = soup.find("title")
    if title_tag:
        result["title"] = title_tag.get_text(strip=True)

    selectors = _LEARNED_SELECTORS.get(domain_key or "") if domain_key else None

    # Price extraction
    prices: list[str] = []
    if selectors and "price" in selectors:
        for el in soup.select(selectors["price"])[:10]:
            text = el.get_text(strip=True)
            if text and len(text) < 50:
                prices.append(text)
    else:
        # Auto-detect prices
        price_patterns = [
            r"\d{1,3}(?:[\s \xa0]?\d{3})*[\.,]\d{2}\s?[€$£]",
            r"\d{1,3}(?:[\s \xa0]?\d{3})*\s?[€$£]",
        ]
        for elem in soup.find_all(text=re.compile(price_patterns[0])):
            text = str(elem).strip()
            if 3 < len(text) < 30:
                matches = re.findall(price_patterns[0], text)
                prices.extend(matches)

    if prices:
        # Deduplicate while preserving order
        seen = set()
        unique_prices = [p for p in prices if not (p in seen or seen.add(p))]  # type: ignore[func-returns-value]
        result["data"].append({"field": "prices", "values": unique_prices[:10]})

    # Card/result extraction
    cards: list[dict[str, str]] = []
    if selectors and "result" in selectors:
        for el in soup.select(selectors["result"])[:8]:
            text = el.get_text(separator=" ", strip=True)
            if len(text) > 30 and len(text) < 500:
                cards.append({"text": text[:400], "type": "result"})
    elif selectors and "product" in selectors:
        for el in soup.select(selectors["product"])[:8]:
            text = el.get_text(separator=" ", strip=True)
            if len(text) > 30 and len(text) < 500:
                cards.append({"text": text[:400], "type": "product"})
    else:
        # Generic card detection
        card_selectors = [
            "[class*='result']", "[class*='item']", "[class*='card']",
            "[class*='offer']", "[class*='product']", "[class*='deal']",
            "[class*='flight']", "[class*='hotel']",
        ]
        for selector in card_selectors:
            for el in soup.select(selector)[:5]:
                text = el.get_text(separator=" ", strip=True)
                if len(text) > 40 and len(text) < 500:
                    cls = el.get("class", [""])[0] if el.get("class") else ""
                    cards.append({"text": text[:400], "type": cls})

    if cards:
        seen = set()
        unique_cards = [c for c in cards if c["text"] not in seen and not seen.add(c["text"])]  # type: ignore[func-returns-value]
        result["data"].append({"field": "cards", "values": unique_cards[:8]})

    # Link extraction
    links: list[dict[str, str]] = []
    for a in soup.find_all("a", href=True)[:15]:
        text = a.get_text(strip=True)
        href = a["href"]
        if text and len(text) > 5 and len(text) < 100 and href.startswith("http"):
            links.append({"text": text, "url": href})
    if links:
        result["data"].append({"field": "links", "values": links[:10]})

    return result


# ── Unified Search ──────────────────────────────────────────────────────

async def search_smart(query: str) -> dict[str, Any]:
    """Unified smart search: classify intent, build plan, execute, return structured results."""
    logger.info("Smart search started", extra={"query": query})

    # 1. Classify intent
    classification = await _classify_intent(query)
    intent = classification.get("intent", "general")
    params = classification.get("params", {})
    search_query = classification.get("searchQuery", query)

    # 2. Build source list
    sources = _INTENT_SOURCES.get(intent, _INTENT_SOURCES["general"]).copy()

    # 3. Build URLs with parameters
    urls_to_scrape: list[tuple[str, str]] = []  # (url, domain_key)
    for source in sources:
        template = source["template"]
        url = template.replace("{query}", search_query.replace(" ", "+"))

        # Flight-specific substitutions
        if intent == "flights":
            from_city = params.get("from", "").upper()
            to_city = params.get("to", "").upper()
            # Try to resolve IATA codes
            from_iata = from_city[:3] if len(from_city) == 3 else from_city
            to_iata = to_city[:3] if len(to_city) == 3 else to_city
            depart = params.get("departDate", "").replace("-", "")
            retour = params.get("returnDate", "").replace("-", "")
            url = url.replace("{from_iata}", from_iata)
            url = url.replace("{to_iata}", to_iata)
            url = url.replace("{depart}", depart)
            url = url.replace("{return}", retour)

        # Hotel-specific substitutions
        if intent == "hotels":
            city = params.get("location", search_query)
            url = url.replace("{city}", city.replace(" ", "+"))

        # Add to scrape list
        domain_key = source.get("key", source["domain"])
        urls_to_scrape.append((url, domain_key))

    # 4. Scrape all sources in parallel
    scrape_tasks = [_scrape_page(url, key) for url, key in urls_to_scrape]
    scrape_results = await asyncio.gather(*scrape_tasks, return_exceptions=True)

    # 5. Aggregate results
    aggregated: dict[str, Any] = {
        "intent": intent,
        "params": params,
        "query": search_query,
        "sources": [],
        "results": [],
    }

    for i, result in enumerate(scrape_results):
        if isinstance(result, Exception):
            logger.warning(f"Scrape task {i} failed", extra={"error": str(result)})
            continue

        url, _ = urls_to_scrape[i]
        aggregated["sources"].append({"url": url, "title": result.get("title", "")})

        for data_item in result.get("data", []):
            field = data_item.get("field", "")
            values = data_item.get("values", [])
            for value in values:
                if field == "prices":
                    aggregated["results"].append({
                        "type": "price",
                        "value": value,
                        "source_url": url,
                    })
                elif field == "cards":
                    if isinstance(value, dict):
                        aggregated["results"].append({
                            "type": "card",
                            "title": value.get("text", "")[:100],
                            "snippet": value.get("text", ""),
                            "source_url": url,
                        })
                    else:
                        aggregated["results"].append({
                            "type": "card",
                            "title": str(value)[:100],
                            "snippet": str(value),
                            "source_url": url,
                        })
                elif field == "links":
                    if isinstance(value, dict):
                        aggregated["results"].append({
                            "type": "link",
                            "title": value.get("text", ""),
                            "url": value.get("url", ""),
                            "source_url": url,
                        })

    # 6. Add direct comparator links as fallback
    if intent in ("flights", "hotels", "products", "secondhand"):
        _add_direct_links(aggregated, intent, params, search_query)

    logger.info("Smart search completed", extra={
        "intent": intent,
        "results_count": len(aggregated["results"]),
        "sources_count": len(aggregated["sources"]),
    })
    return aggregated


def _add_direct_links(
    aggregated: dict[str, Any],
    intent: str,
    params: dict[str, Any],
    search_query: str,
) -> None:
    """Add direct comparator links as fallback results."""
    if intent == "flights":
        from_city = params.get("from", "")
        to_city = params.get("to", "")
        if from_city and to_city:
            aggregated["results"].append({
                "type": "link",
                "title": f"Skyscanner — {from_city} → {to_city}",
                "url": f"https://www.skyscanner.fr/transport/flights/{from_city.lower()[:3]}/{to_city.lower()[:3]}/",
                "source_url": "",
            })

    elif intent == "hotels":
        city = params.get("location", search_query)
        aggregated["results"].append({
            "type": "link",
            "title": f"Booking.com — {city}",
            "url": f"https://www.booking.com/searchresults.fr.html?ss={city.replace(' ', '+')}",
            "source_url": "",
        })
        aggregated["results"].append({
            "type": "link",
            "title": f"Airbnb — {city}",
            "url": f"https://www.airbnb.fr/s/{city.replace(' ', '-')}/homes",
            "source_url": "",
        })

    elif intent == "products":
        q = search_query.replace(" ", "+")
        aggregated["results"].append({
            "type": "link",
            "title": "Google Shopping",
            "url": f"https://www.google.com/search?tbm=shop&q={q}",
            "source_url": "",
        })
        aggregated["results"].append({
            "type": "link",
            "title": "Amazon",
            "url": f"https://www.amazon.fr/s?k={q}",
            "source_url": "",
        })

    elif intent == "secondhand":
        q = search_query.replace(" ", "+")
        aggregated["results"].append({
            "type": "link",
            "title": "Back Market (reconditionné)",
            "url": f"https://www.backmarket.fr/search?q={q}",
            "source_url": "",
        })
        aggregated["results"].append({
            "type": "link",
            "title": "eBay",
            "url": f"https://www.ebay.fr/sch/i.html?_nkw={q}",
            "source_url": "",
        })
        aggregated["results"].append({
            "type": "link",
            "title": "Leboncoin",
            "url": f"https://www.leboncoin.fr/recherche?text={q}",
            "source_url": "",
        })


# ── Learning / Feedback ───────────────────────────────────────────────────

def learn_selectors(domain: str, selectors: dict[str, str]) -> None:
    """Update learned selectors for a domain. Called when scraping succeeds."""
    _LEARNED_SELECTORS[domain] = selectors
    logger.info("Learned selectors updated", extra={"domain": domain})


def get_learned_selectors() -> dict[str, dict[str, str]]:
    """Return current learned selectors."""
    return _LEARNED_SELECTORS.copy()
