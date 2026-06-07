/**
 * Lightweight Web Scraping Module
 * 
 * Uses fetch() + HTMLRewriter for basic HTML extraction.
 * Cannot match BeautifulSoup/youtube-dl, but handles 80% of use cases:
 * - Metadata extraction (title, description, OG tags)
 * - Text content extraction (main article, body)
 * - Link extraction
 * - Price/heading extraction
 * 
 * For heavy scraping (yt-dlp, SPA crawling), use the Python backend.
 */

// ── Types ─────────────────────────────────────────────────────────────────

interface ScrapeResult {
  title: string;
  url: string;
  description?: string;
  ogTitle?: string;
  ogDescription?: string;
  ogImage?: string;
  author?: string;
  language?: string;
  textContent: string;
  links: Array<{ text: string; url: string }>;
  headings: Array<{ level: string; text: string }>;
  prices: string[];
  error?: string;
}

// ── HTMLRewriter-based extractors ────────────────────────────────────────

/**
 * Extract metadata and text from an HTML page using HTMLRewriter.
 * Runs inside the Worker with zero external dependencies.
 */
export async function scrapeUrl(
  url: string,
  selectors?: Record<string, string>
): Promise<ScrapeResult> {
  // Fetch the page
  const response = await fetch(url, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (compatible; CorelIA/2.0; +https://zentic.fr)',
      'Accept': 'text/html,application/xhtml+xml',
    },
    redirect: 'follow',
    cf: {
      cacheTtl: 300, // Cache for 5 minutes
      cacheEverything: true,
    },
  });

  if (!response.ok) {
    return {
      title: '',
      url,
      textContent: '',
      links: [],
      headings: [],
      prices: [],
      error: `HTTP ${response.status}: ${response.statusText}`,
    };
  }

  const contentType = response.headers.get('content-type') || '';
  if (!contentType.includes('text/html') && !contentType.includes('application/xhtml')) {
    return {
      title: '',
      url,
      textContent: '',
      links: [],
      headings: [],
      prices: [],
      error: `Unsupported content type: ${contentType}`,
    };
  }

  // Collectors
  let title = '';
  let description = '';
  let ogTitle = '';
  let ogDescription = '';
  let ogImage = '';
  let author = '';
  let language = '';
  const textChunks: string[] = [];
  const linkList: Array<{ text: string; url: string }> = [];
  const headingList: Array<{ level: string; text: string }> = [];
  const priceList: string[] = [];

  // Price regex patterns
  const priceRegex = /\d[\d\s]*[.,]\d{2}\s?[€$£¥]/g;

  const rewriter = new HTMLRewriter()
    // ── Metadata ──
    .on('title', {
      text(text) {
        title += text.text;
        if (title.length > 500) title = title.substring(0, 500);
      },
    })
    .on('meta[name="description"]', {
      element(el) {
        description = el.getAttribute('content') || '';
      },
    })
    .on('meta[property="og:title"]', {
      element(el) {
        ogTitle = el.getAttribute('content') || '';
      },
    })
    .on('meta[property="og:description"]', {
      element(el) {
        ogDescription = el.getAttribute('content') || '';
      },
    })
    .on('meta[property="og:image"]', {
      element(el) {
        ogImage = el.getAttribute('content') || '';
      },
    })
    .on('meta[name="author"]', {
      element(el) {
        author = el.getAttribute('content') || '';
      },
    })
    .on('html', {
      element(el) {
        language = el.getAttribute('lang') || '';
      },
    })
    // ── Text content (prioritize article/main) ──
    .on('article, main, [role="main"]', {
      text(text) {
        const t = text.text.trim();
        if (t && textChunks.length < 200) {
          textChunks.push(t);
          // Check for prices
          const matches = t.match(priceRegex);
          if (matches && priceList.length < 20) {
            priceList.push(...matches);
          }
        }
      },
    })
    // ── Fallback body text (if no article/main) ──
    .on('body', {
      text(text) {
        if (textChunks.length === 0) {
          const t = text.text.trim();
          if (t && textChunks.length < 200) {
            textChunks.push(t);
            const matches = t.match(priceRegex);
            if (matches && priceList.length < 20) {
              priceList.push(...matches);
            }
          }
        }
      },
    })
    // ── Links ──
    .on('a[href]', {
      element(el) {
        if (linkList.length < 100) {
          const href = el.getAttribute('href') || '';
          if (href && !href.startsWith('javascript:') && !href.startsWith('#')) {
            linkList.push({ text: '', url: href });
          }
        }
      },
      text(text) {
        // Fill in the link text for the last added link
        if (linkList.length > 0) {
          const last = linkList[linkList.length - 1];
          if (!last.text) {
            last.text = text.text.trim().substring(0, 200);
          }
        }
      },
    })
    // ── Headings ──
    .on('h1, h2, h3, h4', {
      element(el) {
        if (headingList.length < 50) {
          headingList.push({ level: el.tagName, text: '' });
        }
      },
      text(text) {
        if (headingList.length > 0) {
          const last = headingList[headingList.length - 1];
          last.text += text.text;
          if (last.text.length > 300) {
            last.text = last.text.substring(0, 300);
          }
        }
      },
    })
    // ── Custom selectors ──
    .on(selectors ? Object.values(selectors).join(', ') : 'never-match', {
      text(text) {
        textChunks.push(text.text.trim());
      },
    });

  await rewriter.transform(response).text(); // Drain the body through the rewriter

  // Resolve relative URLs in links
  const resolvedLinks = linkList.map(link => ({
    text: link.text,
    url: resolveUrl(link.url, url),
  }));

  // Build text content
  const textContent = textChunks
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim()
    .substring(0, 15000);

  return {
    title: ogTitle || title || '',
    url,
    description: ogDescription || description || undefined,
    ogTitle: ogTitle || undefined,
    ogDescription: ogDescription || undefined,
    ogImage: ogImage || undefined,
    author: author || undefined,
    language: language || undefined,
    textContent,
    links: resolvedLinks,
    headings: headingList.filter(h => h.text.trim()),
    prices: priceList.slice(0, 20),
  };
}

/**
 * Search the web using DuckDuckGo HTML (no API key required).
 */
export async function searchWeb(
  query: string,
  numResults: number = 5
): Promise<Array<{ title: string; url: string; snippet: string }>> {
  const searchUrl = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`;
  
  const response = await fetch(searchUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (compatible; CorelIA/2.0; +https://zentic.fr)',
    },
  });

  if (!response.ok) return [];

  const results: Array<{ title: string; url: string; snippet: string }> = [];
  let currentTitle = '';
  let currentUrl = '';
  let currentSnippet = '';

  const rewriter = new HTMLRewriter()
    .on('.result__title a', {
      element(el) {
        currentUrl = el.getAttribute('href') || '';
      },
      text(text) {
        currentTitle += text.text.trim();
      },
    })
    .on('.result__snippet', {
      text(text) {
        currentSnippet += text.text.trim();
      },
    })
    .on('.result', {
      element() {
        if (currentTitle && results.length < numResults) {
          results.push({
            title: currentTitle.substring(0, 200),
            url: currentUrl,
            snippet: currentSnippet.substring(0, 500),
          });
        }
        currentTitle = '';
        currentUrl = '';
        currentSnippet = '';
      },
    });

  await rewriter.transform(response).text();
  
  return results;
}

// ── Helpers ──────────────────────────────────────────────────────────────

function resolveUrl(href: string, baseUrl: string): string {
  try {
    return new URL(href, baseUrl).toString();
  } catch {
    return href;
  }
}
