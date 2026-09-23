const CACHE = "central-comercial-v6";
const CACHE_VERSION = "v11";
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
  const requestUrl = new URL(event.request.url);
  if (
    !["http:", "https:"].includes(requestUrl.protocol) ||
    requestUrl.origin !== self.location.origin ||
    requestUrl.hostname.endsWith("supabase.co") ||
    requestUrl.pathname.includes("/rest/v1/") ||
    requestUrl.pathname.includes("/storage/v1/")
  ) {
    return;
  }

  event.respondWith(
    fetch(event.request)
      .then((networkResponse) => {
        if (networkResponse.ok) {
          const responseForCache = networkResponse.clone();
          event.waitUntil(
            caches.open(ACTIVE_CACHE)
              .then((cache) => cache.put(event.request, responseForCache))
              .catch((error) => console.warn("[SW] Nao foi possivel atualizar o cache:", error))
          );
        }
        return networkResponse;
      })
      .catch(() => {
        return caches.match(event.request);
      })
  );
});
