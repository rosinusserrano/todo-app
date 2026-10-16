// A web page's title, for a link in a task.
//
// A task whose title holds a URL shows the page's title instead
// (link_titles.dart). The native builds ask the page themselves; a browser
// cannot - another site sends no CORS headers - so the web build asks this
// route. It is feeds.js's shape exactly, and the same three things keep it
// from being a request forgery: only an account can call it, every hop
// (redirects are followed by hand) must resolve to a public address, and what
// comes back is a short string, never the page.
//
// Only the head of the page is read: the title is near the top, and a link
// to a 2GB video must not be downloaded to find out it has none.

import { lookup as dnsLookup } from 'node:dns/promises';

import { FeedError, assertPublic } from './feeds.js';

const MAX_BYTES = 256 * 1024;
const TIMEOUT_MS = 8_000;
const MAX_REDIRECTS = 5;
const MAX_TITLE = 300;

/** What the page calls itself: og:title, else <title>. Null for neither. */
export function titleFromHtml(html) {
  const og =
    html.match(/<meta[^>]+property=["']og:title["'][^>]*content=["']([^"']*)["']/i) ??
    html.match(/<meta[^>]+content=["']([^"']*)["'][^>]*property=["']og:title["']/i);
  const raw = og?.[1] ?? html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1];
  if (raw == null) return null;
  const title = decodeEntities(raw).replace(/\s+/g, ' ').trim();
  if (!title) return null;
  return title.length > MAX_TITLE ? `${title.slice(0, MAX_TITLE - 1)}…` : title;
}

const NAMED = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };

function decodeEntities(s) {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) => {
    if (e[0] === '#') {
      const code = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      try {
        return String.fromCodePoint(code);
      } catch {
        return m;
      }
    }
    return NAMED[e.toLowerCase()] ?? m;
  });
}

/** Up to MAX_BYTES of the body, stopping early once the head is over. */
async function readHead(res) {
  if (!res.body) return Buffer.from(await res.arrayBuffer()).toString('utf8');
  const reader = res.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (size < MAX_BYTES) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(Buffer.from(value));
      size += value.length;
      if (/<\/head>/i.test(Buffer.concat(chunks).toString('latin1'))) break;
    }
  } finally {
    reader.cancel().catch(() => {});
  }
  return Buffer.concat(chunks).toString('utf8');
}

/**
 * The title of the page at [raw], or null when it has none (or is not a
 * page). Throws FeedError for an address that cannot be asked.
 */
export async function fetchLinkTitle(
  raw,
  { fetchImpl = fetch, lookup = dnsLookup, allowPrivate = false } = {}
) {
  let url;
  try {
    url = new URL(String(raw ?? ''));
  } catch {
    throw new FeedError('Not a web address', 400);
  }

  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    if (url.protocol !== 'https:' && url.protocol !== 'http:') {
      throw new FeedError('Not a web address', 400);
    }
    if (!allowPrivate) await assertPublic(url, lookup);

    let res;
    try {
      res = await fetchImpl(url, {
        redirect: 'manual',
        signal: AbortSignal.timeout(TIMEOUT_MS),
        headers: {
          accept: 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.5',
          // Some sites answer a bare client with a bot wall and its title.
          'user-agent': 'Mozilla/5.0 (compatible; TodoWidget link titles)',
        },
      });
    } catch (err) {
      throw new FeedError(`Could not reach it: ${err.message ?? err}`);
    }

    if (res.status >= 300 && res.status < 400 && res.headers.get('location')) {
      url = new URL(res.headers.get('location'), url);
      continue;
    }
    if (res.status !== 200) return null;
    const type = res.headers.get('content-type') ?? '';
    if (type && !/html/i.test(type)) {
      res.body?.cancel().catch(() => {});
      return null;
    }
    return titleFromHtml(await readHead(res));
  }
  throw new FeedError('Too many redirects');
}

/** Titles already looked up, so a list of links on every device costs one fetch each. */
export class TitleCache {
  constructor({ max = 2000, ttlMs = 24 * 60 * 60 * 1000, now = Date.now } = {}) {
    this.max = max;
    this.ttlMs = ttlMs;
    this.now = now;
    this.map = new Map();
  }

  get(url) {
    const hit = this.map.get(url);
    if (!hit) return undefined;
    if (this.now() - hit.at > this.ttlMs) {
      this.map.delete(url);
      return undefined;
    }
    return hit.title;
  }

  set(url, title) {
    this.map.delete(url);
    this.map.set(url, { title, at: this.now() });
    while (this.map.size > this.max) this.map.delete(this.map.keys().next().value);
  }
}
