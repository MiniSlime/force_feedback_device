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
  dt
}

raw_dt <- rbindlist(lapply(files, read_task), fill = TRUE)
raw_dt <- raw_dt[method %in% c("hand-grip", "wrist-worn")]
raw_dt <- raw_dt[!is.na(trueDirection)]

directions <- as.integer(c(0, 45, 90, 135, 180, 225, 270, 315))
direction_labels <- paste0(directions, "°")
response_labels <- c(direction_labels, "skip")

normalize_angle <- function(angle) {
  angle %% 360
}

closest_direction <- function(angle, directions) {
  if (is.na(angle) || angle < 0) {
    return(NA_integer_)
  }
  angle <- normalize_angle(angle)
  diffs <- abs(((angle - directions + 180) %% 360) - 180)
  as.integer(directions[which.min(diffs)])
}

raw_dt[, responseDirection := vapply(responseAngle, closest_direction, integer(1), directions = directions)]
raw_dt[, responseCategory := ifelse(is.na(responseDirection), "skip", paste0(responseDirection, "°"))]

make_confusion_plot <- function(mat, method_name, duty_cycle, output_path) {
  max_count <- max(mat, na.rm = TRUE)
  if (!is.finite(max_count) || max_count <= 0) {
    max_count <- 1
  }
  colors <- colorRampPalette(c("#FFFFFF", "#2C7FB8"))(100)
  breaks <- seq(0, max_count, length.out = 101)

  png(output_path, width = 900, height = 900, res = 150)
  par(mar = c(5, 6, 3, 2))
  image(
    x = 1:ncol(mat),
    y = 1:nrow(mat),
    z = t(mat[nrow(mat):1, ]),
    col = colors,
    breaks = breaks,
    axes = FALSE,
    xlab = "回答方向",
    ylab = "正解方向"
  )
  axis(1, at = 1:length(response_labels), labels = response_labels)
  axis(2, at = 1:length(direction_labels), labels = rev(direction_labels), las = 1)
  box()

  for (i in seq_len(nrow(mat))) {
    for (j in seq_len(ncol(mat))) {
      value <- mat[i, j]
      if (is.na(value)) {
        next
      }
      text(j, nrow(mat) - i + 1, labels = value, cex = 0.9, col = "black")
    }
  }
  dev.off()
}

output_files <- character(0)
for (method_name in unique(raw_dt$method)) {
  for (duty_cycle in unique(raw_dt$dutyCycle)) {
    sub_dt <- raw_dt[method == method_name & dutyCycle == duty_cycle]
    if (nrow(sub_dt) == 0) {
      next
    }
    mat <- matrix(0, nrow = length(directions), ncol = length(response_labels))
    rownames(mat) <- direction_labels
    colnames(mat) <- response_labels
    for (i in seq_len(nrow(sub_dt))) {
      true_dir <- sub_dt$trueDirection[i]
      resp_cat <- sub_dt$responseCategory[i]
      row_idx <- match(true_dir, directions)
      col_idx <- match(resp_cat, response_labels)
      if (is.na(row_idx) || is.na(col_idx)) {
        next
      }
      mat[row_idx, col_idx] <- mat[row_idx, col_idx] + 1
    }
    output_path <- file.path(output_dir, sprintf("task_confusion_matrix_%s_%s.png", method_name, duty_cycle))
    make_confusion_plot(mat, method_name, duty_cycle, output_path)
    output_files <- c(output_files, output_path)
  }
}

message("出力先: ", paste(output_files, collapse = "\n"))
