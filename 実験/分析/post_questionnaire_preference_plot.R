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
base_dir <- file.path(project_root, "実験", "実験結果", "実験後アンケート")
output_dir <- file.path(script_dir, "outputs")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

files <- list.files(base_dir, pattern = "\\.csv$", full.names = TRUE)
if (length(files) == 0) {
  candidate_dirs <- list.dirs(project_root, recursive = TRUE, full.names = TRUE)
  post_dirs <- candidate_dirs[basename(candidate_dirs) == "実験後アンケート"]
  if (length(post_dirs) > 0) {
    base_dir <- post_dirs[1]
    files <- list.files(base_dir, pattern = "\\.csv$", full.names = TRUE)
  }
}
if (length(files) == 0) {
  stop("実験後アンケートのCSVが見つかりません。")
}

message("読み込んだCSV:\n", paste(files, collapse = "\n"))

read_post <- function(path) {
  dt <- fread(path, encoding = "UTF-8")
  required_cols <- c("participantId", "preferredMethod")
  if (!all(required_cols %in% names(dt))) {
    stop("CSVの列構成が想定と異なります: ", path)
  }
  dt[, participantId := as.character(participantId)]
  dt[, preferredMethod := trimws(as.character(preferredMethod))]
  dt
}

raw_dt <- rbindlist(lapply(files, read_post), fill = TRUE)
raw_dt[is.na(preferredMethod) | preferredMethod == "", preferredMethod := "未回答"]

label_map <- c(
  "wrist-worn" = "wrist-worn",
  "hand-grip" = "hand-grip",
  "both" = "どちらも同じ",
  "unknown" = "わからない",
  "未回答" = "未回答"
)

raw_dt[, preferredLabel := label_map[preferredMethod]]
raw_dt[is.na(preferredLabel), preferredLabel := preferredMethod]

levels_order <- c("wrist-worn", "hand-grip", "どちらも同じ", "わからない", "未回答")
raw_dt[, preferredLabel := factor(preferredLabel, levels = levels_order)]

summary_dt <- raw_dt[, .(count = .N), by = preferredLabel][order(preferredLabel)]
summary_dt[, ratio := round(count / sum(count) * 100, 1)]

output_csv <- file.path(output_dir, "post_questionnaire_preference_summary.csv")
fwrite(summary_dt, output_csv)

p <- ggplot(summary_dt, aes(x = preferredLabel, y = count, fill = preferredLabel)) +
  geom_col(width = 0.6, color = "grey30") +
  geom_text(aes(label = paste0(count, " (", ratio, "%)")), vjust = -0.4, size = 3.5) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +
  labs(
    x = "選択条件",
    y = "人数",
    title = "条件に対する好み"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    legend.position = "none",
    axis.text.x = element_text(angle = 20, vjust = 1, hjust = 1),
    plot.title = element_text(hjust = 0.5)
  )

output_plot <- file.path(output_dir, "post_questionnaire_preference_plot.png")
ggsave(output_plot, plot = p, width = 7.5, height = 4.2, dpi = 150)

message("\n出力先:\n", paste(c(output_csv, output_plot), collapse = "\n"))
