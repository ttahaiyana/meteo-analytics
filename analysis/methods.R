# Методы анализа. Каждый принимает запрос req (data_dir, locations, params) и возвращает список для JSON.

loc_info <- function(req, id) {
  l <- req$locations[req$locations$id == id, ]
  list(id = l$id, name = l$name, zone = l$zone, lat = l$lat, lon = l$lon)
}
get_series <- function(req, id) load_series(req$data_dir, id)
all_ids <- function(req) req$locations$id
param <- function(req, name, default = NULL) {
  v <- req$params[[name]]
  if (is.null(v) || identical(v, "")) default else v
}
need_loc <- function(req) {
  id <- param(req, "loc")
  if (is.null(id)) stop("не указан параметр loc")
  id
}

# ---- 1. Режим и сезонность --------------------------------------------------
m_seasonality <- function(req) {
  id <- need_loc(req)
  df <- get_series(req, id)
  b <- df[in_base(df), ]
  # нормы: средние месячные значения за базовый период
  mmean <- function(v) as.numeric(tapply(b[[v]], b$month, mean, na.rm = TRUE))
  ym <- aggregate(precip ~ year + month, b, sum)
  precip <- as.numeric(tapply(ym$precip, ym$month, mean))
  tmean <- mmean("tmean")
  dtr <- as.numeric(tapply(b$tmax - b$tmin, b$month, mean, na.rm = TRUE))
  cold <- which.min(tmean); warm <- which.max(tmean)
  # годовые аномалии относительно нормы
  yt <- agg_by(df$tmean, df$year, mean)
  yp <- agg_by(df$precip, df$year, sum)
  norm_t <- mean(yt$value[yt$key >= BASE[1] & yt$key <= BASE[2]], na.rm = TRUE)
  norm_p <- mean(yp$value[yp$key >= BASE[1] & yp$key <= BASE[2]], na.rm = TRUE)
  list(location = loc_info(req, id), base = paste(BASE, collapse = "–"), months = MONTHS_RU,
       tmean = tmean, tmax = mmean("tmax"), tmin = mmean("tmin"), precip = precip,
       wind = mmean("wind"), hum = mmean("hum"), dtr = dtr,
       coldest = MONTHS_RU[cold], warmest = MONTHS_RU[warm],
       dtr_coldest = dtr[cold], dtr_warmest = dtr[warm],
       years = yt$key, tmean_anom = yt$value - norm_t,
       precip_anom_pct = (yp$value - norm_p) / norm_p * 100,
       norm_tmean = norm_t, norm_precip = norm_p)
}

# ---- 2. Сравнение регионов ---------------------------------------------------
indicators <- function(df) {
  b <- df[in_base(df), ]
  ym <- aggregate(tmean ~ year + month, b, mean)
  mt <- tapply(ym$tmean, ym$month, mean)
  yp <- agg_by(b$precip, b$year, sum)
  list(tmean = mean(b$tmean, na.rm = TRUE), tmax_abs = max(b$tmax, na.rm = TRUE), tmin_abs = min(b$tmin, na.rm = TRUE),
       amplitude = max(mt) - min(mt), precip_year = mean(yp$value, na.rm = TRUE),
       wind = mean(b$wind, na.rm = TRUE), hum = mean(b$hum, na.rm = TRUE),
       hot_days = mean(tapply(b$tmax >= 30, b$year, sum, na.rm = TRUE)),
       frost_days = mean(tapply(b$tmin < 0, b$year, sum, na.rm = TRUE)),
       heavy_rain_days = mean(tapply(b$precip >= 20, b$year, sum, na.rm = TRUE)))
}

m_compare <- function(req) {
  ids <- all_ids(req)
  rows <- list(); prof <- list()
  for (id in ids) {
    df <- get_series(req, id)
    ind <- indicators(df)
    rows[[id]] <- c(list(id = id), ind)
    b <- df[in_base(df), ]
    ym <- aggregate(precip ~ year + month, b, sum)
    prof[[id]] <- list(id = id, tmean = as.numeric(tapply(b$tmean, b$month, mean, na.rm = TRUE)),
                       precip = as.numeric(tapply(ym$precip, ym$month, mean)))
  }
  tab <- do.call(rbind, lapply(rows, function(r) as.data.frame(r, stringsAsFactors = FALSE)))
  tab <- merge(req$locations[, c("id", "name", "zone", "lat", "lon")], tab, by = "id", sort = FALSE)
  feat <- c("tmean", "amplitude", "precip_year", "wind", "hum", "hot_days", "frost_days", "heavy_rain_days")
  n <- nrow(tab)
  k <- as.integer(param(req, "k", 4))
  k <- max(1, min(k, n - 1))
  tab$cluster <- 1L; tab$pc1 <- 0; tab$pc2 <- 0
  if (n >= 3 && k >= 2) {
    X <- scale(tab[, feat]); X[is.na(X)] <- 0
    set.seed(42)
    km <- kmeans(X, centers = k, nstart = 50)
    tab$cluster <- as.integer(km$cluster)
    pc <- prcomp(X)
    tab$pc1 <- pc$x[, 1]; tab$pc2 <- if (ncol(pc$x) >= 2) pc$x[, 2] else 0
  }
  list(base = paste(BASE, collapse = "–"), months = MONTHS_RU, k = k, features = feat,
       table = tab, profiles = unname(prof))
}

# ---- 3. Тренды ---------------------------------------------------------------
annual_series <- function(df, v) {
  a <- agg_by(df[[v]], df$year, VAR_FUN[[v]])
  a[a$key >= min(df$year) & a$key <= max(df$year), ]
}

m_trends <- function(req) {
  v <- param(req, "var", "tmean")
  fun <- VAR_FUN[[v]]
  id <- param(req, "loc")
  if (is.null(id)) {  # рейтинг «где тренд быстрее»
    rk <- lapply(all_ids(req), function(i) {
      a <- annual_series(get_series(req, i), v)
      s <- trend_stats(a$key, a$value)
      c(list(id = i, name = loc_info(req, i)$name, zone = loc_info(req, i)$zone), s[c("sen", "sen_lo", "sen_hi", "ols", "mk_p", "significant", "direction")])
    })
    rk <- do.call(rbind, lapply(rk, as.data.frame, stringsAsFactors = FALSE))
    rk <- rk[order(-rk$sen), ]
    return(list(var = v, unit = unname(VAR_UNIT[v]), per = "десятилетие", ranking = rk))
  }
  df <- get_series(req, id)
  a <- annual_series(df, v)
  st <- trend_stats(a$key, a$value)
  fit <- if (is.na(st$sen)) NULL else st$sen / 10 * range(a$key) + st$sen_intercept
  seasons <- lapply(names(SEASONS), function(s) {
    d <- df[df$season == s & df$syear > min(df$year) & df$syear <= max(df$year), ]
    sa <- agg_by(d[[v]], d$syear, fun, min_frac = 0.85)
    c(list(season = s, label = unname(SEASONS[s])), trend_stats(sa$key, sa$value)[c("n", "sen", "sen_lo", "sen_hi", "ols", "mk_p", "significant", "direction")])
  })
  list(location = loc_info(req, id), var = v, unit = unname(VAR_UNIT[v]), per = "десятилетие",
       years = a$key, values = a$value, stats = st, sen_line = list(x = range(a$key), y = fit),
       seasons = do.call(rbind, lapply(seasons, as.data.frame, stringsAsFactors = FALSE)))
}

# ---- 4. Экстремумы -----------------------------------------------------------
m_extremes <- function(req) {
  id <- need_loc(req)
  df <- get_series(req, id)
  b <- df[in_base(df), ]
  p95 <- unname(quantile(b$tmax, 0.95, na.rm = TRUE))
  wet <- b$precip[!is.na(b$precip) & b$precip >= 1]
  rain95 <- unname(quantile(wet, 0.95))
  years <- sort(unique(df$year))
  per_year <- lapply(years, function(y) {
    d <- df[df$year == y, ]
    hot <- d$tmax > p95
    hot[is.na(hot)] <- FALSE
    r <- rle(hot)
    list(year = y, hot_days = sum(hot), heatwaves = sum(r$values & r$lengths >= 3),
         frost_days = sum(d$tmin < 0, na.rm = TRUE), heavy_rain_days = sum(d$precip >= rain95, na.rm = TRUE),
         max_dry_spell = max_run(d$precip < 1), max_wind = max(d$wind, na.rm = TRUE), max_precip = max(d$precip, na.rm = TRUE))
  })
  py <- do.call(rbind, lapply(per_year, as.data.frame))
  tr <- lapply(c("hot_days", "heatwaves", "frost_days", "heavy_rain_days", "max_dry_spell"), function(k) {
    c(list(indicator = k), trend_stats(py$year, py[[k]])[c("sen", "sen_lo", "sen_hi", "mk_p", "significant", "direction")])
  })
  rec <- function(col, fun, label, unit) {
    i <- fun(df[[col]], na.rm = TRUE)
    j <- which(df[[col]] == i)[1]
    list(label = label, value = i, unit = unit, date = as.character(df$date[j]))
  }
  list(location = loc_info(req, id),
       thresholds = list(hot_p95_tmax = p95, heavy_rain_mm = rain95, base = paste(BASE, collapse = "–")),
       yearly = py, trends = do.call(rbind, lapply(tr, as.data.frame, stringsAsFactors = FALSE)),
       records = list(rec("tmax", max, "Рекордная жара", "°C"), rec("tmin", min, "Рекордный холод", "°C"),
                      rec("precip", max, "Максимум осадков за сутки", "мм"), rec("wind", max, "Максимальный ветер", "м/с")))
}

# ---- 5. Связи между параметрами ---------------------------------------------
m_correlations <- function(req) {
  id <- need_loc(req)
  df <- get_series(req, id)
  vars <- c("tmean", "precip", "hum", "wind", "pres", "cloud")
  labels <- c("Температура", "Осадки", "Влажность", "Ветер", "Давление", "Облачность")
  m <- function(method) {
    cm <- suppressWarnings(cor(df[, vars], use = "pairwise.complete.obs", method = method))
    unname(split(round(cm, 3), row(cm)))
  }
  set.seed(1)
  s <- df[sample(nrow(df), min(900, nrow(df))), vars]
  list(location = loc_info(req, id), vars = vars, labels = labels, pearson = m("pearson"), spearman = m("spearman"),
       sample = as.list(s))
}

# ---- 6. Прикладные выводы ----------------------------------------------------
m_insights <- function(req) {
  rows <- lapply(all_ids(req), function(id) {
    b <- get_series(req, id); b <- b[in_base(b), ]
    share <- function(cond) as.numeric(tapply(cond, b$month, function(x) 100 * mean(x, na.rm = TRUE)))
    risk <- share(b$tmax >= 32 | b$tmin <= -15 | b$precip >= 10 | b$wind >= 15)
    tour <- share(b$tmean >= 15 & b$tmean <= 27 & b$precip < 1 & b$wind < 10)
    cons <- share(b$tmin > 0 & b$precip < 5 & b$wind < 12)
    wind <- as.numeric(tapply(b$wind, b$month, mean, na.rm = TRUE))
    wcube <- as.numeric(tapply(b$wind^3, b$month, mean, na.rm = TRUE))
    top <- function(x, dec = TRUE) MONTHS_RU[head(order(x, decreasing = dec), 3)]
    c(list(id = id, name = loc_info(req, id)$name), list(risk = risk, tourism = tour, construction = cons, wind = wind, wind_power_index = wcube),
      list(riskiest = top(risk), best_tourism = top(tour), best_construction = top(cons),
           wind_potential = mean(wcube, na.rm = TRUE)))
  })
  list(months = MONTHS_RU, base = paste(BASE, collapse = "–"),
       definitions = list(
         risk = "доля суток с жарой ≥32 °C, морозом ≤−15 °C, осадками ≥10 мм или ветром ≥15 м/с",
         tourism = "доля комфортных суток: 15–27 °C, без осадков (<1 мм), ветер <10 м/с",
         construction = "доля суток, пригодных для работ: Tmin>0 °C, осадки <5 мм, ветер <12 м/с",
         wind = "индекс ветрового потенциала — среднее v³ по суточным максимумам скорости ветра на 10 м (оценка сверху, не мощность)"),
       locations = rows)
}

# ---- Качество данных ---------------------------------------------------------
m_quality <- function(req) {
  rows <- lapply(all_ids(req), function(id) {
    q <- attr(get_series(req, id), "quality")
    pct <- function(f) round(100 * sapply(q$vars, function(v) v[[f]]) / q$rows, 3)
    list(id = id, name = loc_info(req, id)$name, rows = q$rows, from = q$from, to = q$to,
         missing_pct = as.list(pct("missing")), outliers = as.list(sapply(q$vars, function(v) v$outliers)),
         filled = as.list(sapply(q$vars, function(v) v$filled)), left_pct = as.list(pct("left")))
  })
  list(rules = list(limits = LIMITS, max_gap_days = MAX_GAP, no_interpolation = NO_INTERP), locations = rows)
}
