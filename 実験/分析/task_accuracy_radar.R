#!/usr/bin/env Rscript

lib_dir <- file.path(getwd(), ".r_libs")
if (dir.exists(lib_dir)) {
  .libPaths(c(lib_dir, .libPaths()))
}

if (!requireNamespace("data.table", quietly = TRUE)) {
  stop("data.table が見つかりません。先にパッケージを導入してください。")
}
if (!requireNamespace("fmsb", quietly = TRUE)) {
  stop("fmsb が見つかりません。先にパッケージを導入してください。")
}

library(data.table)
library(fmsb)

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
  dt[, isCorrect := as.numeric(isCorrect)]
  dt[isCorrect < 0, isCorrect := 0]
  dt
}

raw_dt <- rbindlist(lapply(files, read_task), fill = TRUE)
raw_dt <- raw_dt[method %in% c("hand-grip", "wrist-worn")]

directions <- c(0, 45, 90, 135, 180, 225, 270, 315)
combos <- CJ(method = c("hand-grip", "wrist-worn"), dutyCycle = c(70, 100), trueDirection = directions)

participant_dir <- raw_dt[, .(
  participantRate = mean(isCorrect == 1, na.rm = TRUE)
), by = .(participantId, method, dutyCycle, trueDirection)]

participant_overall <- raw_dt[, .(
  participantRate = mean(isCorrect == 1, na.rm = TRUE)
), by = .(participantId, method, dutyCycle)]

agg <- participant_dir[, .(
  correctRate = mean(participantRate, na.rm = TRUE),
  n = sum(!is.na(participantRate))
), by = .(method, dutyCycle, trueDirection)]

agg <- merge(combos, agg, by = c("method", "dutyCycle", "trueDirection"), all.x = TRUE)
agg[is.na(correctRate), correctRate := 0]
agg[is.na(n), n := 0]

make_radar_plot <- function(dt, method_name, duty_cycle, output_path, overall_mean) {
  direction_order <- c(90, 135, 180, 225, 270, 315, 0, 45)
  direction_labels <- paste0(direction_order, "°")
  dt <- dt[order(match(trueDirection, direction_order))]
  values <- as.numeric(dt$correctRate)
  names(values) <- direction_labels
  avg_rate <- mean(values, na.rm = TRUE)

  radar_df <- rbind(
    rep(1, length(values)),
    rep(0, length(values)),
    values
  )
  colnames(radar_df) <- direction_labels
  radar_df <- as.data.frame(radar_df)

  seg <- 4
  png(output_path, width = 900, height = 900, res = 150)
  par(mar = c(1.5, 1.5, 3, 1.5))
  radarchart(
    radar_df,
    axistype = 1,
    seg = seg,
    pcol = "#4C78A8",
    pfcol = adjustcolor("#4C78A8", alpha.f = 0.25),
    plwd = 2,
    cglcol = "grey70",
    cglty = 1,
    cglwd = 0.8,
    axislabcol = "grey30",
    vlcex = 1.25
  )
  angle <- seq(90, 450, length = length(values) + 1) * pi / 180
  angle <- angle[1:length(values)]
  scale <- 1 / (seg + 1) + values * seg / (seg + 1)
  label_radius <- pmin(scale + 0.05, 1.1)
  text(
    label_radius * cos(angle),
    label_radius * sin(angle),
    labels = sprintf("%.1f%%", values * 100),
    cex = 1.1,
    col = "grey20"
  )
  text(
    0,
    0,
    sprintf("平均\n%.1f%%", overall_mean * 100),
    cex = 1.3,
    col = "grey20"
  )
  title(paste0("正答率(", method_name, " / ", duty_cycle, "%)"), cex.main = 1.3)
  dev.off()
}

output_files <- character(0)
for (method_name in unique(combos$method)) {
  for (duty_cycle in unique(combos$dutyCycle)) {
    sub_dt <- agg[method == method_name & dutyCycle == duty_cycle]
    overall_mean <- participant_overall[method == method_name & dutyCycle == duty_cycle,
                                        mean(participantRate, na.rm = TRUE)]
    if (is.na(overall_mean)) {
      overall_mean <- 0
    }
    output_path <- file.path(output_dir, sprintf("task_accuracy_radar_%s_%s.png", method_name, duty_cycle))
    make_radar_plot(sub_dt, method_name, duty_cycle, output_path, overall_mean)
    output_files <- c(output_files, output_path)
  }
}

message("出力先: ", paste(output_files, collapse = "\n"))
