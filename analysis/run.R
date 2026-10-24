# Диспетчер: Rscript run.R <метод>; запрос — JSON в stdin, ответ — JSON в stdout.
args <- commandArgs(trailingOnly = TRUE)
for (lib in strsplit(Sys.getenv("R_LIBS_USER"), ":")[[1]]) if (nzchar(lib) && dir.exists(lib)) .libPaths(c(lib, .libPaths()))
if (dir.exists(path.expand("~/R/lib"))) .libPaths(c(path.expand("~/R/lib"), .libPaths()))

script_dir <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
suppressPackageStartupMessages(library(jsonlite))
for (f in c("utils.R", "methods.R")) source(file.path(script_dir, f))

if (length(args) != 1) stop("ожидается один аргумент: имя метода")
req <- fromJSON(paste(readLines(file("stdin"), warn = FALSE), collapse = "\n"), simplifyVector = TRUE)
handlers <- list(seasonality = m_seasonality, compare = m_compare, trends = m_trends,
                 extremes = m_extremes, correlations = m_correlations, insights = m_insights,
                 quality = m_quality)
h <- handlers[[args[1]]]
if (is.null(h)) stop("неизвестный метод: ", args[1])
res <- h(req)
cat(toJSON(res, auto_unbox = TRUE, na = "null", digits = 4, null = "null"))
