// Service worker mínimo: necesario para que el navegador considere el
// sitio "instalable" como app (con ícono, pantalla completa y sin la
// barra de Chrome), en vez de ofrecer solo un acceso directo.
// No cachea nada de forma agresiva: siempre intenta ir a la red primero
// para que los alumnos y cambios se vean al instante.

const CACHE_NAME = 'sistema-escolar-v1';

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  event.respondWith(
    fetch(event.request).catch(() => caches.match(event.request))
  );
});
