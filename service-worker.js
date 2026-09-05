// Service Worker para Bitácora - Offline First
//
// Estrategia (corregida):
// - Documentos HTML (bitacora.html, etc.): "red primero, caché de respaldo".
//   Siempre intenta traer la versión más nueva del servidor; solo usa la
//   copia guardada si no hay conexión. Así, cada vez que subas un cambio a
//   bitacora.html, se ve de inmediato sin tener que cerrar sesión ni borrar
//   datos del sitio.
// - Recursos externos que casi nunca cambian (Tailwind, Firebase SDK):
//   "caché primero", pero refrescando la copia guardada en segundo plano
//   para no perder velocidad de carga.
//
// Sube el número de CACHE_NAME cada vez que quieras forzar que TODOS los
// dispositivos tiren su caché vieja de golpe (por ejemplo, si algún día
// vuelve a haber un problema de contenido desactualizado).
const CACHE_NAME = 'bitacora-v2';
const urlsToCache = [
  './',
  './bitacora.html',
  './promo-sistema-escolar.html',
  'https://cdn.tailwindcss.com',
  'https://www.gstatic.com/firebasejs/9.23.0/firebase-app-compat.js',
  'https://www.gstatic.com/firebasejs/9.23.0/firebase-auth-compat.js',
  'https://www.gstatic.com/firebasejs/9.23.0/firebase-database-compat.js'
];

// Instala el service worker y precarga los archivos base.
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => {
      console.log('Service Worker: Cacheando archivos offline...');
      return cache.addAll(urlsToCache).catch(err => {
        console.log('Algunos recursos no pudieron cachearse:', err);
        // Continúa aunque algunos fallen
      });
    })
  );
  self.skipWaiting(); // Activa esta versión nueva de inmediato
});

// Al activarse, borra cualquier caché de una versión anterior (esto es lo
// que garantiza que una copia vieja de bitacora.html nunca se quede
// "atorada" para siempre).
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(cacheNames => {
      return Promise.all(
        cacheNames.map(cacheName => {
          if (cacheName !== CACHE_NAME) {
            console.log('Service Worker: Eliminando caché antiguo:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
  self.clients.claim(); // Toma control de las pestañas ya abiertas de inmediato
});

self.addEventListener('fetch', event => {
  // Solo intervenir en peticiones GET
  if (event.request.method !== 'GET') return;

  const esDocumentoHtml =
    event.request.mode === 'navigate' ||
    (event.request.headers.get('accept') || '').includes('text/html');

  if (esDocumentoHtml) {
    // ---- RED PRIMERO (para HTML) ----
    event.respondWith(
      fetch(event.request)
        .then(response => {
          if (response && response.status === 200) {
            const copia = response.clone();
            caches.open(CACHE_NAME).then(cache => cache.put(event.request, copia));
          }
          return response;
        })
        .catch(() =>
          caches.match(event.request).then(cached => cached || caches.match('./bitacora.html'))
        )
    );
    return;
  }

  // ---- CACHÉ PRIMERO, con refresco en segundo plano (para lo demás) ----
  event.respondWith(
    caches.match(event.request).then(cachedResponse => {
      const fetchPromise = fetch(event.request)
        .then(networkResponse => {
          if (networkResponse && networkResponse.status === 200) {
            const copia = networkResponse.clone();
            caches.open(CACHE_NAME).then(cache => cache.put(event.request, copia));
          }
          return networkResponse;
        })
        .catch(() => cachedResponse);

      return cachedResponse || fetchPromise;
    })
  );
});
