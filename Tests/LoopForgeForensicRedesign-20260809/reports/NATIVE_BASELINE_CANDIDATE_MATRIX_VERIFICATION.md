# Native Baseline/Candidate Matrix Verification

Status: **candidate matrix passed independent adversarial review and the exact clean-revision package passed native confirmation; push remains pending**

Recorded: `2026-08-16T10:31:38Z`

The baseline is the exact recoverable LoopForge commit `6e9b99d12e61c5a4fce2d867d7986cb56c75a1a0`. The candidate source snapshot is `3870639da9fa122df044658f68608fbfed8385fccd341fb7ee2d872d2be57845`, now bound to clean implementation commit `65d050f7300ae62073ed8ac36eeeda5f30f9e5ec`. All matrix captures came from the real native application at the matched standard/accessibility and expanded/narrow configurations. The user display was restored to its original `1168×755` scaled setting after capture. The exact clean-commit package was then relaunched through Computer Use for final native confirmation.

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

- executable: `bf857623a683aed3da556148e0548d63f39227c2e7516a7f13881a04ea83447b`;
- ZIP: `7a51e174cdb8df4db96bf7e21c3ffdcbf1b65ab42a63bbe2465b5f5292fc3443`;
- DMG: `85f89b3e8b1598ae966de98f1ec91ce99f4b5ce48d34e91233ab46ae4f0efd91`;
- package test log: `1daa3cbd9781f49e8732fd7e7acdb0efe8d707c9ebd4838798c774d4b79e7717`.

The clean package embeds `sourceDirty: false`, the exact implementation commit, the reviewed source snapshot, and the accepted test-log digest. [The final clean-package screenshot](../screenshots/packaged-loopforge-clean-65d050f-native-confirmation-20260816T102827Z.jpeg), SHA-256 `46b0b08c6de2c7f839933ea579e80cb8007e3db7a848b9f83eec8467b358797a`, confirms the stopped legacy task, primary task hierarchy, Running node loops summary, graph cards, and explicit continuation labels in the signed application. Final release remains false only until the reporting commit and push complete.
