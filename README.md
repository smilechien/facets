# FACETS Model

A lightweight, web-oriented **FACETS-style** module for multi-facet rating analysis.

This component is adapted from the FACETS-related logic in the uploaded `raschonlinePCM` project and focuses on the two sections most relevant for a GitHub overview: **Principles** and **Methods**. A minimal Python module and a runnable CSV example are included so the FACETS workflow can be demonstrated outside the full web application.

---

## Principles

The FACETS model extends Rasch measurement to situations where an observed score is influenced by **multiple facets** rather than by persons and items alone. In practical rating settings, a score may depend simultaneously on:

- performer or examinee ability,
- task or item difficulty,
- judge severity or leniency,
- segment, station, or occasion effects.

This implementation follows several practical principles.

### 1. Multi-facet measurement
Each row of data is interpreted as one rating event produced by the joint action of multiple facets. In long-format input, **all columns before the final numeric `Score` column are treated as facet terms**.

### 2. Common latent scale
Facet levels are interpreted on a shared measurement logic so that different sources of variation can be reviewed together in one coherent framework.

### 3. Additive explanation
The simplified Python implementation uses an additive design matrix to approximate expected scores and residual structure. This does **not** attempt to replicate proprietary FACETS estimation exactly; instead, it provides stable, interpretable diagnostics for web-based reporting and teaching.

### 4. Fit-oriented interpretation
Observed ratings are compared with expected values to derive **approximate INFIT and OUTFIT summaries** for each facet level. These summaries help identify:

- unusually severe or lenient judges,
- inconsistent facet levels,
- unexpected rating behavior,
- local clues for closer fairness review.

### 5. Usability first
The goal is accessible browser-based or script-based analysis:

- upload or read a CSV,
- detect whether it is FACETS long format,
- optionally reshape supported wide judge panels,
- generate fit summaries quickly,
- export tables for dashboards or reports.

---

## Methods

### Input rule
The preferred input is a **long-format CSV** in which:

- all columns before the last column are facet identifiers,
- the final column is numeric and named `Score` (or any last numeric column).

Example facet sets include:

- `Dancer,Judge,Segment,Score`
- `Student,Rater,Station,Score`
- `Patient,Doctor,Clinic,Score`

### Workflow
The minimal workflow contains the following steps.

1. **Read the CSV robustly** using common encodings.
2. **Validate FACETS long format** by checking that the final column is mostly numeric.
3. **Standardize numeric facet labels** by prefixing numeric-like terms with the facet name.
   - Example: `Judge = 1,2,3` becomes `Judge1, Judge2, Judge3`.
4. **Fit a simplified additive model** using dummy-coded facet terms.
5. **Compute residual-based fit summaries** for each facet level.
6. **Return facet-level tables** containing:
   - `INFIT_MNSQ`
   - `OUTFIT_MNSQ`
   - `INFIT_ZSTD`
   - `OUTFIT_ZSTD`

### Supported wide-panel detection
The included Python example also detects one common judging layout such as:

- `A01, A02, ..., B01, B02, ...`

where:

- the alphabetic prefix is treated as a segment or occasion,
- the repeated numeric suffix is treated as a judge identifier.

Such data can be reshaped automatically into FACETS long format.

---

## Minimal executable CSV example

Save the following as `example_facets_minimal.csv`.

```csv
Dancer,Judge,Segment,Score
TPE121,1,A,2
TPE121,2,A,1
TPE121,3,A,2
TPE121,1,B,2
TPE121,2,B,1
TPE121,3,B,2
JPN233,1,A,1
JPN233,2,A,2
JPN233,3,A,2
JPN233,1,B,1
JPN233,2,B,2
JPN233,3,B,2
```

---

## Quick start

```bash
python facets_module.py example_facets_minimal.csv --outdir outputs
```

This will generate:

- `facets_long_clean.csv`
- `facet_Dancer_estimates.csv`
- `facet_Judge_estimates.csv`
- `facet_Segment_estimates.csv`
- `facets_summary.json`

---

## Notes

- This code is a **lightweight FACETS-style helper** for demonstration, rapid diagnostics, and report preparation.
- It is **not** intended to reproduce the full estimation engine or output conventions of commercial FACETS software.
- The emphasis is on **clarity, usability, and integration into web dashboards or research prototypes**.
