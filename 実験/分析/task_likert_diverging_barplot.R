#!/usr/bin/env Rscript

# 二極分散型積み上げ横棒グラフ（リッカート尺度）の描画スクリプト
# 参考: https://rfortherestofus.com/2021/10/diverging-bar-chart

lib_dir <- file.path(getwd(), ".r_libs")
if (dir.exists(lib_dir)) {
  .libPaths(c(lib_dir, .libPaths()))
}

if (!requireNamespace("data.table", quietly = TRUE)) {
  stop("data.table が見つかりません。先にパッケージを導入してください。")
}
if (!requireNamespace("tidyverse", quietly = TRUE)) {
  stop("tidyverse が見つかりません。先にパッケージを導入してください。")
}
if (!requireNamespace("scales", quietly = TRUE)) {
  stop("scales が見つかりません。先にパッケージを導入してください。")
}

library(data.table)
library(tidyverse)
library(scales)

# ---- スクリプトの場所からプロジェクトルートと入出力ディレクトリを決定 ----
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

# ---- データ読み込み ----
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

# 条件ラベル（箱ひげ図スクリプトと同じ順序）
condition_levels <- c(
  "hand-grip × 70",
  "hand-grip × 100",
  "wrist-worn × 70",
  "wrist-worn × 100"
)
raw_dt[, condition := paste0(method, " × ", dutyCycle)]
raw_dt[, condition := factor(condition, levels = condition_levels)]

# clarity / confidence をロング形式に変換（tidyverse で扱うため data.frame に変換）
long_df <- melt(
  raw_dt,
  id.vars = c("participantId", "method", "dutyCycle", "condition"),
  measure.vars = c("clarity", "confidence"),
  variable.name = "item",
  value.name = "value"
) %>%
  as_tibble() %>%
  filter(!is.na(value))

item_labels <- c(clarity = "力覚の分かりやすさ", confidence = "回答への確信度")
long_df <- long_df %>%
  mutate(
    item = factor(item, levels = names(item_labels), labels = item_labels),
    value = as.integer(round(value))
  )

# ---- 参考記事の手順に従って集計 ----
# 1) 度数・割合
summary_df <- long_df %>%
  group_by(item, condition, value) %>%
  count(name = "n_answers") %>%
  group_by(item, condition) %>%
  mutate(percent_answers = n_answers / sum(n_answers)) %>%
  ungroup()

# 2) 二極分散用データを作成
# 7件法では中間の4点を左右に1/2ずつ割り当て、中心（0%）をまたぐように配置する
summary_div_main <- summary_df %>%
  filter(value != 4) %>%
  mutate(
    category = paste0(value, "点"),
    percent_answers_signed = if_else(value <= 3, -percent_answers, percent_answers)
  )

summary_div_mid_left <- summary_df %>%
  filter(value == 4) %>%
  transmute(
    item,
    condition,
    value,
    n_answers,
    percent_answers,
    category = "4点(左)",
    percent_answers_signed = -percent_answers / 2
  )

summary_div_mid_right <- summary_df %>%
  filter(value == 4) %>%
  transmute(
    item,
    condition,
    value,
    n_answers,
    percent_answers,
    category = "4点(右)",
    percent_answers_signed = percent_answers / 2
  )

summary_div <- bind_rows(summary_div_main, summary_div_mid_left, summary_div_mid_right) %>%
  mutate(
    # stack順:
    # 左側(外→内): 1,2,3,4(左) / 右側(内→外): 4(右),5,6,7
    # ggplotの正側スタック順の都合に合わせ、正側のfactor順は 7,6,5,4(右) とする
    category = factor(
      category,
      levels = c("1点", "2点", "3点", "4点(左)", "7点", "6点", "5点", "4点(右)")
    )
  )

output_paths <- character(0)

for (item_name in levels(summary_div$item)) {
  item_df <- summary_div %>% filter(item == item_name)
  if (nrow(item_df) == 0) next

  p <- item_df %>%
    ggplot(aes(
      x = condition,
      y = percent_answers_signed,
      fill = category
    )) +
    geom_col() +
    geom_hline(yintercept = 0, color = "black") +
    coord_flip() +
    # coord_flip()後の表示で、上から hand-grip × 70 → ... → wrist-worn × 100 にする
    scale_x_discrete(limits = rev(condition_levels)) +
    scale_y_continuous(
      limits = c(-1, 1),
      breaks = seq(-1, 1, by = 0.25),
      minor_breaks = seq(-1, 1, by = 0.125),
      labels = function(x) paste0(round(abs(x) * 100), "%"),
      expand = c(0, 0)
    ) +
    scale_fill_manual(
      breaks = c("1点", "2点", "3点", "4点(左)", "5点", "6点", "7点"),
      labels = c("1点", "2点", "3点", "4点", "5点", "6点", "7点"),
      values = c(
        "1点" = "darkorange3",
        "2点" = "orange",
        "3点" = "gold",
        "4点(左)" = "grey80",
        "4点(右)" = "grey80",
        "5点" = "skyblue",
        "6点" = "deepskyblue3",
        "7点" = "deepskyblue4"
      ),
      name = NULL
    ) +
    labs(
      x = "条件 × デューティ比",
      y = "回答割合"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      axis.text.x = element_text(color = "grey20"),
      panel.grid.major = element_line(color = "grey80", linewidth = 0.4),
      panel.grid.minor = element_line(color = "grey90", linewidth = 0.25),
      legend.position = "bottom",
      plot.margin = margin(t = 5.5, r = 20, b = 5.5, l = 8)
    )

  file_key <- names(item_labels)[match(item_name, item_labels)]
  output_path <- file.path(output_dir, sprintf("task_likert_diverging_bar_%s.png", file_key))
  ggsave(output_path, plot = p, width = 7.8, height = 4.5, dpi = 150)
  output_paths <- c(output_paths, output_path)
}

message("出力先: ", paste(output_paths, collapse = "\n"))
