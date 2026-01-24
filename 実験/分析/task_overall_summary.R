#!/usr/bin/env Rscript

lib_dir <- file.path(getwd(), ".r_libs")
if (dir.exists(lib_dir)) {
  .libPaths(c(lib_dir, .libPaths()))
}

if (!requireNamespace("data.table", quietly = TRUE)) {
  stop("data.table が見つかりません。先にパッケージを導入してください。")
}

library(data.table)

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
  dt[isCorrect < 0, isCorrect := NA_real_]
  dt
}

raw_dt <- rbindlist(lapply(files, read_task), fill = TRUE)
raw_dt <- raw_dt[method %in% c("hand-grip", "wrist-worn")]

accuracy_values <- raw_dt[!is.na(isCorrect), as.numeric(isCorrect == 1)]
error_values <- raw_dt[!is.na(error), error]

overall_accuracy_mean <- mean(accuracy_values, na.rm = TRUE)
overall_accuracy_sd <- sd(accuracy_values, na.rm = TRUE)
overall_error_mean <- mean(error_values, na.rm = TRUE)
overall_error_sd <- sd(error_values, na.rm = TRUE)

participant_accuracy <- raw_dt[!is.na(isCorrect), .(
  accuracy = mean(isCorrect == 1, na.rm = TRUE)
), by = .(participantId)]
participant_error <- raw_dt[!is.na(error), .(
  meanError = mean(error, na.rm = TRUE)
), by = .(participantId)]

max_accuracy <- participant_accuracy[which.max(accuracy)]
min_accuracy <- participant_accuracy[which.min(accuracy)]
min_error <- participant_error[which.min(meanError)]
max_error <- participant_error[which.max(meanError)]

cat("全条件の平均正答率: ", sprintf("%.4f", overall_accuracy_mean), "\n", sep = "")
cat("全条件の正答率の標準偏差: ", sprintf("%.4f", overall_accuracy_sd), "\n", sep = "")
cat("全条件の平均誤差: ", sprintf("%.4f", overall_error_mean), "°\n", sep = "")
cat("全条件の誤差の標準偏差: ", sprintf("%.4f", overall_error_sd), "\n", sep = "")
cat("\n")
cat("最も正答率が高い参加者: ", max_accuracy$participantId,
    "（正答率: ", sprintf("%.4f", max_accuracy$accuracy), "）\n", sep = "")
cat("最も正答率が低い参加者: ", min_accuracy$participantId,
    "（正答率: ", sprintf("%.4f", min_accuracy$accuracy), "）\n", sep = "")
cat("最も平均誤差が小さい参加者: ", min_error$participantId,
    "（平均誤差: ", sprintf("%.4f", min_error$meanError), "°）\n", sep = "")
cat("最も平均誤差が大きい参加者: ", max_error$participantId,
    "（平均誤差: ", sprintf("%.4f", max_error$meanError), "°）\n", sep = "")
