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
base_dir <- file.path(project_root, "実験", "実験結果", "NASA-TLX")
output_dir <- file.path(script_dir, "outputs")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

files <- list.files(base_dir, pattern = "\\.csv$", full.names = TRUE)
if (length(files) == 0) {
  candidate_dirs <- list.dirs(project_root, recursive = TRUE, full.names = TRUE)
  nasa_dirs <- candidate_dirs[basename(candidate_dirs) == "NASA-TLX"]
  if (length(nasa_dirs) > 0) {
    base_dir <- nasa_dirs[1]
    files <- list.files(base_dir, pattern = "\\.csv$", full.names = TRUE)
  }
}
if (length(files) == 0) {
  stop("NASA-TLX のCSVが見つかりません。")
}

message("読み込んだCSVファイル:")
for (file_path in files) {
  message("- ", basename(file_path))
}

read_nasa <- function(path) {
  dt <- fread(path, encoding = "UTF-8")
  if (ncol(dt) >= 5) {
    setnames(dt, 1:5, c("item", "rating", "count", "weight", "score"))
  }
  dt[, item := ifelse(is.na(item) | item == "", "総合", item)]
  dt[, participantId := sub("^(P\\d+)_.*$", "\\1", basename(path))]
  dt[, method := sub("^P\\d+_(.*)\\.csv$", "\\1", basename(path))]
  dt[, method := gsub("_", "-", method)]
  dt[, rating := as.numeric(rating)]
  dt[, score := as.numeric(score)]
  dt[method %in% c("hand-grip", "wrist-worn")]
}

raw_dt <- rbindlist(lapply(files, read_nasa), fill = TRUE)
if (nrow(raw_dt) == 0) {
  stop("解析対象の条件 (hand-grip / wrist-worn) が見つかりません。")
}

item_levels <- c(
  "知的・知覚的要求",
  "身体的要求",
  "タイムプレッシャー",
  "作業成績",
  "努力",
  "フラストレーション"
)

run_paired_tests <- function(dt, value_col, label_prefix) {
  results <- list()
  items <- unique(dt$item)
  for (current_item in items) {
    slice <- dt[item == current_item]
    wide <- dcast(
      slice,
      participantId ~ method,
      value.var = value_col
    )
    if (!all(c("hand-grip", "wrist-worn") %in% names(wide))) {
      next
    }
    wide <- wide[!is.na(`hand-grip`) & !is.na(`wrist-worn`)]
    n <- nrow(wide)
    if (n == 0) {
      next
    }
    diff <- wide[["wrist-worn"]] - wide[["hand-grip"]]
    shapiro_p <- NA_real_
    test_name <- NA_character_
    statistic <- NA_real_
    p_value <- NA_real_
    if (n >= 3) {
      shapiro_p <- tryCatch(
        shapiro.test(diff)$p.value,
        error = function(e) NA_real_
      )
    }

    if (!is.na(shapiro_p) && shapiro_p >= 0.05) {
      test <- t.test(wide[["wrist-worn"]], wide[["hand-grip"]], paired = TRUE)
      test_name <- "paired_t_test"
      statistic <- unname(test$statistic)
      p_value <- test$p.value
    } else {
      test <- wilcox.test(
        wide[["wrist-worn"]],
        wide[["hand-grip"]],
        paired = TRUE,
        exact = FALSE
      )
      test_name <- "wilcoxon_signed_rank"
      statistic <- unname(test$statistic)
      p_value <- test$p.value
    }

    results[[length(results) + 1]] <- data.table(
      measure = label_prefix,
      item = current_item,
      n = n,
      shapiro_p = shapiro_p,
      test = test_name,
      statistic = statistic,
      p_value = p_value,
      mean_wrist_worn = mean(wide[["wrist-worn"]]),
      mean_hand_grip = mean(wide[["hand-grip"]]),
      mean_diff = mean(diff)
    )
  }
  rbindlist(results, fill = TRUE)
}

rating_dt <- raw_dt[item %in% item_levels & !is.na(rating)]
rating_dt[, item := factor(item, levels = item_levels)]
rating_results <- run_paired_tests(rating_dt, "rating", "rating")

total_dt <- raw_dt[item == "総合" & !is.na(score)]
total_dt[, item := "総合スコア"]
total_results <- run_paired_tests(total_dt, "score", "total_score")

all_results <- rbindlist(list(rating_results, total_results), fill = TRUE)
all_results <- all_results[order(measure, item)]

output_path <- file.path(output_dir, "nasa_tlx_tests.csv")
fwrite(all_results, output_path)

print(all_results)
message("出力先: ", output_path)
