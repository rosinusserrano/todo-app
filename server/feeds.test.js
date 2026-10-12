// The calendar-feed fetch the web app goes through. Run with: npm run test:server
//
// What is worth pinning is what keeps a server that fetches addresses users
// type from being pointed at itself: private addresses refused on every hop,
// redirects included, and nothing relayed that is not a calendar.

import test from 'node:test';
import assert from 'node:assert/strict';

import { FeedError, feedUrl, fetchFeed, isPrivateAddress } from './feeds.js';

const CAL = 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nSUMMARY:x\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';

/** A fetch that answers from a table keyed by URL. */
function fakeFetch(routes) {
  const asked = [];
  const impl = async (url) => {
    asked.push(String(url));
    const r = routes[String(url)];
    if (!r) throw new Error('no route');
    return new Response(r.body ?? null, { status: r.status ?? 200, headers: r.headers ?? {} });
  };
  impl.asked = asked;
  return impl;
}

const publicDns = async () => [{ address: '93.184.216.34' }];

test('webcal is https', () => {
  assert.equal(feedUrl('webcal://calendar.google.com/a.ics').href, 'https://calendar.google.com/a.ics');
  assert.equal(feedUrl('calendar.google.com/a.ics').href, 'https://calendar.google.com/a.ics');
  assert.equal(feedUrl(''), null);
});

test('private and loopback addresses are recognised', () => {
  for (const ip of ['127.0.0.1', '10.1.2.3', '192.168.2.184', '172.20.0.1', '169.254.1.1', '::1', 'fd00::1', '::ffff:127.0.0.1', '100.100.1.1']) {
    assert.ok(isPrivateAddress(ip), ip);
  }
  for (const ip of ['93.184.216.34', '8.8.8.8', '2606:4700::1111']) {
    assert.ok(!isPrivateAddress(ip), ip);
  }
});

test('a calendar comes back as text', async () => {
  const fetchImpl = fakeFetch({ 'https://example.com/a.ics': { body: CAL } });
  const text = await fetchFeed('webcal://example.com/a.ics', { fetchImpl, lookup: publicDns });
  assert.equal(text, CAL);
});

test('a page that is not a calendar is refused, not relayed', async () => {
  const fetchImpl = fakeFetch({ 'https://example.com/page': { body: '<html>secret</html>' } });
  await assert.rejects(
    fetchFeed('https://example.com/page', { fetchImpl, lookup: publicDns }),
    (err) => err instanceof FeedError && err.status === 422 && !err.message.includes('secret')
  );
});

test('a host on the local network is refused before anything is fetched', async () => {
  const fetchImpl = fakeFetch({});
  await assert.rejects(
    fetchFeed('http://127.0.0.1:8787/api/admin/users', { fetchImpl, lookup: publicDns }),
    (err) => err.status === 400
  );
  await assert.rejects(
    fetchFeed('https://intranet.example/a.ics', {
      fetchImpl,
      lookup: async () => [{ address: '192.168.1.10' }],
    }),
    (err) => err.status === 400
  );
  assert.equal(fetchImpl.asked.length, 0);
});

test('a redirect to a private address is refused too', async () => {
  const fetchImpl = fakeFetch({
    'https://example.com/a.ics': { status: 302, headers: { location: 'http://127.0.0.1/x' } },
  });
  await assert.rejects(
    fetchFeed('https://example.com/a.ics', { fetchImpl, lookup: publicDns }),
    (err) => err.status === 400
  );
  assert.deepEqual(fetchImpl.asked, ['https://example.com/a.ics']);
});

test('a public redirect is followed', async () => {
  const fetchImpl = fakeFetch({
    'https://example.com/a.ics': { status: 301, headers: { location: '/b.ics' } },
    'https://example.com/b.ics': { body: CAL },
  });
  assert.equal(await fetchFeed('https://example.com/a.ics', { fetchImpl, lookup: publicDns }), CAL);
});

test('allowPrivate lets a LAN calendar through', async () => {
  const fetchImpl = fakeFetch({ 'http://192.168.1.10/a.ics': { body: CAL } });
  assert.equal(
    await fetchFeed('http://192.168.1.10/a.ics', { fetchImpl, lookup: publicDns, allowPrivate: true }),
    CAL
  );
});
