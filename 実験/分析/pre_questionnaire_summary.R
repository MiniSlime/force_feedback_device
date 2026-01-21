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
base_dir <- file.path(project_root, "実験", "実験結果", "実験前アンケート")
output_dir <- file.path(script_dir, "outputs")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

files <- list.files(base_dir, pattern = "\\.csv$", full.names = TRUE)
if (length(files) == 0) {
  candidate_dirs <- list.dirs(project_root, recursive = TRUE, full.names = TRUE)
  pre_dirs <- candidate_dirs[basename(candidate_dirs) == "実験前アンケート"]
  if (length(pre_dirs) > 0) {
    base_dir <- pre_dirs[1]
    files <- list.files(base_dir, pattern = "\\.csv$", full.names = TRUE)
  }
}
if (length(files) == 0) {
  stop("実験前アンケートのCSVが見つかりません。")
}

message("読み込んだCSV:\n", paste(files, collapse = "\n"))

read_pre <- function(path) {
  dt <- fread(path, encoding = "UTF-8")
  required_cols <- c("participantId", "gender", "handedness")
  if (!all(required_cols %in% names(dt))) {
    stop("CSVの列構成が想定と異なります: ", path)
  }
  dt[, participantId := as.character(participantId)]
  dt[, gender := trimws(as.character(gender))]
  dt[, handedness := trimws(as.character(handedness))]
  dt
}

raw_dt <- rbindlist(lapply(files, read_pre), fill = TRUE)

summarize_counts <- function(values, levels, label, output_path) {
  dt <- data.table(value = values)
  dt[is.na(value) | value == "", value := "未回答"]
  dt[, value := factor(value, levels = levels)]
  summary_dt <- dt[, .(count = .N), by = value][order(value)]
  summary_dt[, ratio := round(count / sum(count) * 100, 1)]
  summary_dt[, category := as.character(value)]
  summary_dt[, value := NULL]

  message("\n", label, "集計:")
  print(summary_dt)
  fwrite(summary_dt, output_path)
  output_path
}

gender_levels <- c("男", "女", "無回答", "未回答")
handedness_levels <- c("右利き", "左利き", "両利き", "わからない", "未回答")

gender_output <- summarize_counts(
  raw_dt$gender,
  gender_levels,
  "性別",
  file.path(output_dir, "pre_questionnaire_gender_summary.csv")
)

handedness_output <- summarize_counts(
  raw_dt$handedness,
  handedness_levels,
  "利き手",
  file.path(output_dir, "pre_questionnaire_handedness_summary.csv")
)

message("\n出力先:\n", paste(c(gender_output, handedness_output), collapse = "\n"))
