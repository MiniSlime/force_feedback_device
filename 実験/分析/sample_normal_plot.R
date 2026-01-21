#!/usr/bin/env Rscript

lib_dir <- file.path(getwd(), ".r_libs")
if (dir.exists(lib_dir)) {
  .libPaths(c(lib_dir, .libPaths()))
}

if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("ggplot2 が見つかりません。先にパッケージを導入してください。")
}

library(ggplot2)

set.seed(123)
samples <- rnorm(1000, mean = 0, sd = 1)
df <- data.frame(value = samples)

p <- ggplot(df, aes(x = value)) +
  geom_histogram(aes(y = after_stat(density)), bins = 30, fill = "#4C78A8", alpha = 0.7) +
  stat_function(fun = dnorm, args = list(mean = 0, sd = 1), color = "#F58518", linewidth = 1) +
  labs(
    title = "正規分布サンプルのヒストグラム",
    x = "値",
    y = "密度"
  ) +
  theme_minimal()

output_path <- file.path(getwd(), "実験", "分析", "normal_distribution_plot.png")
ggsave(output_path, plot = p, width = 8, height = 5, dpi = 150)

message("出力先: ", output_path)
