const CACHE_VERSION = 'demografie-shell-v1';
const APP_SHELL = [
  './sn_zp_demografie_planung.html',
  './demografie.webmanifest',
  './icons/demografie-192.png',
  './icons/demografie-512.png'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_VERSION)
      .then(cache => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys
        .filter(key => key.startsWith('demografie-shell-') && key !== CACHE_VERSION)
        .map(key => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  if (event.request.mode !== 'navigate') return;

  event.respondWith(
    fetch(event.request).catch(() => caches.match('./sn_zp_demografie_planung.html'))
  );
});