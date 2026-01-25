#!/usr/bin/env Rscript

lib_dir <- file.path(getwd(), ".r_libs")
if (dir.exists(lib_dir)) {
  .libPaths(c(lib_dir, .libPaths()))
}

if (!requireNamespace("data.table", quietly = TRUE)) {
  stop("data.table が見つかりません。先にパッケージを導入してください。")
}
if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("ggplot2 が見つかりません。先にパッケージを導入してください。")
}

library(data.table)
library(ggplot2)

get_script_path <- function() {
  source_path <- sys.frame(1)$ofile
  if (!is.null(source_path)) {
    return(normalizePath(source_path))
  }
  cmd <- commandArgs(trailingOnly = FALSE)
  file_arg <- "--file="
  match <- grep(file_arg, cmd)
  if (length(match) > 0) {
    return(normalizePath(sub(file_arg, "", cmd[match][1])))
  }
  normalizePath(getwd())
}

script_path <- get_script_path()
script_dir <- dirname(script_path)
project_root <- normalizePath(file.path(script_dir, "..", ".."))
base_dir <- file.path(project_root, "実験", "実験結果", "NASA-TLX")
output_dir <- file.path(script_dir, "outputs")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

files <- list.files(base_dir, pattern = "\\.csv$", full.names = TRUE)
if (length(files) == 0) {
  candidate_dirs <- list.dirs(project_root, recursive = TRUE, full.names = TRUE)
  nasa_dirs <- candidate_dirs[basename(candidate_dirs) == "NASA-TLX"]
  if (length(nasa_dirs) > 0) {
    base_dir <- nasa_dirs[1]
    files <- list.files(base_dir, pattern = "\\.csv$", full.names = TRUE)
  }
}
if (length(files) == 0) {
  stop("NASA-TLX のCSVが見つかりません。")
}

read_nasa <- function(path) {
  dt <- fread(path, encoding = "UTF-8")
  if (ncol(dt) >= 5) {
    setnames(dt, 1:5, c("item", "rating", "count", "weight", "score"))
  }
  dt[, item := ifelse(is.na(item) | item == "", "総合", item)]
  dt[, participantId := sub("^(P\\d+)_.*$", "\\1", basename(path))]
  dt[, method := sub("^P\\d+_(.*)\\.csv$", "\\1", basename(path))]
  dt[, method := gsub("_", "-", method)]
  dt[, rating := as.numeric(rating)]
  dt[, score := as.numeric(score)]
  dt[, value := ifelse(item == "総合", score, rating)]
  dt[!is.na(value)]
}

raw_dt <- rbindlist(lapply(files, read_nasa), fill = TRUE)
raw_dt <- raw_dt[method %in% c("hand-grip", "wrist-worn")]
raw_dt[, method := factor(method, levels = c("hand-grip", "wrist-worn"))]

item_levels <- c(
  "知的・知覚的要求",
  "身体的要求",
  "タイムプレッシャー",
  "作業成績",
  "努力",
  "フラストレーション",
  "総合"
)
raw_dt[, item := factor(item, levels = item_levels)]
raw_dt <- raw_dt[!is.na(item)]

sig_item <- "総合"
sig_label <- "*"
sig_data <- raw_dt[item == sig_item]
sig_label_y <- if (nrow(sig_data) > 0) {
  max(sig_data$value, na.rm = TRUE) + 5
} else {
  NA_real_
}
bracket_height <- 1
dodge_width <- 0.75
method_count <- 2
item_index <- match(sig_item, item_levels)
offset <- (dodge_width / method_count) / 2
sig_x_left <- item_index - offset
sig_x_right <- item_index + offset
sig_star_y <- sig_label_y + 0.7
sig_bracket <- data.table(
  x = c(sig_x_left, sig_x_left, sig_x_right),
  xend = c(sig_x_right, sig_x_left, sig_x_right),
  y = c(sig_label_y, sig_label_y, sig_label_y),
  yend = c(sig_label_y, sig_label_y - bracket_height, sig_label_y - bracket_height)
)
sig_star <- data.table(
  x = item_index,
  y = sig_star_y,
  label = sig_label
)

dodge <- position_dodge(width = 0.75)
p <- ggplot(raw_dt, aes(x = item, y = value, fill = method)) +
  stat_boxplot(geom = "errorbar", width = 0.2, position = dodge) +
  geom_boxplot(outlier.size = 1.5, width = 0.6, position = dodge) +
  scale_x_discrete(
    labels = function(x) {
      vapply(strwrap(x, width = 6), paste, collapse = "\n", FUN.VALUE = character(1))
    }
  ) +
  labs(
    x = NULL,
    y = "評定点",
    fill = "条件"
  ) +
  scale_y_continuous(expand = expansion(mult = c(0.05, 0.15))) +
  theme_minimal(base_size = 12) +
  theme(
    axis.text.x = element_text(angle = 25, vjust = 1, hjust = 1),
    axis.title.x = element_text(margin = margin(t = 8)),
    plot.margin = margin(8, 12, 12, 8),
    legend.position = "right"
  ) +
  coord_cartesian(clip = "off")

if (is.finite(sig_label_y)) {
  p <- p +
    geom_segment(
      data = sig_bracket,
      aes(x = x, xend = xend, y = y, yend = yend),
      inherit.aes = FALSE,
      lineend = "butt"
    ) +
    geom_text(
      data = sig_star,
      aes(x = x, y = y, label = label),
      inherit.aes = FALSE,
      vjust = 0
    )
}

output_path <- file.path(output_dir, "nasa_tlx_boxplot.png")
ggsave(output_path, plot = p, width = 9.2, height = 4.6, dpi = 150)

message("出力先: ", output_path)
