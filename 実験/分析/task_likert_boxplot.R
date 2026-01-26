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
base_dir <- file.path(project_root, "実験", "実験結果", "タスク記録")
output_dir <- file.path(script_dir, "outputs")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

files <- list.files(base_dir, pattern = "\\.csv$", full.names = TRUE)
if (length(files) == 0) {
  candidate_dirs <- list.dirs(project_root, recursive = TRUE, full.names = TRUE)
  task_dirs <- candidate_dirs[basename(candidate_dirs) == "タスク記録"]
  if (length(task_dirs) > 0) {
    base_dir <- task_dirs[1]
    files <- list.files(base_dir, pattern = "\\.csv$", full.names = TRUE)
  }
}
if (length(files) == 0) {
  stop("タスク記録のCSVが見つかりません。")
}

read_task <- function(path) {
  dt <- fread(path, encoding = "UTF-8")
  required_cols <- c(
    "participantId",
    "method",
    "trialIndex",
    "trueDirection",
    "dutyCycle",
    "responseAngle",
    "responseTimeMs",
    "error",
    "isCorrect",
    "clarity",
    "confidence"
  )
  if (!all(required_cols %in% names(dt))) {
    stop("CSVの列構成が想定と異なります: ", path)
  }
  dt[, method := gsub("_", "-", method)]
  dt[, dutyCycle := as.integer(dutyCycle)]
  dt[, clarity := as.numeric(clarity)]
  dt[, confidence := as.numeric(confidence)]
  dt
}

raw_dt <- rbindlist(lapply(files, read_task), fill = TRUE)
raw_dt <- raw_dt[method %in% c("hand-grip", "wrist-worn")]

raw_dt[, condition := paste0(method, " × ", dutyCycle)]
raw_dt[, condition := factor(condition, levels = c(
  "hand-grip × 70",
  "hand-grip × 100",
  "wrist-worn × 70",
  "wrist-worn × 100"
))]

long_dt <- melt(
  raw_dt,
  id.vars = c("participantId", "method", "dutyCycle", "condition"),
  measure.vars = c("clarity", "confidence"),
  variable.name = "item",
  value.name = "value"
)
long_dt <- long_dt[!is.na(value)]

item_labels <- c(clarity = "力覚の分かりやすさ", confidence = "回答への確信度")
long_dt[, item := factor(item, levels = names(item_labels), labels = item_labels)]

dodge <- position_dodge(width = 0.7)
jitter <- position_jitterdodge(jitter.width = 0.12, dodge.width = 0.7)
output_paths <- character(0)
for (item_name in levels(long_dt$item)) {
  item_dt <- long_dt[item == item_name]
  if (nrow(item_dt) == 0) {
    next
  }
  p <- ggplot(item_dt, aes(x = condition, y = value, fill = condition)) +
    stat_boxplot(geom = "errorbar", width = 0.2, position = dodge) +
    geom_boxplot(outlier.shape = NA, width = 0.6, position = dodge) +
    geom_point(
      aes(color = condition),
      position = jitter,
      color = "grey30",
      alpha = 0.5,
      size = 1.4,
      show.legend = FALSE
    ) +
    scale_y_continuous(
      limits = c(1, 7),
      breaks = 1:7
    ) +
    labs(
      x = "条件 × デューティ比",
      y = "評定点",
      fill = "条件"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      axis.text.x = element_text(angle = 25, vjust = 1, hjust = 1),
      legend.position = "none"
    )
  file_key <- names(item_labels)[match(item_name, item_labels)]
  output_path <- file.path(output_dir, sprintf("task_likert_boxplot_%s.png", file_key))
  ggsave(output_path, plot = p, width = 6.0, height = 4.2, dpi = 150)
  output_paths <- c(output_paths, output_path)
}

message("出力先: ", paste(output_paths, collapse = "\n"))
