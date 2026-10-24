# Проверка статистических функций на синтетических рядах с известным ответом.
# Запуск: Rscript analysis/tests/test_stats.R
.libPaths(c(path.expand("~/R/lib"), .libPaths()))
dir <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
source(file.path(dir, "..", "utils.R"))

ok <- function(cond, msg) { if (!isTRUE(cond)) stop("FAIL: ", msg, call. = FALSE); cat("ok  ", msg, "\n") }

# 1. линейный ряд с известным наклоном 0.03/год и малым шумом
set.seed(1)
t <- 1950:2024
x <- 5 + 0.03 * (t - 1950) + rnorm(length(t), 0, 0.2)
s <- trend_stats(t, x)
ok(abs(s$sen - 0.3) < 0.05, "наклон Тейла–Сена ≈ 0.3 за десятилетие")
ok(abs(s$ols - 0.3) < 0.05, "наклон OLS ≈ 0.3 за десятилетие")
ok(s$sen_lo < 0.3 && s$sen_hi > 0.3, "95% ДИ содержит истинный наклон")
ok(s$significant && s$direction == "рост", "тренд значим и направлен вверх")

# 2. Манн–Кендалл сверяем с независимой реализацией в базовом R (cor.test по Кендаллу)
kt <- cor.test(t, x, method = "kendall", exact = FALSE)
mk <- mk_test(x)
ok(abs(mk$tau - unname(kt$estimate)) < 1e-9, "τ Кендалла совпадает с cor.test")
ok(abs(mk$p - kt$p.value) < 0.01, "p-value согласуется с cor.test")

# 3. ряд без тренда
# доля ложных срабатываний должна быть близка к уровню значимости 5%
fp <- mean(replicate(400, mk_test(rnorm(75))$p) < 0.05)
ok(fp > 0.02 && fp < 0.09, sprintf("белый шум: доля ложных срабатываний %.3f ≈ 0.05", fp))

# 4. короткий ряд не даёт ложных выводов
ok(is.na(mk_test(1:5)$p), "n<8: тест не выполняется")

# 5. интерполяция: короткие пропуски заполняются, длинные — нет
v <- c(1, 2, NA, NA, 5, 6, NA, NA, NA, NA, NA, 12)
f <- fill_short(v, 3)
ok(all(f$x[3:4] == c(3, 4)) && f$filled == 2, "пропуск из 2 суток интерполирован линейно")
ok(all(is.na(f$x[7:11])), "пропуск из 5 суток оставлен")

# 6. длина серии
ok(max_run(c(TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, NA)) == 3, "максимальная серия подряд")
cat("Все проверки пройдены\n")
