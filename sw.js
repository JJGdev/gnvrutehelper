/* GnvRuteHelper · trabajador de fondo (service worker)
   - Guarda la app en el móvil: abre al instante y sin gastar datos.
   - La página principal se pide primero a internet (así siempre tienes la última versión)
     y si no hay cobertura se usa la guardada.
   - Los trozos del mapa se guardan al verlos, para no descargarlos dos veces.
   - Supabase, direcciones y rutas andando siempre van a internet (son datos vivos). */
const VERSION = 'v5';
const APP = 'gnv-app-' + VERSION, MAPA = 'gnv-mapa-v1';
const BASE = ['./', './index.html', './manifest.webmanifest', './icons/icon-192.png', './icons/icon-512.png', './icons/apple-touch-icon.png'];
const LIBS = ['https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css',
              'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(APP).then(async c => {
    await c.addAll(BASE);
    await Promise.all(LIBS.map(u => c.add(u).catch(() => {})));   // si falla una librería, se guardará al usarla
  }).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k.startsWith('gnv-app-') && k !== APP).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const req = e.request; if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // Página principal: primero internet, si no, la guardada
  if (req.mode === 'navigate'){
    e.respondWith(fetch(req).then(r => { const copia = r.clone(); caches.open(APP).then(c => c.put(req, copia)); return r; })
      .catch(async () => (await caches.match(req)) || caches.match('./index.html')));
    return;
  }
  // Trozos del mapa: los guardados primero (máximo ~600)
  if (url.hostname === 'tile.openstreetmap.org'){
    e.respondWith(caches.open(MAPA).then(async c => {
      const hit = await c.match(req); if (hit) return hit;
      const r = await fetch(req);
      if (r.ok){ c.put(req, r.clone()); c.keys().then(ks => { if (ks.length > 600) ks.slice(0, ks.length - 600).forEach(k => c.delete(k)); }); }
      return r;
    }));
    return;
  }
  // Archivos fijos de la app y librerías
  if (url.origin === location.origin || url.hostname === 'cdnjs.cloudflare.com'){
    e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(r => {
      if (r.ok && url.hostname === 'cdnjs.cloudflare.com'){ const copia = r.clone(); caches.open(APP).then(c => c.put(req, copia)); }
      return r;
    })));
  }
});
