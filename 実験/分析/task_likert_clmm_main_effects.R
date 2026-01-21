#!/usr/bin/env Rscript

lib_dir <- file.path(getwd(), ".r_libs")
if (dir.exists(lib_dir)) {
  .libPaths(c(lib_dir, .libPaths()))
}

if (!requireNamespace("data.table", quietly = TRUE)) {
  stop("data.table が見つかりません。先にパッケージを導入してください。")
}
if (!requireNamespace("ordinal", quietly = TRUE)) {
  stop("ordinal が見つかりません。先にパッケージを導入してください。")
}

library(data.table)
library(ordinal)

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

message("読み込んだCSVファイル:")
for (file_path in files) {
  message("- ", basename(file_path))
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
  dt[, clarity := as.integer(clarity)]
  dt[, confidence := as.integer(confidence)]
  dt
}

raw_dt <- rbindlist(lapply(files, read_task), fill = TRUE)
raw_dt <- raw_dt[method %in% c("hand-grip", "wrist-worn")]

if (nrow(raw_dt) == 0) {
  stop("解析対象データが空です。")
}

direction_levels <- c(0, 45, 90, 135, 180, 225, 270, 315)
raw_dt[, direction := factor(trueDirection, levels = direction_levels)]
raw_dt[, method := factor(method, levels = c("hand-grip", "wrist-worn"))]
raw_dt[, dutyCycle := factor(dutyCycle, levels = c(70, 100))]
raw_dt[, participantId := factor(participantId)]

run_clmm_tests <- function(dt, outcome_name) {
  dt <- dt[!is.na(get(outcome_name))]
  if (nrow(dt) == 0) {
    stop(outcome_name, " の有効データがありません。")
  }
  dt[, outcome := ordered(get(outcome_name), levels = 1:7)]

  full_model <- clmm(
    outcome ~ method + direction + dutyCycle + (1 | participantId),
    data = dt,
    Hess = TRUE
  )

  tests <- drop1(full_model, test = "Chisq")
  test_dt <- as.data.table(tests, keep.rownames = "term")
  test_dt <- test_dt[term %in% c("method", "direction", "dutyCycle")]

  df_col <- intersect(c("Df", "df", "npar"), names(test_dt))
  chi_col <- intersect(c("Chisq", "LR.stat", "LRT", "Deviance"), names(test_dt))
  p_col <- intersect(c("Pr(>Chisq)", "Pr(>Chi)", "Pr(Chi)"), names(test_dt))
  if (length(df_col) == 0 || length(chi_col) == 0 || length(p_col) == 0) {
    stop("drop1()の列名が想定と異なります: ", paste(names(test_dt), collapse = ", "))
  }
  setnames(test_dt, c("term", df_col[1], chi_col[1], p_col[1]),
           c("effect", "df", "chi_sq", "p_value"))
  test_dt[, outcome := outcome_name]
  test_dt[, effect := factor(effect, levels = c("method", "direction", "dutyCycle"))]
  test_dt[order(effect)]
}

clarity_dt <- run_clmm_tests(raw_dt, "clarity")
confidence_dt <- run_clmm_tests(raw_dt, "confidence")

results <- rbindlist(list(clarity_dt, confidence_dt), fill = TRUE)
results <- results[order(outcome, effect)]

output_path <- file.path(output_dir, "task_likert_clmm_main_effects.csv")
fwrite(results, output_path)

print(results)
message("出力先: ", output_path)
