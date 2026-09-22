const CACHE = "central-comercial-v6";
const CACHE_VERSION = "v7";
const ACTIVE_CACHE = `${CACHE}-${CACHE_VERSION}`;

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
    caches.open(ACTIVE_CACHE)
      .then((cache) => cache.addAll(ASSETS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((key) => key !== ACTIVE_CACHE).map((key) => caches.delete(key)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  if (event.request.url.includes("supabase.co") || event.request.url.includes("/rest/v1/") || event.request.url.includes("/storage/v1/")) {
    return;
  }
  
  event.respondWith(
    fetch(event.request)
      .then((networkResponse) => {
        const resClone = networkResponse.clone();
        caches.open(ACTIVE_CACHE).then((cache) => cache.put(event.request, resClone));
        return networkResponse;
      })
      .catch(() => {
        return caches.match(event.request);
      })
  );
});
