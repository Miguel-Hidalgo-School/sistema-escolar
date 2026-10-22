// Service worker de Sistema Escolar / CheckIn Kids.
// - Hace instalable el sitio como app (igual que antes).
// - NUEVO: guarda en el teléfono las páginas y librerías para que abran SIN Internet.
//   Siempre intenta primero la red (para ver los cambios al instante), pero si no hay
//   señal o responde muy lento (más de 4 s) usa la copia guardada.
// - Nunca toca las llamadas a Firebase (base de datos, login): esas van directo.

const CACHE_NAME = 'sistema-escolar-v3';
const PRECACHE = ['./', 'index.html', 'checkin-kids.html', 'usuarios.html', 'banos.html',
  'manifest.json', 'manifest-checkin.json'];
const CDN_OK = ['www.gstatic.com', 'fonts.googleapis.com', 'fonts.gstatic.com', 'cdn.jsdelivr.net', 'cdnjs.cloudflare.com'];
const NET_TIMEOUT = 8000;

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    // Cada archivo por separado: si alguno no existe, los demás igual se guardan.
    await Promise.all(PRECACHE.map(u => cache.add(new Request(u, { cache: 'reload' })).catch(() => {})));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

function redConTiempo(request) {
  // Devuelve { promesa, resultado }: resultado se resuelve con la respuesta, o con null si tarda demasiado.
  const promesa = fetch(request);
  const resultado = new Promise((resolve) => {
    const t = setTimeout(() => resolve(null), NET_TIMEOUT);
    promesa.then(r => { clearTimeout(t); resolve(r); }, () => { clearTimeout(t); resolve(null); });
  });
  return { promesa, resultado };
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // Firebase (datos y login) y cualquier otra API: sin tocar.
  if (url.origin !== self.location.origin && !CDN_OK.includes(url.hostname)) return;
  if (url.hostname === 'www.gstatic.com' && !url.pathname.startsWith('/firebasejs/')) return;

  // Librerías y fuentes (no cambian): primero la copia guardada; si no hay, se baja y se guarda.
  if (url.origin !== self.location.origin) {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE_NAME);
      const hit = await cache.match(req);
      if (hit) return hit;
      try {
        const res = await fetch(req);
        if (res && (res.ok || res.type === 'opaque')) cache.put(req, res.clone());
        return res;
      } catch (e) {
        return new Response('', { status: 504 });
      }
    })());
    return;
  }

  // Páginas y archivos propios: red primero (máx. 4 s); si falla o tarda, copia guardada.
  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const { promesa, resultado } = redConTiempo(req);
    const res = await resultado;
    if (res && res.ok) {
      cache.put(req, res.clone());
      return res;
    }
    const hit = await cache.match(req, { ignoreSearch: true });
    if (hit) {
      // Si la red solo iba lenta, que termine en segundo plano y deje la copia al día.
      event.waitUntil(promesa.then(r => { if (r && r.ok) cache.put(req, r.clone()); }).catch(() => {}));
      return hit;
    }
    if (res) return res;
    try { return await promesa; } catch (e) { return new Response('Sin conexión', { status: 503 }); }
  })());
});
