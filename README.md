# Diet, Physical Activity & Obesity Risk — NHANES 2021–2023

Analysis of the CDC National Health and Nutrition Examination Survey (August 2021–August 2023) — examining how physical activity, sedentary behaviour, and dietary quality predict obesity in 6,235 U.S. adults using SAS logistic regression.

**[View Research Report →](https://kevintan701.github.io/nhanes-activity-diet/)**

---

## Key Findings

- Sedentary adults had **52.0% obesity prevalence** vs. **33.4%** in active adults (χ²=156.2, p<0.001)
- The composite activity score was the **strongest predictor** (Wald χ²=91.9, OR=0.932, 95% CI: 0.918–0.945, p<0.001)
- Sedentary time raised obesity odds independently of activity level (OR=1.001/min, 95% CI: 1.001–1.001, p<0.001)
- Dietary fiber was the only significant protective dietary factor (OR=0.983/g/day, 95% CI: 0.977–0.989, p<0.001)
- Adults below the federal poverty line had **55% higher obesity odds** than high-income peers (OR=1.553, 95% CI: 1.274–1.894, p<0.001)
- Full 7-predictor stepwise model: **c-statistic=0.656**, Hosmer–Lemeshow χ²=1.63 (p=0.9903, outstanding calibration); optimal cut-off 0.400, sensitivity 65.3%, specificity 55.3%

---

## Project Structure

```
nhanes-activity-diet/
├── nhanes_activity_diet.sas   # Full SAS analysis pipeline (9 sections)
├── index.html                 # Interactive research report
└── README.md
```

---

## Analysis Pipeline (SAS)

The SAS program covers 9 sections:

| Section | Content |
|---|---|
| 0–1 | Global parameters and macro library — reusable macros for XPT import, variable summarization, frequency tables, group profiling, and median imputation |
| 2 | Batch XPT import — 5 NHANES files merged on SEQN respondent ID |
| 3 | Data cleaning, cohort restriction (adults ≥18), and PAQ variable harmonization for the 2021–2023 redesigned questionnaire |
| 4 | EDA — descriptive statistics, frequency tables, bivariate cross-tabulations with chi-square |
| 5 | Feature engineering — composite activity score, diet quality score, income categories, log transforms, median imputation |
| 6 | Three logistic regression models (A: activity only, B: dietary only, C: full stepwise) with ODS Graphics odds ratio plots |
| 7 | ROC/AUC, decile calibration, Youden's J cut-off, confusion matrix, and PROC SURVEYFREQ national estimates |
| 8–9 | Scored dataset export and dataset inventory |

---

## Data

Five XPT files from the NHANES August 2021–August 2023 cycle:

| File | Contents |
|---|---|
| `DEMO_L.XPT` | Demographics — age, sex, race/ethnicity, poverty-to-income ratio, MEC weights |
| `BMX_L.XPT` | Body measures — BMI, waist circumference, height, weight |
| `PAQ_L.XPT` | Physical activity questionnaire (2021–2023 redesigned variables) |
| `DR1TOT_L.XPT` | 24-hour dietary recall Day 1 — calories, protein, fat, sugar, fiber, sodium |
| `BPXO_L.XPT` | Oscillometric blood pressure |

Download from: **https://wwwn.cdc.gov/nchs/nhanes/**

> Files are not included in this repository. Download the 2021–2023 cycle files and upload to your SAS OnDemand working directory.

---

## Physical Activity Quantification

The 2021–2023 PAQ_L uses a frequency-unit-duration structure. MET-minutes/week were calculated as:

```
MET-min/week = (Moderate min/week × 4.0) + (Vigorous min/week × 8.0)
```

Activity classification:
- **Active** — ≥600 MET-min/week (meets CDC guidelines): 52.8%
- **Low Active** — some activity but <600 MET-min/week: 28.0%
- **Sedentary** — zero reported leisure activity: 18.5%

---

## Model Results

### Three models compared

| Model | Predictors | N | AUC |
|---|---|---|---|
| A — Activity only | Composite score, sedentary time, CDC guideline flag | 6,235 used | 0.607 |
| B — Dietary only | Fiber, sodium, log-calories, sugars, diet quality score | 4,929 used | 0.573 |
| C — Full stepwise | All domains combined (7 variables selected, 11 df) | 4,929 used | **0.656** |

### Final model odds ratios (Model C)

| Predictor | Coeff | SE | OR | 95% CI | p |
|---|---|---|---|---|---|
| Composite activity score (per point) | −0.0707 | 0.0074 | 0.932 | 0.918–0.945 | <0.001 |
| Dietary fiber (per g/day) | −0.0170 | 0.0031 | 0.983 | 0.977–0.989 | <0.001 |
| Age (per year, continuous) | −0.0158 | 0.0057 | 0.984 | 0.973–0.995 | 0.005 |
| Sedentary time (per min/day) | 0.000853 | 0.000153 | 1.001 | 1.001–1.001 | <0.001 |
| Hypertension | 0.4208 | 0.0623 | 1.523 | 1.348–1.721 | <0.001 |
| Income: Below Poverty vs High | 0.4405 | 0.1012 | 1.553 | 1.274–1.894 | <0.001 |
| Income: Low vs High | 0.3630 | 0.0919 | 1.438 | 1.201–1.721 | <0.001 |
| Income: Middle vs High | 0.3942 | 0.0744 | 1.483 | 1.282–1.716 | <0.001 |
| Age 30–44 vs 18–29 | 0.6664 | 0.1366 | 1.947 | 1.490–2.545 | <0.001 |
| Age 45–59 vs 18–29 | 1.1893 | 0.2028 | 3.285 | 2.208–4.887 | <0.001 |
| Age 60+ vs 18–29 | 1.0554 | 0.2807 | 2.873 | 1.657–4.980 | <0.001 |

Coeff = log-odds estimate; SE = standard error; OR = exp(Coeff); Wald 95% CI.

### Stepwise AUC build sequence

| Step | Variable entered | Wald χ² | Pr > χ² |
|---|---|---|---|
| 1 | Composite Activity Score | 168.51 | <0.001 |
| 2 | Hypertension | 57.19 | <0.001 |
| 3 | Dietary Fiber (g/day) | 35.27 | <0.001 |
| 4 | Age Group | 40.08 | <0.001 |
| 5 | Sedentary Minutes/Day | 21.22 | <0.001 |
| 6 | Income Category | 34.33 | <0.001 |
| **7** | **Age (continuous)** | **7.76** | **0.005** |

Final model c-statistic (AUC) = **0.656** | Hosmer–Lemeshow χ²=1.63, p=0.9903

---

## Getting Started

### Requirements

- SAS OnDemand for Academics (free): https://www.sas.com/en_us/software/on-demand-for-academics.html
- Or any SAS 9.4+ environment

### Steps

1. Download the 5 NHANES XPT files listed above from CDC
2. Upload to your SAS OnDemand working directory
3. Update the `%let DATAPATH` line at the top of `nhanes_activity_diet.sas`
4. Run the program — all 9 sections execute sequentially

---

## References

1. CDC. *NHANES August 2021–August 2023.* https://wwwn.cdc.gov/nchs/nhanes/
2. U.S. Department of Health and Human Services. *Physical Activity Guidelines for Americans, 2nd Edition.* 2018.
3. U.S. Department of Agriculture and HHS. *Dietary Guidelines for Americans, 2020–2025.* December 2020.
4. Biswas A, et al. Sedentary time and its association with risk for disease incidence, mortality, and hospitalization. *Ann Intern Med.* 2015;162(2):123–132.
5. Hosmer DW, Lemeshow S, Sturdivant RX. *Applied Logistic Regression.* 3rd ed. Wiley; 2013.
6. Emmerich SD, et al. Obesity and Severe Obesity Prevalence in Adults: United States, August 2021–August 2023. *NCHS Data Brief No. 508.* CDC/NCHS; 2024.

---

## Author

**Yuntao (Kevin) Tan**  
tyuntao@umich.edu  
February 2026
