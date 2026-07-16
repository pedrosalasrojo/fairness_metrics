# =============================================================================
# 03_compute_all_metrics.R
#
# Computes every fairness metric in this repo IN ONE PASS (as opposed to
# 02_compute_metrics_one_by_one.R, which walks through each one separately
# for teaching purposes) and writes a single combined summary to
# output/fairness_metrics_summary.csv.
#
# This is the script to adapt if you just want to point the toolkit at your
# own data: replace the call to 01_load_data.R below with your own loading +
# validation code, keep G/Y/Yhat/ZG (and optionally A) pointing at your
# columns, and everything downstream is unchanged.
#
# Run from the repo root (scripts/repo/).
# =============================================================================

source("fairness_functions.R")
source("01_load_data.R")   # loads + validates mock_data

eps_used <- 0.10   # discrimination-aversion parameter for the 4 multidimensional metrics

# ---------------------------------------------------------------------------
# 1. The 13 binary metrics + Conditional Equal Opportunity, all at once
# ---------------------------------------------------------------------------
binary_res <- compute_binary_metrics(mock_data, G = "G", Y = "Y", Yhat = "Yhat", A = "age_band")
binary_table <- format_binary_metrics_table(binary_res$metrics)

cat("\n================================================================\n")
cat(" 13 binary fairness metrics (G = 0 vs G = 1)\n")
cat("================================================================\n")
print(binary_table, row.names = FALSE)

cat("\nGroup-level rates behind the metrics above:\n")
print(binary_res$by_group_rates, row.names = FALSE)

cat("\nConditional Equal Opportunity (TPR gap within each age_band):\n")
print(binary_res$conditional_equal_opportunity, row.names = FALSE)

# ---------------------------------------------------------------------------
# 2. The 4 multidimensional metrics, all at once
# ---------------------------------------------------------------------------
multi_res   <- compute_all_multidimensional(mock_data, Y = "Y", Yhat = "Yhat", groups = "ZG", eps = eps_used)
multi_table <- format_multidimensional_table(multi_res)

cat("\n================================================================\n")
cat(sprintf(" 4 multidimensional fairness metrics (subgroups ZG = 0..3, eps = %.2f)\n", eps_used))
cat("================================================================\n")
print(multi_table, row.names = FALSE)

# ---------------------------------------------------------------------------
# 3. Combined summary written to disk
# ---------------------------------------------------------------------------
combined <- rbind(
  data.frame(family = "binary",           metric = binary_table$metric, value = binary_table$point_estimate, is_fair = NA),
  data.frame(family = "multidimensional", metric = multi_table$metric,  value = multi_table$global_value,     is_fair = multi_table$is_fair)
)

if (!dir.exists("output")) dir.create("output")
out_path <- file.path("output", "fairness_metrics_summary.csv")
write.csv(combined, out_path, row.names = FALSE)

cat(sprintf("\nCombined summary (%d metrics) written to %s\n", nrow(combined), out_path))
