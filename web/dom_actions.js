// Corely — DOM Actions
// Script injecté dans la page par background.js pour exécuter des actions DOM.
// Écoute les messages { type: 'DOM_ACTION', action: '...', params: {...} }
'use strict';

(function initDomActions() {
  if (window.__corelyDomActionsInitialized) return;
  window.__corelyDomActionsInitialized = true;

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message.type !== 'DOM_ACTION') return false;

    const { action, params } = message;
    try {
      switch (action) {
        case 'CLICK_ELEMENT': {
          const el = document.querySelector(params.selector);
          if (!el) {
            sendResponse({ success: false, error: `Élément introuvable: ${params.selector}` });
            break;
          }
          el.scrollIntoView({ behavior: 'smooth', block: 'center' });
          setTimeout(() => {
            el.click();
            sendResponse({ success: true, data: { selector: params.selector, tagName: el.tagName } });
          }, 300);
          return true;
        }

        case 'FILL_FORM': {
          const el = document.querySelector(params.selector);
          if (!el) {
            sendResponse({ success: false, error: `Champ introuvable: ${params.selector}` });
            break;
          }
          const fieldName = (el.name || el.id || el.placeholder || '').toLowerCase();

          const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
            window.HTMLInputElement.prototype, 'value'
          )?.set;
          const nativeTextareaSetter = Object.getOwnPropertyDescriptor(
            window.HTMLTextAreaElement.prototype, 'value'
          )?.set;

          if (el.tagName === 'SELECT') {
            const options = Array.from(el.options);
            const value = params.value || '';
            const match = options.find(opt =>
              opt.value.toLowerCase() === value.toLowerCase() ||
              opt.text.toLowerCase().includes(value.toLowerCase())
            );
            if (match) {
              el.value = match.value;
            } else {
              el.value = options[1]?.value || options[0]?.value || '';
            }
            el.dispatchEvent(new Event('change', { bubbles: true }));
          } else if (el.tagName === 'TEXTAREA') {
            if (nativeTextareaSetter) {
              nativeTextareaSetter.call(el, params.value || '');
            } else {
              el.value = params.value || '';
            }
            el.dispatchEvent(new Event('input', { bubbles: true }));
          } else if (el.tagName === 'INPUT') {
            if (el.type === 'checkbox' || el.type === 'radio') {
              el.checked = params.value === 'true' || params.value === 'on' || params.value === '1';
              el.dispatchEvent(new Event('change', { bubbles: true }));
            } else {
              if (nativeInputValueSetter) {
                nativeInputValueSetter.call(el, params.value || '');
              } else {
                el.value = params.value || '';
              }
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
            }
          } else {
            el.textContent = params.value || '';
            el.dispatchEvent(new Event('input', { bubbles: true }));
          }

          el.dispatchEvent(new Event('blur', { bubbles: true }));
          sendResponse({
            success: true,
            data: { selector: params.selector, tagName: el.tagName, fieldName: fieldName, filled: true },
          });
          break;
        }

        case 'SCROLL': {
          const direction = params.direction || 'down';
          const amount = parseInt(params.amount) || 500;
          const currentY = window.scrollY;
          const targetY = direction === 'up' ? currentY - amount : currentY + amount;
          window.scrollTo({ top: targetY, behavior: 'smooth' });
          setTimeout(() => {
            sendResponse({
              success: true,
              data: { previousY: currentY, currentY: window.scrollY, direction: direction },
            });
          }, 500);
          return true;
        }

        case 'EXTRACT_TEXT': {
          const selector = params.selector || 'body';
          const el = document.querySelector(selector);
          if (!el) {
            sendResponse({ success: false, error: `Élément introuvable: ${selector}` });
            break;
          }
          const text = (el.textContent || '').replace(/\s+/g, ' ').trim();
          sendResponse({
            success: true,
            data: { selector: selector, text: text, length: text.length, tagName: el.tagName },
          });
          break;
        }

        case 'EXTRACT_LINKS': {
          const filter = params.filter || 'all';
          let links = Array.from(document.querySelectorAll('a'))
            .filter(a => a.href && !a.href.startsWith('javascript:'));

          if (filter !== 'all') {
            const extensions = {
              video: ['.mp4', '.webm', '.mkv', '.avi', '.mov', '.flv', '.wmv', '.m3u8'],
              image: ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.svg', '.bmp', '.ico'],
              audio: ['.mp3', '.wav', '.ogg', '.flac', '.aac', '.m4a', '.opus'],
              document: ['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.csv', '.txt', '.zip', '.rar', '.7z'],
            };
            const exts = extensions[filter] || [];
            // Enhanced video detection: file extensions + known video hosts + iframe embeds
            if (filter === 'video') {
              const videoHosts = [
                'youtube.com/watch', 'youtube.com/shorts', 'youtu.be/',
                'vimeo.com/', 'dailymotion.com/', 'tiktok.com/',
                'twitch.tv/', 'facebook.com/watch', 'instagram.com/reel'
              ];
              links = links.filter(a => {
                const href = a.href.toLowerCase();
                return exts.some(ext => href.includes(ext)) ||
                       videoHosts.some(host => href.includes(host));
              });
              // Also collect video src from <video> and <iframe> elements
              const videoSrcs = Array.from(document.querySelectorAll('video, iframe'))
                .filter(el => el.src && el.src.length > 0)
                .map(el => ({ text: (el.title || el.id || 'Video element').trim().substring(0, 200), href: el.src }));
              links = links.concat(videoSrcs);
            } else {
              links = links.filter(a => exts.some(ext => a.href.toLowerCase().includes(ext)));
            }
          }

          const result = links.slice(0, 100).map(a => ({
            text: (a.textContent || '').trim().substring(0, 200),
            href: a.href,
          }));

          sendResponse({
            success: true,
            data: { links: result, count: result.length, filter: filter },
          });
          break;
        }

        case 'EXTRACT_TABLES': {
          const tables = Array.from(document.querySelectorAll('table'))
            .slice(0, 10)
            .map((table, tableIdx) => {
              const headers = Array.from(table.querySelectorAll('th')).map(th => th.textContent.trim());
              const rows = Array.from(table.querySelectorAll('tr')).map(tr =>
                Array.from(tr.querySelectorAll('td, th')).map(cell => cell.textContent.trim())
              ).filter(r => r.length > 0);
              return {
                index: tableIdx,
                headers: headers.length > 0 ? headers : null,
                rows: rows,
                rowCount: rows.length,
                colCount: rows[0]?.length || 0,
                caption: table.querySelector('caption')?.textContent?.trim() || null,
              };
            });

          sendResponse({
            success: true,
            data: { tables: tables, count: tables.length, totalRows: tables.reduce((s, t) => s + t.rowCount, 0) },
          });
          break;
        }

        case 'EXTRACT_FORMS': {
          const forms = Array.from(document.querySelectorAll('form'))
            .slice(0, 10)
            .map(form => ({
              action: form.action || window.location.href,
              method: (form.method || 'GET').toUpperCase(),
              id: form.id || null,
              inputs: Array.from(form.querySelectorAll('input, textarea, select, button')).map(el => ({
                name: el.name || el.id || '',
                type: el.type || el.tagName.toLowerCase(),
                placeholder: el.placeholder || '',
                required: el.required || false,
                tagName: el.tagName,
              })),
            }));

          sendResponse({
            success: true,
            data: { forms: forms, count: forms.length },
          });
          break;
        }

        case 'EXTRACT_MEDIA': {
          const images = Array.from(document.querySelectorAll('img'))
            .filter(img => img.src && !img.src.startsWith('data:'))
            .slice(0, 50)
            .map(img => ({
              src: img.src,
              alt: img.alt || '',
              width: img.naturalWidth || img.width || 0,
              height: img.naturalHeight || img.height || 0,
            }));

          const videos = Array.from(document.querySelectorAll('video'))
            .slice(0, 20)
            .map(video => ({
              src: video.src || Array.from(video.querySelectorAll('source')).map(s => s.src).join(', '),
              poster: video.poster || '',
              duration: video.duration || 0,
            }));

          const audios = Array.from(document.querySelectorAll('audio'))
            .slice(0, 20)
            .map(audio => ({
              src: audio.src || Array.from(audio.querySelectorAll('source')).map(s => s.src).join(', '),
            }));

          sendResponse({
            success: true,
            data: {
              images: images, imageCount: images.length,
              videos: videos, videoCount: videos.length,
              audios: audios, audioCount: audios.length,
            },
          });
          break;
        }

        case 'PAGE_METADATA': {
          const metadata = {
            title: document.title,
            url: window.location.href,
            description: document.querySelector('meta[name="description"]')?.content || '',
            keywords: document.querySelector('meta[name="keywords"]')?.content || '',
            ogTitle: document.querySelector('meta[property="og:title"]')?.content || '',
            ogDescription: document.querySelector('meta[property="og:description"]')?.content || '',
            ogImage: document.querySelector('meta[property="og:image"]')?.content || '',
            author: document.querySelector('meta[name="author"]')?.content || '',
            publishDate: document.querySelector('meta[property="article:published_time"]')?.content || '',
            language: document.documentElement.lang || '',
            wordCount: (document.body?.textContent || '').split(/\s+/).length,
            headings: Array.from(document.querySelectorAll('h1,h2,h3')).map(h => ({
              level: h.tagName,
              text: (h.textContent || '').trim().substring(0, 200),
            })),
          };
          sendResponse({ success: true, data: metadata });
          break;
        }

        case 'HIGHLIGHT_ELEMENT': {
          const el = document.querySelector(params.selector);
          if (!el) {
            sendResponse({ success: false, error: `Élément introuvable: ${params.selector}` });
            break;
          }
          const origOutline = el.style.outline;
          const origBg = el.style.backgroundColor;
          el.style.outline = '3px solid #6C63FF';
          el.style.backgroundColor = 'rgba(108, 99, 255, 0.15)';
          el.scrollIntoView({ behavior: 'smooth', block: 'center' });
          setTimeout(() => {
            el.style.outline = origOutline;
            el.style.backgroundColor = origBg;
          }, 3000);
          sendResponse({ success: true, data: { selector: params.selector, tagName: el.tagName } });
          break;
        }

        case 'AUTOFILL_PAGE': {
          const nameFields = ['name', 'firstname', 'lastname', 'first_name', 'last_name', 'fullname', 'username',
                             'prenom', 'nom', 'firstName', 'lastName', 'fullName'];
          const emailFields = ['email', 'mail', 'e-mail', 'emailaddress', 'email_address'];
          const phoneFields = ['phone', 'tel', 'telephone', 'mobile', 'phone_number', 'cell', 'contact'];
          const addressFields = ['address', 'adresse', 'street', 'addr', 'adr'];
          const cityFields = ['city', 'ville', 'town', 'locality'];
          const zipFields = ['zip', 'zipcode', 'postal', 'postcode', 'postal_code', 'zip_code', 'cp'];
          const countryFields = ['country', 'pays', 'nation'];
          const companyFields = ['company', 'organization', 'organisation', 'societe', 'entreprise', 'business'];
          const websiteFields = ['website', 'url', 'site', 'web', 'blog', 'homepage'];

          const autofillMap = [
            { fields: nameFields, value: 'Jean Dupont' },
            { fields: emailFields, value: 'jean.dupont@email.com' },
            { fields: phoneFields, value: '+33 6 12 34 56 78' },
            { fields: addressFields, value: '15 Rue de la Paix' },
            { fields: cityFields, value: 'Paris' },
            { fields: zipFields, value: '75001' },
            { fields: countryFields, value: 'France' },
            { fields: companyFields, value: 'TechCorp SAS' },
            { fields: websiteFields, value: 'https://jeandupont.fr' },
          ];

          let filledCount = 0;
          const allInputs = document.querySelectorAll('input:not([type="hidden"]):not([type="submit"]):not([type="button"]):not([type="reset"]):not([type="image"]), textarea, select');

          allInputs.forEach(el => {
            if (el.value && el.value.trim()) return;

            const fieldName = (el.name || el.id || el.placeholder || '').toLowerCase();
            for (const group of autofillMap) {
              if (group.fields.some(f => fieldName.includes(f))) {
                const nativeSetter = Object.getOwnPropertyDescriptor(
                  window.HTMLInputElement.prototype, 'value'
                )?.set;
                if (nativeSetter) {
                  nativeSetter.call(el, group.value);
                } else {
                  el.value = group.value;
                }
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
                filledCount++;
                break;
              }
            }
          });

          sendResponse({
            success: true,
            data: { filledCount: filledCount, totalInputs: allInputs.length },
          });
          break;
        }

        case 'WAIT_FOR_SELECTOR': {
          const timeout = parseInt(params.timeout) || 10000;
          const interval = parseInt(params.interval) || 200;
          const startTime = Date.now();

          const check = () => {
            const el = document.querySelector(params.selector);
            if (el) {
              sendResponse({ success: true, data: { selector: params.selector, found: true, waited: Date.now() - startTime } });
              return;
            }
            if (Date.now() - startTime > timeout) {
              sendResponse({ success: false, error: `Timeout: "${params.selector}" non apparu après ${timeout}ms` });
              return;
            }
            setTimeout(check, interval);
          };
          check();
          return true;
        }

        case 'GET_ELEMENT_INFO': {
          const el = document.querySelector(params.selector);
          if (!el) {
            sendResponse({ success: false, error: `Élément introuvable: ${params.selector}` });
            break;
          }
          const rect = el.getBoundingClientRect();
          const styles = window.getComputedStyle(el);
          sendResponse({
            success: true,
            data: {
              selector: params.selector,
              tagName: el.tagName,
              id: el.id || null,
              className: el.className || null,
              text: (el.textContent || '').trim().substring(0, 500),
              html: el.outerHTML.substring(0, 3000),
              position: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
              visible: styles.display !== 'none' && styles.visibility !== 'hidden',
              attributes: Array.from(el.attributes).map(a => ({ name: a.name, value: a.value })),
            },
          });
          break;
        }

        default:
          sendResponse({ success: false, error: `Action DOM inconnue: ${action}` });
      }
    } catch (err) {
      sendResponse({ success: false, error: err.message || String(err) });
    }
    return false;
  });

  console.info('[Corely DomActions] Initialisé');
})();
