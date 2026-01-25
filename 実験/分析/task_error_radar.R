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

message("読み込んだCSV:\n", paste(files, collapse = "\n"))

read_task <- function(path) {
  dt <- fread(path, encoding = "UTF-8")
  if (!all(c("participantId", "method", "trialIndex", "trueDirection", "dutyCycle", "responseAngle",
             "responseTimeMs", "error", "isCorrect", "clarity", "confidence") %in% names(dt))) {
    stop("CSVの列構成が想定と異なります: ", path)
  }
  dt[, method := gsub("_", "-", method)]
  dt[, trueDirection := as.integer(trueDirection)]
  dt[, dutyCycle := as.integer(dutyCycle)]
  dt[, responseAngle := as.numeric(responseAngle)]
  dt[, isCorrect := as.numeric(isCorrect)]
  dt[, error := as.numeric(error)]
  dt[responseAngle < 0 | isCorrect < 0, error := NA_real_]
  dt[, signedError := NA_real_]
  dt[
    !is.na(responseAngle) & !is.na(trueDirection) & responseAngle >= 0 & isCorrect >= 0,
    signedError := ((responseAngle - trueDirection + 180) %% 360) - 180
  ]
  dt
}

raw_dt <- rbindlist(lapply(files, read_task), fill = TRUE)
raw_dt <- raw_dt[method %in% c("hand-grip", "wrist-worn")]

participant_dir <- raw_dt[, .(
  participantError = mean(signedError, na.rm = TRUE)
), by = .(participantId, method, dutyCycle, trueDirection)]

participant_dir <- participant_dir[!is.na(participantError)]
participant_dir[, method := factor(method, levels = c("hand-grip", "wrist-worn"))]
participant_dir[, trueDirection := factor(trueDirection, levels = c(0, 45, 90, 135, 180, 225, 270, 315))]

dodge <- position_dodge(width = 0.75)
make_boxplot <- function(dt, method_name, duty_cycle, output_path) {
  p <- ggplot(dt, aes(x = trueDirection, y = participantError, fill = method)) +
    geom_hline(yintercept = 0, color = "grey50", linewidth = 0.6) +
    stat_boxplot(geom = "errorbar", width = 0.2, position = dodge) +
    geom_boxplot(outlier.size = 1.5, width = 0.6, position = dodge) +
    scale_x_discrete(labels = function(x) paste0(x, "°")) +
    labs(
      x = "正解方向",
      y = "平均誤差(°)",
      fill = "条件"
    ) +
    scale_y_continuous(expand = expansion(mult = c(0.08, 0.12))) +
    theme_minimal(base_size = 12) +
    theme(
      axis.text.x = element_text(angle = 25, vjust = 1, hjust = 1),
      axis.title.x = element_text(margin = margin(t = 8)),
      plot.margin = margin(8, 12, 12, 8),
      legend.position = "none"
    )
  ggsave(output_path, plot = p, width = 6.2, height = 4.6, dpi = 150)
}

output_files <- character(0)
for (method_name in levels(participant_dir$method)) {
  for (duty_cycle in sort(unique(participant_dir$dutyCycle))) {
    sub_dt <- participant_dir[method == method_name & dutyCycle == duty_cycle]
    if (nrow(sub_dt) == 0) {
      next
    }
    output_path <- file.path(
      output_dir,
      sprintf("task_error_boxplot_%s_%s.png", method_name, duty_cycle)
    )
    make_boxplot(sub_dt, method_name, duty_cycle, output_path)
    output_files <- c(output_files, output_path)
  }
}

message("出力先: ", paste(output_files, collapse = "\n"))
