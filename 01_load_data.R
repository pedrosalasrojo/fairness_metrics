# =============================================================================
# 01_load_data.R
#
# Loads the mock loan-approval data used throughout this repo and runs a few
# sanity checks before any fairness metric is computed. Run this script from
# the repo root (scripts/repo/), i.e. make sure your working directory is the
# folder that contains this file, fairness_functions.R and data/mock_data.csv.
#
# If data/mock_data.csv does not exist yet, run generate_mock_data.R first:
#   Rscript generate_mock_data.R
# =============================================================================

data_path <- file.path("data", "mock_data.csv")

if (!file.exists(data_path)) {
  stop(
    "data/mock_data.csv not found. Run generate_mock_data.R first ",
    "(from the repo root: Rscript generate_mock_data.R), then re-run this script."
  )
}

mock_data <- read.csv(data_path, stringsAsFactors = FALSE)

# ---------------------------------------------------------------------------
# Sanity checks: the columns every downstream script relies on must exist
# and have the expected type/coding. These checks are what "plug and play"
# means in practice -- if you swap in your own data, run this script first
# and fix any error message before moving on to 02_/03_.
# ---------------------------------------------------------------------------
required_cols <- c("G", "region", "age_band", "score", "Y", "Yhat", "ZG")
missing_cols  <- setdiff(required_cols, names(mock_data))
if (length(missing_cols) > 0) {
  stop("Missing required column(s): ", paste(missing_cols, collapse = ", "))
}

stopifnot(
  "G must be binary (0/1)"     = all(sort(unique(mock_data$G))    == c(0, 1)),
  "Y must be binary (0/1)"     = all(sort(unique(mock_data$Y))    == c(0, 1)),
  "Yhat must be binary (0/1)"  = all(sort(unique(mock_data$Yhat)) == c(0, 1)),
  "ZG must be integer-coded"   = all(mock_data$ZG %% 1 == 0)
)

cat("Data loaded successfully:", nrow(mock_data), "rows,", ncol(mock_data), "columns.\n\n")

cat("Column roles used by the fairness metrics in this repo:\n")
cat("  G      - protected attribute for the 13 binary metrics (0 = disadvantaged, 1 = advantaged)\n")
cat("  Y      - true outcome (1 = would repay the loan)\n")
cat("  Yhat   - algorithm's decision (1 = loan approved)\n")
cat("  score  - continuous predicted probability behind Yhat\n")
cat("  age_band - stratifying variable for Conditional Equal Opportunity\n")
cat("  ZG     - integer subgroup code (0-3) for the 4 multidimensional metrics\n\n")

cat("Group sizes (G):\n");            print(table(mock_data$G))
cat("\nSubgroup sizes (ZG):\n");       print(table(mock_data$ZG))
cat("\nRepayment rate (Y) by G:\n");   print(tapply(mock_data$Y,    mock_data$G, mean))
cat("\nApproval rate (Yhat) by G:\n"); print(tapply(mock_data$Yhat, mock_data$G, mean))

# `mock_data` is left in the environment for 02_/03_ to use when this script
# is sourced rather than run standalone.
