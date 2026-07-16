# Fairness Metrics Toolkit

**Author:** Pedro Salas-Rojo

A self-contained R toolkit implementing **13 binary (two-group) fairness
metrics** and **4 multidimensional (N-subgroup) fairness metrics** used to
audit whether an algorithm's predictions/decisions treat a protected group
(e.g. by sex, ethnicity, region) fairly relative to a reference group.

This repo is **metrics only**. It does not implement or discuss correction
methods (i.e. ways to *fix* an unfair algorithm) — only how to *measure*
fairness, with a runnable example on synthetic data.

No installation is required beyond R itself: every function here uses only
base R (`stats`), no external packages.

---

## Repository structure

```
fairness_metrics/
├── README.md                          <- this file
├── fairness_functions.R                <- every fairness metric function (the only file you need to reuse elsewhere)
├── 01_load_data.R                      <- loads + validates the data
├── 02_compute_metrics_one_by_one.R      <- walks through each metric individually, with explanation
├── 03_compute_all_metrics.R             <- computes every metric at once and writes a summary CSV
├── data/
│   └── mock_data.csv                   <- synthetic loan-approval data (generated, not real; ships pre-built)
└── docs/
    └── fairness_metrics_guide.pdf      <- longer write-up: formulas, interpretation, worked example
```

Running `03_compute_all_metrics.R` writes a summary to `output/fairness_metrics_summary.csv`,
created automatically on first run — that folder is not part of the repo itself.

## Quick start

`data/mock_data.csv` ships pre-built, so no generation step is needed. Clone
the repo, open R (or RStudio) with the repo folder as your working directory,
and run the scripts in order:

```r
source("01_load_data.R")                  # 1. loads + validates the mock data
source("02_compute_metrics_one_by_one.R") # 2. walks through every metric, one at a time
source("03_compute_all_metrics.R")        # 3. computes everything at once -> output/fairness_metrics_summary.csv
```

or, from a terminal:

```bash
Rscript 02_compute_metrics_one_by_one.R
Rscript 03_compute_all_metrics.R
```

`01_load_data.R` is sourced automatically by scripts 02 and 03 — you only
need to run it directly if you want to inspect the data on its own.

### Using your own data instead of the mock example

`fairness_functions.R` has no dependency on the mock dataset. To apply it to
your own data, your data frame needs:

| Role | Used by | Requirement |
|---|---|---|
| `G` | 13 binary metrics | exactly 2 values (any coding; internally mapped to 0/1) |
| `Y` | 13 binary metrics | true outcome, binary (0/1) |
| `Yhat` | 13 binary metrics | algorithm's decision, binary (0/1) |
| `A` | Conditional Equal Opportunity (optional) | any categorical stratifying variable |
| `ZG` | 4 multidimensional metrics | integer subgroup code (0, 1, 2, ... — as many subgroups as you need) |

Then call `compute_binary_metrics()` and/or `compute_all_multidimensional()`
directly (see `03_compute_all_metrics.R` for the exact calls) — nothing else
in the repo needs to change.

---

## The mock example

`data/mock_data.csv` was built by simulating a **loan-approval algorithm**:
applicants have covariates (income, credit score, employment years) that
determine whether they would truly repay a loan (`Y`), and the algorithm
predicts a repayment probability (`score`) and approves the loan if that
probability clears a threshold (`Yhat`). The simulation deliberately builds
in:

1. A structural gap in applicant covariates across the protected group `G`
   (0 = disadvantaged, 1 = advantaged), reflecting real-world disparities
   upstream of any algorithm; and
2. A direct algorithmic penalty against `G = 0` on top of that, i.e. the
   kind of bias fairness audits are designed to catch.

`region` (a second attribute, combined with `G` into `ZG = 2*G + region`) and
`age_band` are included only to give the multidimensional metrics and
Conditional Equal Opportunity something to condition on. No real data is used
anywhere in this repository.

---

## Metrics reference

All 13 binary metrics compare group `G = 0` (disadvantaged) against
`G = 1` (advantaged/reference). Metrics ending in `_diff` have an expected
value of **0** under parity; metrics ending in `_ratio` have an expected
value of **1**.

### 13 binary (two-group) metrics

| # | Metric | Formula (G=0 vs G=1) | Reference |
|---|---|---|---|
| 1 | Statistical Parity (`SP_diff`) | P(Ŷ=1\|G=0) − P(Ŷ=1\|G=1) | Dwork, Hardt, Pitassi, Reingold & Zemel (2012), *Fairness Through Awareness*, ITCS |
| 2 | Disparate Impact (`DI_ratio`) | P(Ŷ=1\|G=0) / P(Ŷ=1\|G=1) | Feldman, Friedler, Moeller, Scheidegger & Venkatasubramanian (2015), *Certifying and Removing Disparate Impact*, KDD |
| 3 | Equal Opportunity, TPR parity (`EqOp_plus_diff`) | TPR(G=0) − TPR(G=1) | Hardt, Price & Srebro (2016), *Equality of Opportunity in Supervised Learning*, NeurIPS |
| 4 | Equal Opportunity, TNR parity (`EqOp_minus_diff`) | TNR(G=0) − TNR(G=1) | Hardt, Price & Srebro (2016) — mirror of #3 |
| 5 | Equalized Odds, TPR component (`EqOdds_plus_diff`) | TPR(G=0) − TPR(G=1) | Hardt, Price & Srebro (2016) |
| 6 | Equalized Odds, FPR component (`EqOdds_minus_diff`) | FPR(G=0) − FPR(G=1) | Hardt, Price & Srebro (2016) |
| 7 | Treatment Equality, difference (`TreatmentEquality_diff`) | (FPR/FNR)(G=0) − (FPR/FNR)(G=1) | Berk, Heidari, Jabbari, Kearns & Roth (2021), *Fairness in Criminal Justice Risk Assessments: The State of the Art*, Sociological Methods & Research |
| 8 | Treatment Equality, ratio (`TreatmentEquality_ratio`) | (FPR/FNR)(G=0) / (FPR/FNR)(G=1) | Berk, Heidari, Jabbari, Kearns & Roth (2021) |
| 9 | Overall Accuracy, difference (`OverallAcc_diff`) | Acc(G=0) − Acc(G=1) | Berk, Heidari, Jabbari, Kearns & Roth (2021) |
| 10 | Overall Accuracy, ratio (`OverallAcc_ratio`) | Acc(G=0) / Acc(G=1) | Berk, Heidari, Jabbari, Kearns & Roth (2021) |
| 11 | Equalized Disincentive (`EqDisincentive_diff`) | [TPR−FPR](G=0) − [TPR−FPR](G=1) | Youden (1950), *Index for Rating Diagnostic Tests*, Cancer — group-parity version of Youden's J statistic |
| 12 | PPV parity / Predictive Parity (`PPV_parity_diff`) | PPV(G=0) − PPV(G=1) | Chouldechova (2017), *Fair Prediction with Disparate Impact*, Big Data |
| 13 | NPV parity (`NPV_parity_diff`) | NPV(G=0) − NPV(G=1) | Chouldechova (2017) — mirror of #12 |

**Conditional Equal Opportunity** (`conditional_equal_opportunity()`): recomputes
metric #3 (TPR parity) separately within each level of a third variable `A`.
This is a natural extension of Hardt et al. (2016) implemented in this
toolkit to check whether an overall Equal Opportunity gap is uniform across
strata or concentrated in one — it is not itself a metric with a single
canonical source paper.

### 4 multidimensional (N-subgroup) metrics

These extend the idea of fairness beyond two groups to any number of
subgroups (e.g. combinations of protected attributes), each governed by a
discrimination-aversion parameter ε (`eps`): larger ε relaxes the fairness
threshold, with ε = 0 the strictest case.

| Metric | Formula | Fair iff | Reference |
|---|---|---|---|
| Statistical Subgroup Parity (`SubPar`) | max<sub>m</sub> [P(zg<sub>m</sub>)·\|P(Ŷ=1) − P(Ŷ=1\|zg<sub>m</sub>)\| − ε] | ≤ 0 | Kearns, Neel, Roth & Wu (2018), *Preventing Fairness Gerrymandering: Auditing and Learning for Subgroup Fairness*, ICML |
| False Positive Subgroup Parity (`FalPos`) | max<sub>m</sub> [P(Y=0,zg<sub>m</sub>)·\|FPR<sub>overall</sub> − FPR<sub>zgm</sub>\| − ε] | ≤ 0 | Kearns, Neel, Roth & Wu (2018), ICML |
| Differential Fairness (`DifFair`) | max<sub>m</sub> P(Ŷ=c\|zg<sub>m</sub>) / min<sub>m</sub> P(Ŷ=c\|zg<sub>m</sub>) − e<sup>ε</sup>, for c ∈ {0,1} | ≤ 0 for both c | Foulds, Islam, Keya & Pan (2020), *An Intersectional Definition of Fairness*, IEEE ICDE |
| Worst-Case Fairness (`WorCas`) | 1 − min<sub>m</sub> P(Ŷ=c\|zg<sub>m</sub>) / max<sub>m</sub> P(Ŷ=c\|zg<sub>m</sub>), for c ∈ {0,1} | ≤ 1 − e<sup>−ε</sup> for both c | Ghosh, Genuit & Reagan (2021), *Characterizing Intersectional Group Fairness with Worst-Case Comparisons* |

The companion paper Kearns, Neel, Roth & Wu, *An Empirical Study of Rich
Subgroup Fairness for Machine Learning* (FAT* 2019) empirically studies the
same two definitions and is a useful complement to the ICML 2018 paper above.

See `docs/fairness_metrics_guide.pdf` for the full derivations, how to read
each number, and a worked example on the mock data.

---

## Acknowledgments

Alexandros Puente Pomar (Research Assistant) developed the original
implementation of these metrics that this toolkit builds on. His work — the
correctness and care in the underlying computations — was excellent, and this
public repo would not exist without it.

## How to cite

If you use this toolkit, please cite:

> Salas-Rojo, P. (2026). *Fairness Metrics Toolkit*
> [Software]. https://github.com/pedrosalasrojo/fairness_metrics
