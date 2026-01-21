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

library(data.table)
library(lme4)

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
  dt[, isCorrect := as.numeric(isCorrect)]
  dt[isCorrect < 0, isCorrect := 0]
  dt
}

raw_dt <- rbindlist(lapply(files, read_task), fill = TRUE)
raw_dt <- raw_dt[method %in% c("hand-grip", "wrist-worn")]
raw_dt <- raw_dt[!is.na(isCorrect)]

if (nrow(raw_dt) == 0) {
  stop("解析対象データが空です。")
}

direction_levels <- c(0, 45, 90, 135, 180, 225, 270, 315)
raw_dt[, direction := factor(trueDirection, levels = direction_levels)]
raw_dt[, method := factor(method, levels = c("hand-grip", "wrist-worn"))]
raw_dt[, dutyCycle := factor(dutyCycle, levels = c(70, 100))]
raw_dt[, participantId := factor(participantId)]

main_model <- glmer(
  isCorrect ~ direction + method + dutyCycle + (1 | participantId),
  data = raw_dt,
  family = binomial,
  control = glmerControl(optimizer = "bobyqa")
)

no_direction_model <- glmer(
  isCorrect ~ method + dutyCycle + (1 | participantId),
  data = raw_dt,
  family = binomial,
  control = glmerControl(optimizer = "bobyqa")
)

direction_lrt <- anova(no_direction_model, main_model, test = "Chisq")
direction_result <- data.table(
  test = "direction_main_effect",
  df = direction_lrt[2, "Df"],
  chi_sq = direction_lrt[2, "Chisq"],
  p_value = direction_lrt[2, "Pr(>Chisq)"]
)

interaction_model <- glmer(
  isCorrect ~ direction * method + direction * dutyCycle + (1 | participantId),
  data = raw_dt,
  family = binomial,
  control = glmerControl(optimizer = "bobyqa")
)

interaction_tests <- drop1(interaction_model, test = "Chisq")
interaction_dt <- as.data.table(interaction_tests, keep.rownames = "term")
interaction_dt <- interaction_dt[term %in% c("direction:method", "direction:dutyCycle")]
df_col <- intersect(c("Df", "df", "npar"), names(interaction_dt))
chi_col <- intersect(c("Chisq", "LRT", "Deviance"), names(interaction_dt))
p_col <- intersect(c("Pr(>Chisq)", "Pr(>Chi)", "Pr(Chi)"), names(interaction_dt))
if (length(df_col) == 0 || length(chi_col) == 0 || length(p_col) == 0) {
  stop("drop1()の列名が想定と異なります: ", paste(names(interaction_dt), collapse = ", "))
}
setnames(interaction_dt, c("term", df_col[1], chi_col[1], p_col[1]),
         c("test", "df", "chi_sq", "p_value"))

results <- rbindlist(list(direction_result, interaction_dt), fill = TRUE)
results <- results[order(test)]

output_path <- file.path(output_dir, "task_accuracy_glmm_tests.csv")
fwrite(results, output_path)

print(results)
message("出力先: ", output_path)
