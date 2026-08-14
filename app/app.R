# app.R — Seed Production Logging (offline shinylive PWA)
# ---------------------------------------------------------------------------
# Runs client-side via webR when exported with {shinylive}; also runs in a
# normal R session (shiny::runApp("app")) for local development and testing.
#
# There is NO server and NO shared database. Each device stores its own
# records in the browser (IndexedDB). Export CSV regularly and collect the
# files centrally. See README.md.
# ---------------------------------------------------------------------------

library(shiny)
library(bslib)
library(DT)

# ---- Storage ---------------------------------------------------------------
# In webR (shinylive) records persist to an IndexedDB-backed filesystem mounted
# at /data. In a normal R session they persist to a local folder so you can
# develop before exporting.

is_webr <- function() {
  identical(Sys.info()[["sysname"]], "Emscripten") ||
    grepl("emscripten|wasm", R.version$os, ignore.case = TRUE)
}

DATA_DIR  <- if (is_webr()) "/data" else file.path(getwd(), ".local-data")
DATA_FILE <- file.path(DATA_DIR, "records.rds")

empty_records <- function() {
  data.frame(
    lot_id = character(), crop = character(), variety = character(),
    seed_class = character(), season = character(), year = integer(),
    source_lot = character(), source_class = character(), area_ha = numeric(),
    district = character(), block = character(), village = character(),
    lat = numeric(), lon = numeric(), sowing_date = character(),
    grower = character(), grower_ref = character(), notes = character(),
    logged_at = character(), stringsAsFactors = FALSE
  )
}

mount_storage <- function() {
  if (is_webr() && requireNamespace("webr", quietly = TRUE)) {
    try({
      if (!dir.exists("/data")) dir.create("/data")
      webr::mount(mountpoint = "/data", type = "IDBFS")
      webr::syncfs(TRUE)   # pull previously saved data OUT of IndexedDB
    }, silent = TRUE)
  } else if (!dir.exists(DATA_DIR)) {
    dir.create(DATA_DIR, recursive = TRUE)
  }
}

flush_storage <- function() {
  if (is_webr() && requireNamespace("webr", quietly = TRUE)) {
    try(webr::syncfs(FALSE), silent = TRUE)  # write current state INTO IndexedDB
  }
}

load_records <- function() {
  if (file.exists(DATA_FILE)) {
    out <- try(readRDS(DATA_FILE), silent = TRUE)
    if (!inherits(out, "try-error") && is.data.frame(out)) return(out)
  }
  empty_records()
}

save_records <- function(df) {
  if (!dir.exists(DATA_DIR)) dir.create(DATA_DIR, recursive = TRUE)
  saveRDS(df, DATA_FILE)
  flush_storage()
}

# ---- Controlled vocabularies (edit to fit your portfolio) ------------------
CROPS   <- c("Paddy/Rice", "Pigeonpea", "Groundnut", "Finger millet (Ragi)",
             "Blackgram", "Greengram", "Sesame", "Other")
CLASSES <- c("Nucleus", "Breeder", "Foundation", "Certified")
SEASONS <- c("Kharif", "Rabi", "Summer")

# ---- Small JS: device geolocation -> Shiny input ---------------------------
geo_js <- HTML(
  "Shiny.addCustomMessageHandler('getGeo', function(x){",
  "  if (navigator.geolocation) {",
  "    navigator.geolocation.getCurrentPosition(function(p){",
  "      Shiny.setInputValue('geo', {lat: p.coords.latitude, lon: p.coords.longitude});",
  "    }, function(){ alert('Could not get GPS. Enable location and retry.'); });",
  "  } else { alert('Geolocation not supported on this device.'); }",
  "});"
)

# ---- UI --------------------------------------------------------------------
ui <- page_navbar(
  title = "Seed Production Log",
  theme = bs_theme(version = 5, primary = "#2e7d32"),
  header = tags$head(
    tags$meta(name = "viewport",
              content = "width=device-width, initial-scale=1, maximum-scale=1"),
    tags$script(geo_js)
  ),

  nav_panel(
    "Log entry",
    layout_column_wrap(
      width = "240px",
      textInput("lot_id", "Lot ID *", placeholder = "e.g. PDY-MTU1010-K26-001"),
      selectInput("crop", "Crop *", choices = CROPS),
      textInput("variety", "Variety *", placeholder = "e.g. MTU-1010"),
      selectInput("seed_class", "Seed class *", choices = CLASSES),
      selectInput("season", "Season *", choices = SEASONS),
      numericInput("year", "Year *",
                   value = as.integer(format(Sys.Date(), "%Y")),
                   min = 2020, max = 2100, step = 1),
      textInput("source_lot", "Source seed lot no."),
      selectInput("source_class", "Source seed class", choices = c("", CLASSES)),
      numericInput("area_ha", "Area (ha) *", value = NA, min = 0, step = 0.1),
      textInput("district", "District"),
      textInput("block", "Block"),
      textInput("village", "Village"),
      numericInput("lat", "GPS latitude", value = NA, step = 0.00001),
      numericInput("lon", "GPS longitude", value = NA, step = 0.00001),
      dateInput("sowing_date", "Sowing date"),
      textInput("grower", "Grower name"),
      textInput("grower_ref", "Grower reg / KYC ref")
    ),
    div(class = "mt-2",
        actionButton("get_gps", "Use device GPS", class = "btn-outline-secondary btn-sm",
                     icon = icon("location-crosshairs"))),
    textAreaInput("notes", "Notes", rows = 2, width = "100%"),
    div(class = "d-flex gap-2 mt-2",
        actionButton("save", "Save record", class = "btn-primary"),
        actionButton("clear", "Clear form", class = "btn-outline-secondary"))
  ),

  nav_panel(
    "Records",
    div(class = "d-flex justify-content-between align-items-center flex-wrap gap-2 mb-2",
        span(textOutput("count", inline = TRUE)),
        div(class = "d-flex gap-2",
            downloadButton("download_csv", "Export CSV", class = "btn-success btn-sm"),
            actionButton("delete_sel", "Delete selected",
                         class = "btn-outline-danger btn-sm"))),
    DTOutput("tbl")
  ),

  nav_panel(
    "About",
    card(
      card_header("Offline seed production log"),
      p(strong("Data lives on this device only."),
        " There is no shared server. Export CSV regularly and collect the files",
        " centrally to build a combined dataset."),
      p(strong("Install for offline use:"),
        " open this page once while you have signal, then use your browser's",
        " \u201cAdd to Home Screen\u201d. After that it opens and logs without a connection."),
      p(strong("Backup:"),
        " clearing your browser data erases stored records \u2014 export CSV first.")
    )
  )
)

# ---- Server ----------------------------------------------------------------
server <- function(input, output, session) {

  mount_storage()
  records <- reactiveVal(load_records())

  # GPS
  observeEvent(input$get_gps, session$sendCustomMessage("getGeo", list()))
  observeEvent(input$geo, {
    updateNumericInput(session, "lat", value = round(input$geo$lat, 6))
    updateNumericInput(session, "lon", value = round(input$geo$lon, 6))
  })

  output$count <- renderText({
    n <- nrow(records())
    paste0(n, if (n == 1) " record" else " records", " on this device")
  })

  reset_form <- function() {
    for (id in c("lot_id", "variety", "source_lot", "district", "block",
                 "village", "grower", "grower_ref"))
      updateTextInput(session, id, value = "")
    updateSelectInput(session, "source_class", selected = "")
    for (id in c("area_ha", "lat", "lon"))
      updateNumericInput(session, id, value = NA)
    updateTextAreaInput(session, "notes", value = "")
  }
  observeEvent(input$clear, reset_form())

  observeEvent(input$save, {
    missing <- character()
    if (!nzchar(trimws(input$lot_id)))  missing <- c(missing, "Lot ID")
    if (!nzchar(trimws(input$variety))) missing <- c(missing, "Variety")
    if (is.na(input$area_ha))           missing <- c(missing, "Area (ha)")
    if (length(missing)) {
      showNotification(paste("Please fill:", paste(missing, collapse = ", ")),
                       type = "error"); return()
    }
    if (input$lot_id %in% records()$lot_id) {
      showNotification("A record with this Lot ID already exists.",
                       type = "warning"); return()
    }
    new <- data.frame(
      lot_id = input$lot_id, crop = input$crop, variety = input$variety,
      seed_class = input$seed_class, season = input$season,
      year = as.integer(input$year), source_lot = input$source_lot,
      source_class = input$source_class, area_ha = input$area_ha,
      district = input$district, block = input$block, village = input$village,
      lat = input$lat, lon = input$lon,
      sowing_date = as.character(input$sowing_date),
      grower = input$grower, grower_ref = input$grower_ref, notes = input$notes,
      logged_at = as.character(Sys.time()), stringsAsFactors = FALSE
    )
    df <- rbind(records(), new)
    records(df); save_records(df)
    showNotification("Record saved.", type = "message")
    reset_form()
  })

  observeEvent(input$delete_sel, {
    sel <- input$tbl_rows_selected
    if (length(sel)) {
      df <- records()[-sel, , drop = FALSE]
      records(df); save_records(df)
      showNotification("Deleted selected record(s).", type = "message")
    }
  })

  output$tbl <- renderDT(
    datatable(records(), selection = "multiple", rownames = FALSE,
              options = list(scrollX = TRUE, pageLength = 10))
  )

  output$download_csv <- downloadHandler(
    filename = function() paste0("seed-log-", Sys.Date(), ".csv"),
    content  = function(file) write.csv(records(), file, row.names = FALSE)
  )

  # extra safety: flush to IndexedDB when the session ends
  session$onSessionEnded(flush_storage)
}

shinyApp(ui, server)
