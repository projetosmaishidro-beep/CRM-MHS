const CACHE = "central-comercial-v6";
const ASSETS = [
  "./",
  "./index.html",
  "./assets/css/styles.css",
  "./assets/js/data.js",
  "./assets/js/store.js",
  "./assets/js/ui.js",
  "./assets/js/app.js",
  "./assets/images/logo-mais.jpg",
  "./assets/js/pdf-report.js"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then((cache) => cache.addAll(ASSETS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  
  event.respondWith(
    fetch(event.request)
      .then((networkResponse) => {
        // Se a rede retornar com sucesso, atualiza o cache silenciosamente com a versão mais fresca
        const resClone = networkResponse.clone();
        caches.open(CACHE).then((cache) => cache.put(event.request, resClone));
        return networkResponse;
      })
      .catch(() => {
        // Se a rede falhar (usuário offline), serve do cache
        return caches.match(event.request);
      })
  );
});
