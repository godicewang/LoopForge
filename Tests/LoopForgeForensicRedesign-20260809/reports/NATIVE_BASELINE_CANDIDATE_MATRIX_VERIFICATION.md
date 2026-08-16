# Native Baseline/Candidate Matrix Verification

Status: **current dirty-source candidate matrix passed independent adversarial review; clean-revision rebuild remains pending**

Recorded: `2026-08-16T10:05:20Z`

The baseline is the exact recoverable LoopForge commit `6e9b99d12e61c5a4fce2d867d7986cb56c75a1a0`. The candidate is the signed package built from dirty-source snapshot `3870639da9fa122df044658f68608fbfed8385fccd341fb7ee2d872d2be57845`. All captures came from the real native application at the matched standard/accessibility and expanded/narrow configurations. The user display was restored to its original `1168×755` scaled setting after capture.

## Red → red → green review chain

1. The first independent review vetoed the candidate at confidence `0.97`: redundant Auto Loop/diagnostics chrome demoted and truncated task identity, dense metadata weakened accessibility layouts, and graph cards were clipped.
2. After the hierarchy and whole-column correction, the second independent review again vetoed at confidence `0.97`: H-04 failed because three cells bisected lower graph cards at an unlabeled vertical viewport boundary. H-05, H-06, H-07, and H-09 passed.
3. After the whole-row/top-alignment correction, the final independent review passed at confidence `0.94`. H-04, H-05, H-06, H-07, and H-09 all passed and `requiredChanges` is empty. The reviewer found complete displayed cards, explicit `Next levels` and `More nodes below` boundaries, stable task hierarchy, and robust narrow/accessibility reflow.

The two red receipts remain immutable evidence; they were not overwritten by the final green review.

## Final four-cell candidate matrix

| Cell | Native size | Candidate SHA-256 | Result |
|---|---:|---|---|
| Standard expanded | 1173×768 | `9dbdbe3bb65fa12e1a9881f1bc350404967bb9e17f294d64e5d29982fbf3cec2` | pass |
| Standard narrow | 1060×752 | `bc88e75b0a8df7b4711eff2318d176023d0eaaf5e286f5bf8f100ac14305139c` | pass |
| Accessibility expanded | 1098×752 | `c517f92e132233c2d99927cda0319e58b7f72586ab953aa38977fb0b051fde05` | pass |
| Accessibility narrow | 1060×752 | `09eb378203ac385e1dde475e4640943ce028f85d94b23e0a460d982c293f364c` | pass |

The reproducible native-pixel metrics and diff harness produced [the final contact sheet](../screenshots/loopforge-native-matrix-whole-row-20260816T100000Z-contact-sheet.jpg), SHA-256 `0c8e84353eeb1851d18548955a2a213378c1c59031d476b9d76a4920c4d8f7f5`, and [machine-readable metrics](../screenshots/loopforge-native-matrix-whole-row-20260816T100000Z-metrics.json).

## Package binding

The reviewed package passed the package-owned suite with **874 executed, 8 skipped, and 0 failures**, strict deep signing, and bounded native startup. Its primary artifacts are:

- executable: `530a0eaeb39fb68f97becc8a8157b0ca6805a0b950f3280ed43da459dd427c36`;
- ZIP: `7e5af93ea939e96a9ae2530f8106498396353df9027fccfd5b8108b43a29eb58`;
- DMG: `128d41d4d034b34c874ac1a3ce93227dbb5b177e6ddd5970244eb469cf42e184`;
- package test log: `9c16fe6f7a10f94c2a71a472c813ef291011dc7c19e15c1001325115c24edf45`.

This closes the current native baseline/candidate matrix only. The package is still dirty-source, and the review/report receipts necessarily postdate its source snapshot. Clean-revision rebuild, final clean-package verification, commit, and push remain required. Final release is false.
