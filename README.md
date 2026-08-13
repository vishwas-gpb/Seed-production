# Seed Production Log — offline Shiny (shinylive) PWA

An offline-first field logging app for seed production, written in **R / Shiny**,
compiled to **WebAssembly** with **shinylive** (R runs in the browser via webR),
hosted free on **GitHub Pages**, and installable as a **PWA** that works with no
signal.

## The offline model (read this first)

There is **no server and no shared database**. R runs entirely in each visitor's
browser. That means:

- Each device stores its **own** records in the browser (IndexedDB). Devices do
  **not** see each other's data.
- To build a combined dataset you **export CSV** from each device and collect the
  files centrally (email / shared folder / a separate online dashboard).
- The **first load must be online** — it downloads the webR + package bundle (tens
  of MB) and caches it. After that the installed app opens and logs offline.
- Browser storage is wiped if the user clears browsing data, so **export CSV is
  the real backup**, not IndexedDB.

## Repository layout

```
seed-log-app/
├── app/
│   └── app.R                 # the Shiny app (edit crop lists, fields here)
├── pwa/
│   ├── manifest.json         # PWA manifest
│   ├── sw.js                 # service worker (offline cache)
│   ├── inject.R              # post-export: wires PWA into index.html
│   ├── icon-192.png          # replace with your own icons if you like
│   └── icon-512.png
├── .github/workflows/
│   └── deploy.yml            # builds + deploys to GitHub Pages on push
├── .gitignore
└── README.md
```

## 1. Develop locally

You can run and test it as a normal Shiny app (records save to a local
`.local-data/` folder instead of IndexedDB):

```r
install.packages(c("shiny", "bslib", "DT"))
shiny::runApp("app")
```

## 2. Preview the exported (WebAssembly) build

```r
install.packages("shinylive")
shinylive::export("app", "_site")
source("pwa/inject.R")                 # adds manifest + service worker
httpuv::runStaticServer("_site/", port = 8008)
```

## 3. Deploy to GitHub Pages

1. Create a GitHub repo and push this folder to `main`.
2. In the repo: **Settings → Pages → Build and deployment → Source: GitHub
   Actions**.
3. Every push to `main` runs `.github/workflows/deploy.yml`, which exports the
   app, injects the PWA, and publishes. The live URL appears in the Actions run
   and under Settings → Pages.

The workflow keeps the large WebAssembly assets **out of your repo** (they are
built fresh each run), so the repo stays small.

## 4. Install on a phone

Open the Pages URL once **with signal**, then use the browser's *Add to Home
Screen*. After that the app opens and logs offline. Staff export CSV when back in
coverage; you pool the CSVs centrally.

## Extending the app

- **Fields / crops:** edit `CROPS`, `CLASSES`, `SEASONS` and the input list in
  `app/app.R`.
- **More record types** (inspections, harvest/quality): add more `nav_panel`s,
  each with its own form and its own `records.rds` file, following the same
  save/load pattern.
- **GPS:** the "Use device GPS" button uses the browser geolocation API — works
  on HTTPS (GitHub Pages is HTTPS).

## Caveats & gotchas

- **Only webR-available packages work.** Keep dependencies light (this app uses
  only shiny, bslib, DT) — every package adds to the first-load size. Do **not**
  use `DBI`/`RPostgres`/`httr` for a live DB; there is no server.
- **IndexedDB persistence** (`webr::mount` + `webr::syncfs`) requires webR's
  *PostMessage* channel, not SharedArrayBuffer. GitHub Pages cannot send the
  COOP/COEP headers needed for SharedArrayBuffer, so it falls back to PostMessage
  automatically — which is what we want. If persistence ever misbehaves, that
  channel setting is the first thing to check.
- **Service worker is cache-first.** When you ship an update, bump the `CACHE`
  version in `pwa/sw.js` (e.g. `seed-log-v2`) so devices refetch.
- **Replace the icons** in `pwa/` with your own branding if desired (keep the
  192px and 512px sizes and filenames, or update `manifest.json`).
