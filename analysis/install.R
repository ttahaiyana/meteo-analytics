# Установка R-зависимостей: Rscript analysis/install.R
lib <- Sys.getenv("R_LIBS_USER", path.expand("~/R/lib"))
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
for (p in c("jsonlite")) if (!requireNamespace(p, quietly = TRUE, lib.loc = c(lib, .libPaths())))
  install.packages(p, lib = lib, repos = "https://cloud.r-project.org")
cat("R-зависимости установлены (используются только jsonlite и базовый R; тесты Манна–Кендалла и Тейла–Сена реализованы в utils.R)\n")
