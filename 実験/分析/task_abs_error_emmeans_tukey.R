#!/usr/bin/env Rscript

lib_dir <- file.path(getwd(), ".r_libs")
if (dir.exists(lib_dir)) {
  .libPaths(c(lib_dir, .libPaths()))
}

if (!requireNamespace("data.table", quietly = TRUE)) {
  stop("data.table が見つかりません。先にパッケージを導入してください。")
}
if (!requireNamespace("lme4", quietly = TRUE)) {
  stop("lme4 が見つかりません。先にパッケージを導入してください。")
}
if (!requireNamespace("emmeans", quietly = TRUE)) {
  stop("emmeans が見つかりません。先にパッケージを導入してください。")
}

library(data.table)
library(lme4)
library(emmeans)

emm_options(lmer.df = "asymptotic")

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
  dt[, trueDirection := as.integer(trueDirection)]
  dt[, dutyCycle := as.integer(dutyCycle)]
  dt[, responseAngle := as.numeric(responseAngle)]
  dt[, isCorrect := as.numeric(isCorrect)]
  dt[, absError := NA_real_]
  dt[
    !is.na(responseAngle) & !is.na(trueDirection) & responseAngle >= 0 & isCorrect >= 0,
    absError := abs(((responseAngle - trueDirection + 180) %% 360) - 180)
  ]
  dt
}

raw_dt <- rbindlist(lapply(files, read_task), fill = TRUE)
raw_dt <- raw_dt[method %in% c("hand-grip", "wrist-worn")]
raw_dt <- raw_dt[!is.na(absError)]

if (nrow(raw_dt) == 0) {
  stop("解析対象データが空です。")
}

direction_levels <- c(0, 45, 90, 135, 180, 225, 270, 315)
raw_dt[, direction := factor(trueDirection, levels = direction_levels)]
raw_dt[, method := factor(method, levels = c("hand-grip", "wrist-worn"))]
raw_dt[, dutyCycle := factor(dutyCycle, levels = c(70, 100))]
raw_dt[, participantId := factor(participantId)]

fit <- lmer(
  absError ~ method * dutyCycle + method * direction + dutyCycle * direction + (1 | participantId),
  data = raw_dt,
  REML = FALSE
)

emm_method_by_direction <- emmeans(fit, ~ method | direction)
pair_method_by_direction <- pairs(emm_method_by_direction, adjust = "tukey")
method_by_direction_dt <- as.data.table(summary(pair_method_by_direction))

emm_direction_by_method <- emmeans(fit, ~ direction | method)
pair_direction_by_method <- pairs(emm_direction_by_method, adjust = "tukey")
direction_by_method_dt <- as.data.table(summary(pair_direction_by_method))

output_method_path <- file.path(output_dir, "task_abs_error_tukey_method_by_direction.csv")
output_direction_path <- file.path(output_dir, "task_abs_error_tukey_direction_by_method.csv")
fwrite(method_by_direction_dt, output_method_path)
fwrite(direction_by_method_dt, output_direction_path)

message("出力先: ", output_method_path)
message("出力先: ", output_direction_path)
