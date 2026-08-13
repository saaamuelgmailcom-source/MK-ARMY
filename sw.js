// Minimal service worker — its only job is to make Chrome/Android treat
// this as an installable app (that requires a registered service worker
// with a fetch handler). It deliberately does NOT cache anything: this
// is a live chat app, and caching the page or its data risks showing
// someone old messages or an outdated app after an update. Every
// request just passes straight through to the network as normal.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {
  // No event.respondWith() call — requests are left completely
  // untouched and go to the network exactly as they would without
  // this file existing at all.
});
