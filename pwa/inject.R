# Run AFTER shinylive::export(). Copies the PWA assets into the exported site
# and injects the manifest link + service-worker registration into index.html.
# Usage:  Rscript pwa/inject.R _site

args <- commandArgs(trailingOnly = TRUE)
site <- if (length(args) >= 1) args[[1]] else "_site"

# 1) copy PWA assets to the site root
file.copy("pwa/manifest.json", file.path(site, "manifest.json"), overwrite = TRUE)
file.copy("pwa/sw.js",          file.path(site, "sw.js"),         overwrite = TRUE)
for (ic in c("icon-192.png", "icon-512.png")) {
  p <- file.path("pwa", ic)
  if (file.exists(p)) file.copy(p, file.path(site, ic), overwrite = TRUE)
}

# 2) inject <link rel=manifest>, theme-color, and SW registration before </head>
index <- file.path(site, "index.html")
html  <- readLines(index, warn = FALSE)

inject <- paste0(
  '<link rel="manifest" href="manifest.json">',
  '<meta name="theme-color" content="#2e7d32">',
  '<link rel="apple-touch-icon" href="icon-192.png">',
  '<script>if("serviceWorker" in navigator){',
  'window.addEventListener("load",function(){',
  'navigator.serviceWorker.register("sw.js").catch(function(e){console.log(e);});',
  '});}</script>'
)

if (any(grepl("</head>", html, fixed = TRUE))) {
  html <- sub("</head>", paste0(inject, "</head>"), html, fixed = TRUE)
} else {
  # fallback: prepend if no </head> found
  html <- c(inject, html)
}
writeLines(html, index)
cat("PWA assets injected into", index, "\n")
