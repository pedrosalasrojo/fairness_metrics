# =============================================================================
# 02_compute_metrics_one_by_one.R
#
# Walks through every fairness metric in this repo ONE AT A TIME, printing
# its formula, its value on the mock data, its expected value under parity,
# and a one-line interpretation. Use this script to learn what each metric
# measures in isolation. See 03_compute_all_metrics.R for the "all at once"
# version, and README.md for the full formulas and literature references.
#
# Run from the repo root (scripts/repo/).
# =============================================================================

source("fairness_functions.R")
source("01_load_data.R")   # loads + validates mock_data

cat("\n================================================================\n")
cat(" PART 1 -- The 13 binary fairness metrics (G = 0 vs G = 1)\n")
cat("================================================================\n")

# Small printing helper used only in this walkthrough script.
.explain <- function(name, value, formula, interpretation) {
  cat(sprintf("\n[%s]\n", name))
  cat(sprintf("  formula:        %s\n", formula))
  cat(sprintf("  value:          %.4f\n", value))
  cat(sprintf("  interpretation: %s\n", interpretation))
}

# --- 1. Statistical Parity -------------------------------------------------
v <- statistical_parity_diff(mock_data)
.explain("Statistical Parity (SP_diff)", v,
         "P(Yhat=1|G=0) - P(Yhat=1|G=1)",
         "Negative => the disadvantaged group (G=0) is approved less often overall. Parity value: 0.")

# --- 2. Disparate Impact ----------------------------------------------------
v <- disparate_impact_ratio(mock_data)
.explain("Disparate Impact (DI_ratio)", v,
         "P(Yhat=1|G=0) / P(Yhat=1|G=1)",
         "Below 1 => G=0 is approved proportionally less than G=1 (below 0.8 is the classic '4/5ths rule' threshold). Parity value: 1.")

# --- 3. Equal Opportunity (TPR parity) --------------------------------------
v <- equal_opportunity_tpr_diff(mock_data)
.explain("Equal Opportunity, TPR parity (EqOp_plus_diff)", v,
         "TPR(G=0) - TPR(G=1), where TPR = P(Yhat=1|Y=1)",
         "Negative => among applicants who WOULD repay, G=0 is approved less often than G=1. Parity value: 0.")

# --- 4. Equal Opportunity (TNR parity) --------------------------------------
v <- equal_opportunity_tnr_diff(mock_data)
.explain("Equal Opportunity, TNR parity (EqOp_minus_diff)", v,
         "TNR(G=0) - TNR(G=1), where TNR = P(Yhat=0|Y=0)",
         "Positive => among applicants who would NOT repay, G=0 is correctly rejected more often than G=1. Parity value: 0.")

# --- 5. Equalized Odds (TPR component) --------------------------------------
v <- equalized_odds_tpr_diff(mock_data)
.explain("Equalized Odds, TPR component (EqOdds_plus_diff)", v,
         "TPR(G=0) - TPR(G=1)",
         "Same quantity as Equal Opportunity's TPR parity; Equalized Odds additionally requires the FPR component below to hold. Parity value: 0.")

# --- 6. Equalized Odds (FPR component) ---------------------------------------
v <- equalized_odds_fpr_diff(mock_data)
.explain("Equalized Odds, FPR component (EqOdds_minus_diff)", v,
         "FPR(G=0) - FPR(G=1), where FPR = P(Yhat=1|Y=0)",
         "Negative => among applicants who would NOT repay, G=0 is mistakenly approved less often than G=1. Parity value: 0.")

# --- 7. Treatment Equality (difference) --------------------------------------
v <- treatment_equality_diff(mock_data)
.explain("Treatment Equality, difference (TreatmentEquality_diff)", v,
         "(FPR/FNR)(G=0) - (FPR/FNR)(G=1)",
         "Compares the RATIO of the two error types within each group; a large gap means the algorithm trades off false positives against false negatives very differently by group. Parity value: 0.")

# --- 8. Treatment Equality (ratio) -------------------------------------------
v <- treatment_equality_ratio(mock_data)
.explain("Treatment Equality, ratio (TreatmentEquality_ratio)", v,
         "(FPR/FNR)(G=0) / (FPR/FNR)(G=1)",
         "Same comparison as above expressed as a ratio. Parity value: 1.")

# --- 9. Overall Accuracy (difference) ----------------------------------------
v <- overall_accuracy_diff(mock_data)
.explain("Overall Accuracy, difference (OverallAcc_diff)", v,
         "Acc(G=0) - Acc(G=1), where Acc = P(Yhat=Y)",
         "The algorithm can be equally (or more) accurate for G=0 even while every other metric above shows a disparity -- accuracy parity does NOT imply fairness on the other 12 metrics. Parity value: 0.")

# --- 10. Overall Accuracy (ratio) --------------------------------------------
v <- overall_accuracy_ratio(mock_data)
.explain("Overall Accuracy, ratio (OverallAcc_ratio)", v,
         "Acc(G=0) / Acc(G=1)",
         "Same comparison as above expressed as a ratio. Parity value: 1.")

# --- 11. Equalized Disincentive ----------------------------------------------
v <- equalized_disincentive_diff(mock_data)
.explain("Equalized Disincentive (EqDisincentive_diff)", v,
         "[TPR(G=0)-FPR(G=0)] - [TPR(G=1)-FPR(G=1)]  (group-level Youden's J parity)",
         "Compares each group's own signal-detection ability (TPR-FPR, Youden 1950); can be near 0 even when SP/DI/PPV show large gaps, because it nets out base-rate differences. Parity value: 0.")

# --- 12. PPV parity (Predictive Parity) --------------------------------------
v <- ppv_parity_diff(mock_data)
.explain("Predictive Parity / PPV parity (PPV_parity_diff)", v,
         "PPV(G=0) - PPV(G=1), where PPV = P(Y=1|Yhat=1)",
         "Negative => among APPROVED applicants, those from G=0 are less likely to actually repay than approved G=1 applicants (the approval decision is less 'reliable' for G=0). Parity value: 0.")

# --- 13. NPV parity -----------------------------------------------------------
v <- npv_parity_diff(mock_data)
.explain("NPV parity (NPV_parity_diff)", v,
         "NPV(G=0) - NPV(G=1), where NPV = P(Y=0|Yhat=0)",
         "Mirror image of PPV parity for REJECTED applicants. Parity value: 0.")

cat("\n================================================================\n")
cat(" PART 1b -- Conditional Equal Opportunity (extension, needs a 3rd variable)\n")
cat("================================================================\n")
ceo <- conditional_equal_opportunity(mock_data, A = "age_band")
cat("\nEqual Opportunity's TPR gap, computed separately within each age_band stratum:\n")
print(ceo)
cat("\nRead this alongside metric #3 above: if CEO_diff is similar in every stratum,\n")
cat("the overall Equal Opportunity gap is not being driven by one age group alone.\n")

cat("\n================================================================\n")
cat(" PART 2 -- The 4 multidimensional metrics (subgroups ZG = 0,1,2,3)\n")
cat("================================================================\n")
cat("Discrimination-aversion parameter eps = 0.10 is used throughout this walkthrough.\n")
eps_demo <- 0.10

# --- 1. Statistical Subgroup Parity ------------------------------------------
subpar <- compute_SubPar(mock_data, Yhat = "Yhat", groups = "ZG", eps = eps_demo)
cat("\n[Statistical Subgroup Parity (SubPar)] -- Kearns, Neel, Roth & Wu (2018)\n")
cat("  formula: SubPar_zgm = P(zgm) * |P(Yhat=1) - P(Yhat=1|zgm)| - eps ; SubPar_ZG = max_m SubPar_zgm\n")
cat(sprintf("  SubPar_ZG = %.4f  (fair iff <= 0)  is_fair_ZG = %s\n", subpar$SubPar_ZG, subpar$is_fair_ZG))
print(subpar$per_group)

# --- 2. False Positive Subgroup Parity ---------------------------------------
falpos <- compute_FalPos(mock_data, Y = "Y", Yhat = "Yhat", groups = "ZG", eps = eps_demo)
cat("\n[False Positive Subgroup Parity (FalPos)] -- Kearns, Neel, Roth & Wu (2018)\n")
cat("  formula: FalPos_zgm = P(Y=0,zgm) * |FPR_overall - FPR_zgm| - eps ; FalPos_ZG = max_m FalPos_zgm\n")
cat(sprintf("  FalPos_ZG = %.4f  (fair iff <= 0)  is_fair_ZG = %s\n", falpos$FalPos_ZG, falpos$is_fair_ZG))
print(falpos$per_group)

# --- 3. Differential Fairness -------------------------------------------------
diffair <- compute_DifFair(mock_data, Y = "Y", Yhat = "Yhat", groups = "ZG", eps = eps_demo)
cat("\n[Differential Fairness (DifFair)] -- Foulds, Islam, Keya & Pan (2020)\n")
cat("  formula: DifFair_ZG(c) = max_m P(Yhat=c|zgm) / min_m P(Yhat=c|zgm) - e^eps ; fair iff <= 0 for c=0 AND c=1\n")
cat(sprintf("  DifFair_ZG(c=1) = %.4f  is_fair(c=1) = %s\n", diffair$c1$DifFair_ZG, diffair$c1$is_fair_ZG))
cat(sprintf("  DifFair_ZG(c=0) = %.4f  is_fair(c=0) = %s\n", diffair$c0$DifFair_ZG, diffair$c0$is_fair_ZG))
cat(sprintf("  is_fair_ZG (both classes) = %s\n", diffair$is_fair_ZG))

# --- 4. Worst-Case Fairness ----------------------------------------------------
worcas <- compute_WorCas(mock_data, Y = "Y", Yhat = "Yhat", groups = "ZG", eps = eps_demo)
cat("\n[Worst-Case Fairness (WorCas)] -- Ghosh, Genuit & Reagan (2021)\n")
cat("  formula: WorCas_ZG(c) = 1 - min_m P(Yhat=c|zgm) / max_m P(Yhat=c|zgm) ; fair iff <= 1 - e^{-eps} for c=0 AND c=1\n")
cat(sprintf("  WorCas_ZG(c=1) = %.4f  is_fair(c=1) = %s\n", worcas$c1$WorCas_ZG, worcas$c1$is_fair_ZG))
cat(sprintf("  WorCas_ZG(c=0) = %.4f  is_fair(c=0) = %s\n", worcas$c0$WorCas_ZG, worcas$c0$is_fair_ZG))
cat(sprintf("  is_fair_ZG (both classes) = %s\n", worcas$is_fair_ZG))

cat("\nDone. See 03_compute_all_metrics.R for a single combined summary table.\n")
