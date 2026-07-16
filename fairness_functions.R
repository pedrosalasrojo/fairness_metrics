# =============================================================================
# fairness_functions.R
#
# Fairness Metrics Toolkit
# Author: Pedro Salas-Rojo
# Builds on an original implementation of these metrics by
# Alexandros Puente Pomar (Research Assistant) -- see README.md, Acknowledgments.
#
# This file contains every function needed to compute:
#   - 13 binary (two-group) fairness metrics
#   - 1 extension of Equal Opportunity conditional on a third variable
#     ("Conditional Equal Opportunity")
#   - 4 multidimensional (N-subgroup) fairness metrics
#
# No other script in this repo defines fairness metrics. If you only want to
# reuse the metrics in your own project, this is the only file you need to
# source() (see README.md for literature references and formulas).
# =============================================================================


# =============================================================================
# SECTION 0 — Internal helpers (not meant to be called directly by users)
# =============================================================================

# Safe division: returns NA instead of erroring/NaN when the denominator is 0.
.safe_div <- function(num, den) ifelse(den == 0, NA_real_, num / den)

# Confusion-matrix counts (TP/FN/FP/TN/N) for one group.
# y and yhat must already be 0/1 vectors of equal length.
.conf_counts <- function(y, yhat) {
  list(
    TP = sum(y == 1 & yhat == 1),
    FN = sum(y == 1 & yhat == 0),
    FP = sum(y == 0 & yhat == 1),
    TN = sum(y == 0 & yhat == 0),
    N  = length(y)
  )
}

# Turns confusion-matrix counts into the rates used by the 13 metrics.
.rates_from_counts <- function(cc) {
  list(
    TPR    = .safe_div(cc$TP, cc$TP + cc$FN),          # True Positive Rate  (a.k.a. sensitivity, recall)
    FPR    = .safe_div(cc$FP, cc$FP + cc$TN),          # False Positive Rate
    TNR    = .safe_div(cc$TN, cc$TN + cc$FP),          # True Negative Rate  (a.k.a. specificity)
    FNR    = .safe_div(cc$FN, cc$FN + cc$TP),          # False Negative Rate
    Acc    = .safe_div(cc$TP + cc$TN, cc$N),           # Overall accuracy
    P_hat1 = .safe_div(cc$TP + cc$FP, cc$N),           # P(Yhat = 1), i.e. selection/acceptance rate
    PPV    = .safe_div(cc$TP, cc$TP + cc$FP),          # Positive Predictive Value (precision)
    NPV    = .safe_div(cc$TN, cc$TN + cc$FN)           # Negative Predictive Value
  )
}

# Coerces a two-valued vector to strict 0/1 coding. Stops if it is not binary.
# `what` is only used to produce a readable error message.
.as_binary_01 <- function(x, what) {
  u <- unique(x[!is.na(x)])
  if (length(u) != 2) stop(sprintf("%s must have exactly two distinct values (found %d).", what, length(u)))
  if (!all(sort(u) == c(0, 1))) x <- as.numeric(as.factor(x)) - 1
  x
}

# Adds "expected_parity" (0 for *_diff metrics, 1 for *_ratio metrics) and the
# resulting deviation to a data frame of point estimates. Used for reporting.
.add_parity_cols <- function(df_summ, estimate_col) {
  df_summ$expected_parity       <- ifelse(grepl("_ratio$", df_summ$metric), 1, 0)
  df_summ$deviation_from_parity <- df_summ[[estimate_col]] - df_summ$expected_parity
  df_summ
}


# =============================================================================
# SECTION 1 — The 13 binary fairness metrics
# =============================================================================
#
# All 13 metrics compare a protected/disadvantaged group (G = 0) against a
# reference/advantaged group (G = 1) on a binary decision Yhat against a
# binary ground truth Y. Difference metrics ("_diff") have expected value 0
# under parity; ratio metrics ("_ratio") have expected value 1 under parity.
#
#   Metric                    Formula (G=0 vs G=1)          Reference
#   ------------------------  ----------------------------  ------------------------------------------
#   SP_diff                   P(Yhat=1|G=0) - P(Yhat=1|G=1)  Dwork et al. (2012)
#   DI_ratio                   P(Yhat=1|G=0) / P(Yhat=1|G=1)  Feldman et al. (2015)
#   EqOp_plus_diff             TPR(G=0) - TPR(G=1)            Hardt, Price & Srebro (2016)
#   EqOp_minus_diff            TNR(G=0) - TNR(G=1)            Hardt, Price & Srebro (2016)
#   EqOdds_plus_diff           TPR(G=0) - TPR(G=1)            Hardt, Price & Srebro (2016)
#   EqOdds_minus_diff          FPR(G=0) - FPR(G=1)            Hardt, Price & Srebro (2016)
#   TreatmentEquality_diff     (FPR/FNR)(G=0) - (FPR/FNR)(G=1) Berk et al. (2021)
#   TreatmentEquality_ratio    (FPR/FNR)(G=0) / (FPR/FNR)(G=1) Berk et al. (2021)
#   OverallAcc_diff            Acc(G=0) - Acc(G=1)            Berk et al. (2021)
#   OverallAcc_ratio           Acc(G=0) / Acc(G=1)            Berk et al. (2021)
#   EqDisincentive_diff        (TPR-FPR)(G=0) - (TPR-FPR)(G=1) Youden (1950); parity version used here
#   PPV_parity_diff            PPV(G=0) - PPV(G=1)            Chouldechova (2017)
#   NPV_parity_diff            NPV(G=0) - NPV(G=1)            Chouldechova (2017); mirror of PPV parity
#
# See README.md for the full description of each metric and how to read it.
# -----------------------------------------------------------------------------

#' Compute all 13 binary fairness metrics (plus group-level diagnostics)
#'
#' @param df   data frame containing at least the G, Y and Yhat columns
#' @param G    name of the protected-group column (must have exactly 2 values)
#' @param Y    name of the true-outcome column (must be 0/1)
#' @param Yhat name of the decision/prediction column (must be 0/1)
#' @param A    optional name of a stratifying column. If supplied,
#'             Conditional Equal Opportunity (CEO) is also computed within
#'             each level of A (see Section 1.1 below).
#'
#' @return a list with:
#'   $metrics                       named numeric vector, the 13 metrics
#'   $by_group_rates                data frame of rates (TPR, FPR, ...) by group
#'   $by_group_counts               data frame of confusion-matrix counts by group
#'   $conditional_equal_opportunity data frame (only when `A` is supplied)
compute_binary_metrics <- function(df, G = "G", Y = "Y", Yhat = "Yhat", A = NULL) {

  g <- .as_binary_01(df[[G]], "G")
  y <- .as_binary_01(df[[Y]], "Y")
  yh <- .as_binary_01(df[[Yhat]], "Yhat")

  df$G    <- g
  df$Y    <- y
  df$Yhat <- yh
  if (!is.null(A)) df$A <- df[[A]]

  df0 <- df[df$G == 0, ]
  df1 <- df[df$G == 1, ]

  c0 <- .conf_counts(df0$Y, df0$Yhat)
  c1 <- .conf_counts(df1$Y, df1$Yhat)
  r0 <- .rates_from_counts(c0)
  r1 <- .rates_from_counts(c1)

  te0 <- .safe_div(r0$FPR, r0$FNR)   # Treatment Equality ratio within group 0
  te1 <- .safe_div(r1$FPR, r1$FNR)   # Treatment Equality ratio within group 1

  metrics <- c(
    SP_diff                 = r0$P_hat1 - r1$P_hat1,
    DI_ratio                = .safe_div(r0$P_hat1, r1$P_hat1),
    EqOp_plus_diff          = r0$TPR - r1$TPR,
    EqOp_minus_diff         = r0$TNR - r1$TNR,
    EqOdds_plus_diff        = r0$TPR - r1$TPR,
    EqOdds_minus_diff       = r0$FPR - r1$FPR,
    TreatmentEquality_diff  = te0 - te1,
    TreatmentEquality_ratio = .safe_div(te0, te1),
    OverallAcc_diff         = r0$Acc - r1$Acc,
    OverallAcc_ratio        = .safe_div(r0$Acc, r1$Acc),
    EqDisincentive_diff     = (r0$TPR - r0$FPR) - (r1$TPR - r1$FPR),
    PPV_parity_diff         = r0$PPV - r1$PPV,
    NPV_parity_diff         = r0$NPV - r1$NPV
  )

  out <- list(metrics = metrics)

  # ---------------------------------------------------------------------
  # 1.1 Conditional Equal Opportunity (CEO) — optional extension.
  # Equal Opportunity (Hardt et al., 2016) compares TPR across G overall;
  # CEO compares TPR across G within each level of a third variable A
  # (e.g. an age band, a region, a risk tier), which can reveal disparities
  # masked by aggregation, or confirm that a global gap is not driven by a
  # single stratum. This is a natural extension implemented in this toolkit,
  # not a metric with a single canonical source paper.
  # ---------------------------------------------------------------------
  if (!is.null(A)) {
    levels_A  <- sort(unique(df$A))
    CEO_table <- data.frame(A = levels_A, TPR_G0 = NA_real_, TPR_G1 = NA_real_, CEO_diff = NA_real_)
    for (k in seq_along(levels_A)) {
      a    <- levels_A[k]
      sub0 <- df[df$G == 0 & df$A == a, ]
      sub1 <- df[df$G == 1 & df$A == a, ]
      tpr0 <- .safe_div(sum(sub0$Yhat == 1 & sub0$Y == 1), sum(sub0$Y == 1))
      tpr1 <- .safe_div(sum(sub1$Yhat == 1 & sub1$Y == 1), sum(sub1$Y == 1))
      CEO_table$TPR_G0[k]   <- tpr0
      CEO_table$TPR_G1[k]   <- tpr1
      CEO_table$CEO_diff[k] <- tpr0 - tpr1
    }
    out$conditional_equal_opportunity <- CEO_table
  }

  out$by_group_rates <- data.frame(
    G      = c(0, 1),
    TPR    = c(r0$TPR,    r1$TPR),
    FPR    = c(r0$FPR,    r1$FPR),
    TNR    = c(r0$TNR,    r1$TNR),
    FNR    = c(r0$FNR,    r1$FNR),
    Acc    = c(r0$Acc,    r1$Acc),
    P_hat1 = c(r0$P_hat1, r1$P_hat1),
    PPV    = c(r0$PPV,    r1$PPV),
    NPV    = c(r0$NPV,    r1$NPV)
  )

  out$by_group_counts <- data.frame(
    G  = c(0, 1),
    TP = c(c0$TP, c1$TP),
    FN = c(c0$FN, c1$FN),
    FP = c(c0$FP, c1$FP),
    TN = c(c0$TN, c1$TN),
    N  = c(c0$N,  c1$N)
  )

  out
}

# -----------------------------------------------------------------------------
# 1.2 Thin per-metric wrappers.
#
# compute_binary_metrics() computes all 13 metrics in one pass because they
# share the same underlying confusion-matrix counts (recomputing the
# confusion matrix 13 times would be wasteful and risks the 13 numbers
# silently drifting out of sync). These wrappers exist so a user who only
# cares about one metric (e.g. for a walkthrough, as in
# 02_compute_metrics_one_by_one.R) can call it by name without having to know
# the internal metric-vector layout.
# -----------------------------------------------------------------------------

statistical_parity_diff    <- function(df, G = "G", Y = "Y", Yhat = "Yhat") compute_binary_metrics(df, G, Y, Yhat)$metrics[["SP_diff"]]
disparate_impact_ratio     <- function(df, G = "G", Y = "Y", Yhat = "Yhat") compute_binary_metrics(df, G, Y, Yhat)$metrics[["DI_ratio"]]
equal_opportunity_tpr_diff <- function(df, G = "G", Y = "Y", Yhat = "Yhat") compute_binary_metrics(df, G, Y, Yhat)$metrics[["EqOp_plus_diff"]]
equal_opportunity_tnr_diff <- function(df, G = "G", Y = "Y", Yhat = "Yhat") compute_binary_metrics(df, G, Y, Yhat)$metrics[["EqOp_minus_diff"]]
equalized_odds_tpr_diff    <- function(df, G = "G", Y = "Y", Yhat = "Yhat") compute_binary_metrics(df, G, Y, Yhat)$metrics[["EqOdds_plus_diff"]]
equalized_odds_fpr_diff    <- function(df, G = "G", Y = "Y", Yhat = "Yhat") compute_binary_metrics(df, G, Y, Yhat)$metrics[["EqOdds_minus_diff"]]
treatment_equality_diff    <- function(df, G = "G", Y = "Y", Yhat = "Yhat") compute_binary_metrics(df, G, Y, Yhat)$metrics[["TreatmentEquality_diff"]]
treatment_equality_ratio   <- function(df, G = "G", Y = "Y", Yhat = "Yhat") compute_binary_metrics(df, G, Y, Yhat)$metrics[["TreatmentEquality_ratio"]]
overall_accuracy_diff      <- function(df, G = "G", Y = "Y", Yhat = "Yhat") compute_binary_metrics(df, G, Y, Yhat)$metrics[["OverallAcc_diff"]]
overall_accuracy_ratio     <- function(df, G = "G", Y = "Y", Yhat = "Yhat") compute_binary_metrics(df, G, Y, Yhat)$metrics[["OverallAcc_ratio"]]
equalized_disincentive_diff<- function(df, G = "G", Y = "Y", Yhat = "Yhat") compute_binary_metrics(df, G, Y, Yhat)$metrics[["EqDisincentive_diff"]]
ppv_parity_diff             <- function(df, G = "G", Y = "Y", Yhat = "Yhat") compute_binary_metrics(df, G, Y, Yhat)$metrics[["PPV_parity_diff"]]
npv_parity_diff             <- function(df, G = "G", Y = "Y", Yhat = "Yhat") compute_binary_metrics(df, G, Y, Yhat)$metrics[["NPV_parity_diff"]]

# Conditional Equal Opportunity as a standalone call (returns the per-stratum table).
conditional_equal_opportunity <- function(df, G = "G", Y = "Y", Yhat = "Yhat", A) {
  compute_binary_metrics(df, G, Y, Yhat, A = A)$conditional_equal_opportunity
}

# Formats the named metric vector returned by compute_binary_metrics() into a
# reporting-friendly data frame (expected value under parity + deviation from it).
format_binary_metrics_table <- function(metrics_vec) {
  df <- data.frame(
    metric         = names(metrics_vec),
    point_estimate = as.numeric(metrics_vec),
    row.names      = NULL
  )
  .add_parity_cols(df, "point_estimate")
}


# =============================================================================
# SECTION 2 — The 4 multidimensional (N-subgroup) fairness metrics
# =============================================================================
#
# Unlike the 13 binary metrics (which compare exactly two groups: G = 0 vs.
# G = 1), these four metrics evaluate fairness across an arbitrary number of
# subgroups at once (e.g. combinations of sex x region x age band). They all
# take a "groups" column coded as consecutive integers (0, 1, 2, ...) and a
# discrimination-aversion parameter `eps` (epsilon): the metric is smaller,
# i.e. "more fair", as eps grows, because eps directly relaxes the fairness
# threshold. eps = 0 is the strictest, zero-tolerance case.
#
#   Metric    Reference
#   --------  --------------------------------------------------------------
#   SubPar    Kearns, Neel, Roth & Wu (2018, ICML); Kearns et al. (2018/2019)
#   FalPos    Kearns, Neel, Roth & Wu (2018, ICML); Kearns et al. (2018/2019)
#   DifFair   Foulds, Islam, Keya & Pan (2020, IEEE ICDE)
#   WorCas    Ghosh, Genuit & Reagan (2021)
#
# See README.md for the full formulas and how to read each one.
# -----------------------------------------------------------------------------

# Shared input handling for the 4 multidimensional metrics: coerces the
# subgroup column to consecutive integers, and binarizes Y/Yhat at quantile Q
# if they arrive as continuous scores rather than already-binary decisions.
.prep_multi_inputs <- function(df, groups, Y = NULL, Yhat = NULL, Q = 0.80) {
  df$ZG <- as.numeric(df[[groups]])
  if (any(df$ZG %% 1 != 0, na.rm = TRUE)) stop("`groups` column must contain integer subgroup codes (0, 1, 2, ...).")

  if (!is.null(Yhat)) {
    df$Yhat <- df[[Yhat]]
    if (!all(df$Yhat %in% c(0, 1), na.rm = TRUE)) df$Yhat <- ifelse(df$Yhat <= quantile(df$Yhat, Q, na.rm = TRUE), 0, 1)
  }
  if (!is.null(Y)) {
    df$Y <- df[[Y]]
    if (!all(df$Y %in% c(0, 1), na.rm = TRUE)) df$Y <- ifelse(df$Y <= quantile(df$Y, Q, na.rm = TRUE), 0, 1)
  }
  df
}

# -----------------------------------------------------------------------------
# 2.1 Statistical Subgroup Parity (SubPar) — Kearns, Neel, Roth & Wu (2018)
#
#   SubPar_zgm = P(zgm) * |P(Yhat=1) - P(Yhat=1|zgm)| - eps
#   SubPar_ZG  = max_m SubPar_zgm
#   Fair iff SubPar_ZG <= 0
# -----------------------------------------------------------------------------
compute_SubPar <- function(df, Yhat, groups, eps = 0, Q = 0.80) {

  df <- .prep_multi_inputs(df, groups = groups, Yhat = Yhat, Q = Q)
  p_hat1_overall <- mean(df$Yhat)
  groups_u       <- sort(unique(df$ZG))

  per_group <- lapply(groups_u, function(g) {
    idx   <- df$ZG == g
    n_g   <- sum(idx)
    p_zgm <- mean(idx)

    if (n_g == 0) return(data.frame(subgroup = g, n = 0L, P_zgm = NA_real_,
                                     P_hat1_overall = NA_real_, P_hat1_given_zgm = NA_real_,
                                     SubPar_zgm = NA_real_, is_fair = NA))

    p_hat1_g       <- mean(df$Yhat[idx])
    subpar_g       <- p_zgm * abs(p_hat1_overall - p_hat1_g)
    subpar_g_check <- subpar_g - eps

    data.frame(subgroup = g, n = n_g, P_zgm = p_zgm,
               P_hat1_overall = p_hat1_overall, P_hat1_given_zgm = p_hat1_g,
               SubPar_zgm = subpar_g, eps = eps,
               SubPar_zgm_check = subpar_g_check, is_fair = subpar_g_check <= 0)
  })

  per_group_df <- do.call(rbind, per_group)
  global_val   <- max(per_group_df$SubPar_zgm, na.rm = TRUE)

  list(per_group = per_group_df, SubPar_ZG = global_val, eps = eps,
       is_fair_ZG = max(per_group_df$SubPar_zgm_check, na.rm = TRUE) <= 0)
}

# -----------------------------------------------------------------------------
# 2.2 False Positive Subgroup Parity (FalPos) — Kearns, Neel, Roth & Wu (2018)
#
#   FalPos_zgm = P(Y=0,zgm) * |FPR_overall - FPR_zgm| - eps
#   FalPos_ZG  = max_m FalPos_zgm
#   Fair iff FalPos_ZG <= 0
# -----------------------------------------------------------------------------
compute_FalPos <- function(df, Y, Yhat, groups, eps = 0, Q = 0.80) {

  df <- .prep_multi_inputs(df, groups = groups, Y = Y, Yhat = Yhat, Q = Q)
  negatives          <- df$Y == 0
  p_hat1_neg_overall <- if (sum(negatives) > 0) mean(df$Yhat[negatives]) else NA_real_
  groups_u           <- sort(unique(df$ZG))

  per_group <- lapply(groups_u, function(g) {
    idx      <- df$ZG == g
    idx_neg  <- idx & negatives
    n_g      <- sum(idx)
    p_y0_zgm <- mean(idx & negatives)

    if (sum(idx_neg) == 0) return(data.frame(subgroup = g, n = n_g, P_Y0_zgm = p_y0_zgm,
                                              FPR_overall = p_hat1_neg_overall, FPR_given_zgm = NA_real_,
                                              FalPos_zgm = NA_real_, is_fair = NA))

    fpr_g          <- mean(df$Yhat[idx_neg])
    falpos_g       <- p_y0_zgm * abs(p_hat1_neg_overall - fpr_g)
    falpos_g_check <- falpos_g - eps

    data.frame(subgroup = g, n = n_g, P_Y0_zgm = p_y0_zgm,
               FPR_overall = p_hat1_neg_overall, FPR_given_zgm = fpr_g,
               FalPos_zgm = falpos_g, FalPos_zgm_check = falpos_g_check, eps = eps,
               is_fair = falpos_g_check <= 0)
  })

  per_group_df <- do.call(rbind, per_group)
  global_val   <- max(per_group_df$FalPos_zgm, na.rm = TRUE)

  list(per_group = per_group_df, FalPos_ZG = global_val, eps = eps,
       is_fair_ZG = max(per_group_df$FalPos_zgm_check, na.rm = TRUE) <= 0)
}

# -----------------------------------------------------------------------------
# 2.3 Differential Fairness (DifFair) — Foulds, Islam, Keya & Pan (2020)
#
#   Original criterion: for ALL y in {0,1} and ALL pairs (si, sj):
#     e^{-eps} <= P(Yhat=y|si) / P(Yhat=y|sj) <= e^{eps}
#   Checking max/min across all groups is equivalent to checking every
#   pairwise ratio, since max/min <= e^eps implies every pairwise ratio also
#   respects the bound.
#
#   DifFair_ZG(c) = max_m P(Yhat=c|zgm) / min_m P(Yhat=c|zgm) - e^eps
#   Fair iff DifFair_ZG(c) <= 0 for BOTH c = 0 and c = 1
# -----------------------------------------------------------------------------
compute_DifFair <- function(df, Y, Yhat, groups, eps = 0, Q = 0.80) {

  df       <- .prep_multi_inputs(df, groups = groups, Y = Y, Yhat = Yhat, Q = Q)
  groups_u <- sort(unique(df$ZG))

  dif_one_class <- function(c_class) {
    p_c_by_group <- sapply(groups_u, function(g) {
      idx <- df$ZG == g
      if (sum(idx) == 0) return(NA_real_)
      mean(df$Yhat[idx] == c_class)
    })
    names(p_c_by_group) <- paste0("ZG=", groups_u)

    p_max        <- max(p_c_by_group, na.rm = TRUE)
    p_min        <- min(p_c_by_group, na.rm = TRUE)
    global_ratio <- .safe_div(p_max, p_min)

    list(per_group  = data.frame(subgroup = groups_u, P_c_given_zgm = as.numeric(p_c_by_group), c_class = c_class),
         DifFair_ZG = global_ratio,
         is_fair_ZG = (global_ratio - exp(eps)) <= 0)
  }

  res_c1 <- dif_one_class(1)
  res_c0 <- dif_one_class(0)

  pairs <- combn(groups_u, 2)
  make_pairwise <- function(c_class, pg) {
    apply(pairs, 2, function(pair) {
      g1 <- pair[1]; g2 <- pair[2]
      p1 <- pg$P_c_given_zgm[pg$subgroup == g1]
      p2 <- pg$P_c_given_zgm[pg$subgroup == g2]
      ratio   <- .safe_div(max(p1, p2, na.rm = TRUE), min(p1, p2, na.rm = TRUE))
      dif_val <- ratio - exp(eps)
      data.frame(c_class = c_class, zgm1 = g1, zgm2 = g2, P_c_zgm1 = p1, P_c_zgm2 = p2,
                 ratio = ratio, DifFair_pair = dif_val, is_fair_pair = dif_val <= 0)
    }) |> (\(x) do.call(rbind, x))()
  }

  pairwise_df <- rbind(make_pairwise(1, res_c1$per_group), make_pairwise(0, res_c0$per_group))

  list(pairwise = pairwise_df, c1 = res_c1, c0 = res_c0, eps = exp(eps),
       is_fair_ZG = res_c1$is_fair_ZG && res_c0$is_fair_ZG)
}

# -----------------------------------------------------------------------------
# 2.4 Worst-Case Fairness (WorCas) — Ghosh, Genuit & Reagan (2021)
#
#   WorCas_ZG(c) = 1 - min_m P(Yhat=c|zgm) / max_m P(Yhat=c|zgm)
#   Fair iff WorCas_ZG(c) <= 1 - e^{-eps} for BOTH c = 0 and c = 1
#
#   (Derivation of the bound: DifFair requires max/min <= e^eps, i.e.
#    min/max >= e^{-eps}, i.e. 1 - min/max <= 1 - e^{-eps}.)
# -----------------------------------------------------------------------------
compute_WorCas <- function(df, Y, Yhat, groups, eps = 0, Q = 0.80) {

  df       <- .prep_multi_inputs(df, groups = groups, Y = Y, Yhat = Yhat, Q = Q)
  groups_u <- sort(unique(df$ZG))

  wc_one_class <- function(c_class) {
    p_c_by_group <- sapply(groups_u, function(g) {
      idx <- df$ZG == g
      if (sum(idx) == 0) return(NA_real_)
      mean(df$Yhat[idx] == c_class)
    })
    names(p_c_by_group) <- paste0("ZG=", groups_u)

    p_max      <- max(p_c_by_group, na.rm = TRUE)
    p_min      <- min(p_c_by_group, na.rm = TRUE)
    worcas_val <- 1 - .safe_div(p_min, p_max)
    fair_bound <- 1 - exp(-eps)

    list(per_group = data.frame(subgroup = groups_u, P_c_given_zgm = as.numeric(p_c_by_group), c_class = c_class),
         P_min = p_min, P_max = p_max, WorCas_ZG = worcas_val, is_fair_ZG = worcas_val <= fair_bound)
  }

  res_c1 <- wc_one_class(1)
  res_c0 <- wc_one_class(0)

  list(c1 = res_c1, c0 = res_c0, eps = 1 - exp(-eps), is_fair_ZG = res_c1$is_fair_ZG && res_c0$is_fair_ZG)
}

# -----------------------------------------------------------------------------
# 2.5 Wrapper: compute all 4 multidimensional metrics in one call
# -----------------------------------------------------------------------------
compute_all_multidimensional <- function(df, Y = "Y", Yhat = "Yhat", groups = "ZG", eps = 0, Q = 0.80) {
  list(
    SubPar  = compute_SubPar(df, Yhat = Yhat, groups = groups, eps = eps, Q = Q),
    FalPos  = compute_FalPos(df, Y = Y, Yhat = Yhat, groups = groups, eps = eps, Q = Q),
    DifFair = compute_DifFair(df, Y = Y, Yhat = Yhat, groups = groups, eps = eps, Q = Q),
    WorCas  = compute_WorCas(df, Y = Y, Yhat = Yhat, groups = groups, eps = eps, Q = Q)
  )
}

# Formats the 4 global (ZG-level) multidimensional results into one row,
# mirroring format_binary_metrics_table() for the binary metrics.
format_multidimensional_table <- function(multi_res) {
  data.frame(
    metric      = c("SubPar", "FalPos", "DifFair_c1", "DifFair_c0", "WorCas_c1", "WorCas_c0"),
    global_value = c(multi_res$SubPar$SubPar_ZG,
                      multi_res$FalPos$FalPos_ZG,
                      multi_res$DifFair$c1$DifFair_ZG,
                      multi_res$DifFair$c0$DifFair_ZG,
                      multi_res$WorCas$c1$WorCas_ZG,
                      multi_res$WorCas$c0$WorCas_ZG),
    is_fair     = c(multi_res$SubPar$is_fair_ZG,
                     multi_res$FalPos$is_fair_ZG,
                     multi_res$DifFair$c1$is_fair_ZG,
                     multi_res$DifFair$c0$is_fair_ZG,
                     multi_res$WorCas$c1$is_fair_ZG,
                     multi_res$WorCas$c0$is_fair_ZG),
    row.names   = NULL
  )
}
