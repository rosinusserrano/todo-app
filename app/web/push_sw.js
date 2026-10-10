// Receives reminders pushed by the sync server (server/push.js) and shows them.
//
// The only service worker this site registers. It deliberately has no fetch
// handler: the app is served no-cache so a deploy is picked up on the next
// open, and a caching worker would undo that.

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { body: event.data ? event.data.text() : '' };
  }
  // iOS revokes the subscription of a site that receives a push and shows
  // nothing, so every push shows something.
  event.waitUntil(
    self.registration.showNotification(data.title || 'Todo', {
      body: data.body || '',
      tag: data.tag,
      icon: 'icons/Icon-192.png',
      data: { url: data.url || '/' },
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = new URL(
    (event.notification.data && event.notification.data.url) || '/',
    self.location.origin
  ).href;
  event.waitUntil(
    (async () => {
      const open = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const client of open) {
        if ('focus' in client) return client.focus();
      }
      return self.clients.openWindow(url);
    })()
  );
});
