const CACHE = "central-comercial-v4";
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
    caches.match(event.request).then((cached) => cached || fetch(event.request))
  );
});
