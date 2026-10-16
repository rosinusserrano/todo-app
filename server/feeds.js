// Fetching a subscribed calendar on behalf of the web app.
//
// A browser cannot fetch a Google (or Outlook, or iCloud) calendar address
// itself: those servers send no CORS headers, so the page is refused the
// response. The native builds ask the address directly; the web build asks
// this route, which fetches it and hands the text back. Nothing is parsed or
// stored here - the client does all of that, exactly as it does natively, so
// there is still one parser and one place a feed becomes rows.
//
// It is a server making requests to addresses a user typed, which is the shape
// of a server-side request forgery, and three things keep it from being one:
//
//   - **Authenticated.** Only an account on this server can use it.
//   - **Public addresses only.** Every hop - the first request and each
//     redirect, which are followed by hand for exactly this reason - must
//     resolve to an address outside loopback, private, link-local and the
//     like, so it cannot be pointed at the machine it runs on or the LAN
//     behind it. TODO_FEED_ALLOW_PRIVATE=1 lifts that, for a calendar served
//     from inside the network.
//   - **Calendars only.** A response that is not an iCalendar file is refused
//     rather than relayed, so even a reachable address yields nothing that is
//     not already a calendar.

import { lookup as dnsLookup } from 'node:dns/promises';
import { isIP } from 'node:net';

const MAX_BYTES = 20 * 1024 * 1024;
const TIMEOUT_MS = 30_000;
const MAX_REDIRECTS = 5;

export class FeedError extends Error {
  constructor(message, status = 502) {
    super(message);
    this.status = status;
  }
}

/** `webcal://` is https with a hint about which app should open it. */
export function feedUrl(raw) {
  if (typeof raw !== 'string' || !raw.trim()) return null;
  let s = raw.trim();
  s = s.replace(/^webcals?:\/\//i, 'https://');
  if (!/^https?:\/\//i.test(s)) s = `https://${s}`;
  try {
    const u = new URL(s);
    return u.hostname ? u : null;
  } catch {
    return null;
  }
}

/** Whether an IP address is one a public calendar cannot be at. */
export function isPrivateAddress(ip) {
  if (isIP(ip) === 4) {
    const [a, b] = ip.split('.').map(Number);
    return (
      a === 0 ||
      a === 10 ||
      a === 127 ||
      (a === 100 && b >= 64 && b <= 127) ||
      (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168) ||
      a >= 224
    );
  }
  const v6 = ip.toLowerCase();
  if (v6 === '::' || v6 === '::1') return true;
  // An IPv4 address written as IPv6 is the IPv4 address.
  const mapped = v6.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  if (mapped) return isPrivateAddress(mapped[1]);
  return /^(fc|fd|fe[89ab])/.test(v6);
}

export async function assertPublic(url, lookup) {
  const host = url.hostname.replace(/^\[|\]$/g, '');
  const addresses = isIP(host)
    ? [{ address: host }]
    : await lookup(host, { all: true }).catch(() => {
        throw new FeedError(`Cannot resolve ${host}`);
      });
  if (addresses.some((a) => isPrivateAddress(a.address))) {
    throw new FeedError('That address is on a private network', 400);
  }
}

/**
 * Fetch a calendar's text, following redirects by hand so each hop is checked.
 * `fetchImpl` and `lookup` are injectable for the tests.
 */
export async function fetchFeed(
  raw,
  { fetchImpl = fetch, lookup = dnsLookup, allowPrivate = false } = {}
) {
  let url = feedUrl(raw);
  if (!url) throw new FeedError('Not a calendar address', 400);

  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    if (url.protocol !== 'https:' && url.protocol !== 'http:') {
      throw new FeedError('Not a calendar address', 400);
    }
    if (!allowPrivate) await assertPublic(url, lookup);

    let res;
    try {
      res = await fetchImpl(url, {
        redirect: 'manual',
        signal: AbortSignal.timeout(TIMEOUT_MS),
        headers: { accept: 'text/calendar, */*;q=0.5' },
      });
    } catch (err) {
      throw new FeedError(`Could not reach it: ${err.message ?? err}`);
    }

    if (res.status >= 300 && res.status < 400 && res.headers.get('location')) {
      url = new URL(res.headers.get('location'), url);
      continue;
    }
    if (res.status === 404) throw new FeedError('Not found - the address may have been reset', 404);
    if (res.status === 401 || res.status === 403) {
      throw new FeedError('Not allowed - the calendar is not shared at that address', 403);
    }
    if (res.status !== 200) throw new FeedError(`The calendar server answered ${res.status}`);

    const declared = Number(res.headers.get('content-length'));
    if (declared > MAX_BYTES) throw new FeedError('That calendar is too large', 413);
    const bytes = Buffer.from(await res.arrayBuffer());
    if (bytes.length > MAX_BYTES) throw new FeedError('That calendar is too large', 413);

    const text = bytes.toString('utf8');
    if (!text.includes('BEGIN:VCALENDAR')) {
      throw new FeedError(
        'That address did not return a calendar. Use the iCal (.ics) address, not the page link',
        422
      );
    }
    return text;
  }
  throw new FeedError('Too many redirects');
}
