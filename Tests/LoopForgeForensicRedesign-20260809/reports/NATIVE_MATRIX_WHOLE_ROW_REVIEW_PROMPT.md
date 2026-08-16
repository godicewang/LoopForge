You are the independent adversarial visual reviewer. Assess only the attached native macOS screenshots and pixel-difference evidence. Do not edit files, inspect implementation code, or trust prior review conclusions.

Evidence binding:

- Baseline revision: `6e9b99d12e61c5a4fce2d867d7986cb56c75a1a0`.
- Candidate source snapshot SHA-256: `3870639da9fa122df044658f68608fbfed8385fccd341fb7ee2d872d2be57845`.
- The first eight attached images alternate baseline then candidate in this order: standard-expanded, standard-narrow, accessibility-expanded, accessibility-narrow.
- The ninth image is the labeled four-row contact sheet. The final four images are the 3×-contrast pixel deltas in that same cell order.
- Native dimensions are 1175×768 baseline versus 1173×768 candidate for standard-expanded, 1060×752 for both standard-narrow, 1098×752 for both accessibility-expanded, and 1060×752 for both accessibility-narrow. The 2-pixel standard-expanded difference is the current macOS zoom maximum; evaluate visible composition, not that harmless frame delta.
- The candidate intentionally preserves a migration-required safety block instead of offering Resume Task. Judge its presentation and hierarchy, not the absence of an unsafe resume affordance.

Evaluate every cell and return the exact requested JSON shape. A global pass requires all five gates to pass:

- H-04: no visible clipping, bisected graph card, unusable density, or unexplained viewport crop. Clearly labeled whole-column and whole-row continuation boundaries such as “Next levels” and “More nodes below” are permitted when every displayed card is complete.
- H-05: the primary Running node loops summary remains visible in the initial viewport.
- H-06: the concrete task identity and task summary retain primary hierarchy; mode, diagnostics, path, and migration detail remain secondary.
- H-07: Larger Text/accessibility cells reflow robustly with readable typography, compact metadata, and no loss of required primary content.
- H-09: candidate aesthetics are not materially worse than baseline across hierarchy, typography, geometry, density, spacing, tone, and information architecture.

Be strict and concrete. Do not treat a large pixel-difference ratio as either success or failure by itself. Set `candidateHasVisibleClipping` true only for actual candidate clipping/bisection, not a deliberate and labeled continuation boundary. If the verdict is `pass`, `requiredChanges` must be an empty array; otherwise list only changes required to clear the veto.
