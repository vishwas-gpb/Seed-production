// Offline service worker for the shinylive PWA — NETWORK-FIRST.
// Online: behaves like no service worker (always goes to the network), so it
// can never serve a stale page or break the live app. Every successful (200)
// same-origin response is copied into the cache as it loads. Offline: served
// from that cache, with index.html as the navigation fallback.
//
// Bump CACHE (v3 -> v4 ...) whenever you ship an update, to force a refresh.

const CACHE = "seed-log-v3";
const SHELL = ["./", "./index.html", "./manifest.json"];

self.addEventListener("install", (event) => {
  self.skipWaiting();
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL).catch(() => {})));
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
  if (url.origin !== self.location.origin) return;

  event.respondWith(
    fetch(req)
      .then((res) => {
        if (res && res.status === 200) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      })
      .catch(() =>
        caches.match(req).then(
          (r) => r || (req.mode === "navigate" ? caches.match("./index.html") : Response.error())
        )
      )
  );
});
