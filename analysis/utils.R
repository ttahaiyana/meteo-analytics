# Общие функции: загрузка и предобработка рядов, статистика трендов.

VARS <- c(tmax = "temperature_2m_max", tmin = "temperature_2m_min", tmean = "temperature_2m_mean",
          precip = "precipitation_sum", wind = "wind_speed_10m_max",
          hum = "relative_humidity_2m_mean", pres = "pressure_msl_mean", cloud = "cloud_cover_mean")

# Физически допустимые диапазоны (пороговые климатические фильтры): °C, мм, м/с, %, гПа.
LIMITS <- list(tmax = c(-90, 60), tmin = c(-90, 60), tmean = c(-90, 60), precip = c(0, 2000),
               wind = c(0, 120), hum = c(0, 100), pres = c(850, 1090), cloud = c(0, 100))
NO_INTERP <- "precip"   # осадки не интерполируем: пропуск нельзя заменять средним
MAX_GAP <- 3            # максимальная длина интерполируемого пропуска, сутки
BASE <- c(1991, 2020)   # базовый климатический период для норм

MONTHS_RU <- c("Янв", "Фев", "Мар", "Апр", "Май", "Июн", "Июл", "Авг", "Сен", "Окт", "Ноя", "Дек")
SEASONS <- c(DJF = "Зима (дек–фев)", MAM = "Весна (мар–май)", JJA = "Лето (июн–авг)", SON = "Осень (сен–ноя)")

# Линейная интерполяция пропусков длиной не более maxgap, окружённых данными.
fill_short <- function(x, maxgap = MAX_GAP) {
  na <- is.na(x)
  if (!any(na) || all(na)) return(list(x = x, filled = 0L))
  r <- rle(na)
  ends <- cumsum(r$lengths)
  starts <- ends - r$lengths + 1
  filled <- 0L
  for (i in which(r$values & r$lengths <= maxgap)) {
    s <- starts[i]; e <- ends[i]
    if (s > 1 && e < length(x)) {
      x[s:e] <- approx(c(s - 1, e + 1), c(x[s - 1], x[e + 1]), xout = s:e)$y
      filled <- filled + r$lengths[i]
    }
  }
  list(x = x, filled = filled)
}

# Загрузка ряда точки + предобработка. В attr "quality" — сведения о качестве.
load_series <- function(dir, id) {
  raw <- read.csv(file.path(dir, paste0(id, ".csv")), stringsAsFactors = FALSE)
  df <- data.frame(date = as.Date(raw$date))
  q <- list(rows = nrow(df), from = as.character(min(df$date)), to = as.character(max(df$date)), vars = list())
  for (v in names(VARS)) {
    x <- as.numeric(raw[[VARS[[v]]]])
    missing <- sum(is.na(x))
    lim <- LIMITS[[v]]
    bad <- !is.na(x) & (x < lim[1] | x > lim[2])
    x[bad] <- NA
    filled <- 0L
    if (!(v %in% NO_INTERP)) {
      f <- fill_short(x)
      x <- f$x; filled <- f$filled
    }
    df[[v]] <- x
    q$vars[[v]] <- list(missing = missing, outliers = sum(bad), filled = filled, left = sum(is.na(x)))
  }
  df$year <- as.integer(format(df$date, "%Y"))
  df$month <- as.integer(format(df$date, "%m"))
  # сезонный год: декабрь относится к зиме следующего года
  df$syear <- df$year + (df$month == 12)
  df$season <- c("DJF", "DJF", "MAM", "MAM", "MAM", "JJA", "JJA", "JJA", "SON", "SON", "SON", "DJF")[df$month]
  attr(df, "quality") <- q
  df
}

in_base <- function(df) df$year >= BASE[1] & df$year <= BASE[2]

# Агрегат по группам; группа с долей пропусков > 1 - min_frac даёт NA.
agg_by <- function(x, g, fun, min_frac = 0.9) {
  res <- tapply(x, g, function(v) if (mean(!is.na(v)) < min_frac) NA_real_ else fun(v, na.rm = TRUE))
  data.frame(key = as.integer(names(res)), value = as.numeric(res))
}

VAR_FUN <- list(tmean = mean, tmax = mean, tmin = mean, precip = sum, wind = mean)
VAR_UNIT <- c(tmean = "°C", tmax = "°C", tmin = "°C", precip = "мм", wind = "м/с")

# Тест Манна–Кендалла с поправкой на совпадения.
mk_test <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 8) return(list(tau = NA_real_, z = NA_real_, p = NA_real_))
  s <- 0
  for (i in 1:(n - 1)) s <- s + sum(sign(x[(i + 1):n] - x[i]))
  tt <- table(x); tt <- tt[tt > 1]
  v <- (n * (n - 1) * (2 * n + 5) - sum(tt * (tt - 1) * (2 * tt + 5))) / 18
  z <- if (s > 0) (s - 1) / sqrt(v) else if (s < 0) (s + 1) / sqrt(v) else 0
  list(tau = s / (n * (n - 1) / 2), z = z, p = 2 * (1 - pnorm(abs(z))))
}

# Наклон Тейла–Сена с 95% доверительным интервалом (Hirsch и др.).
sen_slope <- function(t, x) {
  ok <- !is.na(x); t <- t[ok]; x <- x[ok]
  n <- length(x)
  if (n < 8) return(list(slope = NA_real_, lo = NA_real_, hi = NA_real_, intercept = NA_real_))
  idx <- combn(n, 2)
  sl <- (x[idx[2, ]] - x[idx[1, ]]) / (t[idx[2, ]] - t[idx[1, ]])
  sl <- sort(sl[is.finite(sl)])
  N <- length(sl)
  tt <- table(x); tt <- tt[tt > 1]
  v <- (n * (n - 1) * (2 * n + 5) - sum(tt * (tt - 1) * (2 * tt + 5))) / 18
  C <- qnorm(0.975) * sqrt(v)
  lo <- sl[max(1, floor((N - C) / 2))]
  hi <- sl[min(N, ceiling((N + C) / 2) + 1)]
  b <- median(sl)
  list(slope = b, lo = lo, hi = hi, intercept = median(x - b * t))
}

# Полная сводка тренда ряда x по годам t. Скорости — в единицах за десятилетие.
trend_stats <- function(t, x) {
  mk <- mk_test(x)
  sen <- sen_slope(t, x)
  ok <- !is.na(x)
  ols <- list(slope = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_, r2 = NA_real_)
  if (sum(ok) >= 8) {
    m <- lm(x[ok] ~ t[ok])
    cf <- summary(m)$coefficients
    ci <- confint(m)[2, ]
    ols <- list(slope = unname(cf[2, 1]) * 10, lo = unname(ci[1]) * 10, hi = unname(ci[2]) * 10,
                p = unname(cf[2, 4]), r2 = summary(m)$r.squared)
  }
  list(n = sum(ok), mk_tau = mk$tau, mk_z = mk$z, mk_p = mk$p,
       sen = sen$slope * 10, sen_lo = sen$lo * 10, sen_hi = sen$hi * 10,
       sen_intercept = sen$intercept,
       ols = ols$slope, ols_lo = ols$lo, ols_hi = ols$hi, ols_p = ols$p, r2 = ols$r2,
       significant = !is.na(mk$p) && mk$p < 0.05,
       direction = if (is.na(mk$p) || mk$p >= 0.05) "нет значимого тренда" else if (mk$z > 0) "рост" else "снижение")
}

# Максимальная длина серии TRUE.
max_run <- function(flag) {
  flag[is.na(flag)] <- FALSE
  r <- rle(flag)
  if (!any(r$values)) 0L else max(r$lengths[r$values])
}
