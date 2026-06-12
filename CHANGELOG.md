# Changelog

## v0.0.1 — 2026-06-12

Initial extraction from a private research repo (ZigLinguistics).

- Porter (1980) + Snowball (Porter2) stemmers migrated to Zig 0.16
  (algorithms unchanged).
- 15 legacy test expectations corrected: they had never executed in the
  source repo and asserted step-level rule transforms against the full
  pipeline; every correction refereed against NLTK PorterStemmer in both
  ORIGINAL_ALGORITHM and default modes (which agree with this
  implementation on all 15).
- Brown-vocabulary fixture (41,434 word types, provenance documented) +
  full golden TSVs for both stemmers, byte-identical across runs.
- Generated 2×208-pair golden-sample regression test.
- NLTK agreement over the full vocabulary: Porter 99.32% vs
  ORIGINAL_ALGORITHM (target was ≥95%), Snowball 99.24% vs NLTK Snowball.
- 20 tests. Register exp-1781280310 (verdict filed by the operator's
  experiment ledger).
