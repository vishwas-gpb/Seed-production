// Service worker for offline use.
// Strategy: cache-first with runtime caching. On the first ONLINE visit every
// same-origin asset (index.html + the webR / shinylive WebAssembly bundle) is
// fetched and cached; afterwards the app opens with no connection.
//
// NOTE: this is cache-first, so when you ship an update you must bump CACHE
// (e.g. seed-log-v2) to force clients to refetch.

const CACHE = "seed-log-v1";
const CORE  = ["./", "./index.html", "./manifest.json"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(CORE)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // only cache our own assets

  event.respondWith(
    caches.match(req).then((cached) => {
      if (cached) return cached;
      return fetch(req)
        .then((res) => {
          if (res && res.status === 200 && res.type === "basic") {
            const copy = res.clone();
            caches.open(CACHE).then((c) => c.put(req, copy));
          }
          return res;
        })
        .catch(() => cached); // offline and not in cache
    })
  );
});
