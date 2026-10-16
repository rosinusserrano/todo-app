import assert from 'node:assert/strict';
import { test } from 'node:test';

import { FeedError } from './feeds.js';
import { TitleCache, fetchLinkTitle, titleFromHtml } from './links.js';

const publicLookup = async () => [{ address: '93.184.216.34' }];

function page(html, { status = 200, type = 'text/html; charset=utf-8', headers = {} } = {}) {
  return new Response(html, { status, headers: { 'content-type': type, ...headers } });
}

test('og:title wins over <title>, and entities are decoded', () => {
  assert.equal(
    titleFromHtml('<head><title>Site</title><meta property="og:title" content="A &amp; B"></head>'),
    'A & B'
  );
  assert.equal(titleFromHtml('<title>\n  Hello &#8211; world  </title>'), 'Hello – world');
  assert.equal(titleFromHtml('<p>no title</p>'), null);
  assert.equal(titleFromHtml('<title>   </title>'), null);
});

test('a page answers with its title', async () => {
  const title = await fetchLinkTitle('https://example.com/a', {
    lookup: publicLookup,
    fetchImpl: async () => page('<html><head><title>Example</title></head></html>'),
  });
  assert.equal(title, 'Example');
});

test('redirects are followed and each hop is checked', async () => {
  const seen = [];
  await assert.rejects(
    fetchLinkTitle('https://example.com/a', {
      lookup: async (host) => {
        seen.push(host);
        return [{ address: host === 'example.com' ? '93.184.216.34' : '192.168.1.5' }];
      },
      fetchImpl: async () =>
        new Response(null, { status: 302, headers: { location: 'http://router.lan/' } }),
    }),
    (err) => err instanceof FeedError && err.status === 400
  );
  assert.deepEqual(seen, ['example.com', 'router.lan']);
});

test('not a page, or not found, is no title rather than an error', async () => {
  const pdf = await fetchLinkTitle('https://example.com/a.pdf', {
    lookup: publicLookup,
    fetchImpl: async () => page('%PDF', { type: 'application/pdf' }),
  });
  assert.equal(pdf, null);
  const missing = await fetchLinkTitle('https://example.com/gone', {
    lookup: publicLookup,
    fetchImpl: async () => page('', { status: 404 }),
  });
  assert.equal(missing, null);
});

test('only http and https', async () => {
  await assert.rejects(fetchLinkTitle('file:///etc/passwd'), FeedError);
  await assert.rejects(fetchLinkTitle('not a url'), FeedError);
});

test('the cache forgets the oldest and what has gone stale', () => {
  let now = 0;
  const cache = new TitleCache({ max: 2, ttlMs: 100, now: () => now });
  cache.set('a', 'A');
  cache.set('b', null);
  cache.set('c', 'C');
  assert.equal(cache.get('a'), undefined);
  assert.equal(cache.get('b'), null);
  now = 200;
  assert.equal(cache.get('c'), undefined);
});
