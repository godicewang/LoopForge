# Explicit Non-Productive Release Classification

Status: **the clean package is explicitly non-productive and that classification is included in the final accepted release**

Recorded: `2026-08-16T14:06:46Z`

## Decision

LoopForge's ordinary macOS package does not contain a separately isolated and
ratified productive provider. The package is therefore classified explicitly
as `nonProductiveTransportVeto`; this is no longer an inference from an empty
backend list or a prose report.

The source enum intentionally has no productive case. Its only states are the
exact packaged non-productive transport-veto identity and an unavailable
fail-closed fallback. Both expose `productiveExecutionAvailable == false`.
The exact provider-harness loader additionally rejects any manifest whose
classification, availability Boolean, operational mode, or productive backend
set disagree.

## Package binding

Clean source revision `dc33b91606c27fc073773c990e9840ae398e3316`
packages the same declaration into both `LoopForgeBuildManifest.json` and
`LoopForgeProviderHarnessManifest.json`:

- `releaseCapabilityClassification = nonProductiveTransportVeto`;
- `productiveExecutionAvailable = false`;
- `providerHarnessOperationalMode = transportVetoOnly`; and
- `productiveProviderBackends = []`.

The build manifest has SHA-256
`a70f0c4a2eeb75775a3eaab7dca48f6f1024bea9084bcc6d1133aedd9bcbf387`.
The provider manifest has SHA-256
`9f3c8174c7f59f4a705b8c4b143ed489fedcb688af4ce59e89f04e573b258b6c`.
The smoke gate parses and compares every field before launching the signed
Mach-O.

## Verification

The forged productive-availability test and the fail-closed missing-harness
test passed. The complete current source suite passed 883 tests with 8
environment-gated skips and 0 failures in 92.850 seconds. The clean
package-owned suite passed 883/8/0 in 77.283 seconds. Release compilation,
deep-strict signature verification, ZIP/DMG/checksum validation, exact source
snapshot binding, and isolated executable startup smoke passed.

The package binds source snapshot
`4b5c8ecf75084c9e86651c5c3b640d081b1406cfc3fafe3427c890b1651e78df`
and package-test digest
`83a96a404fe010e0f1b0078c912fad85e76bc8c50716c2bf6200539ae8733719`.
The exact app executable SHA-256 is
`8f4e3ab923583d71df91d999ea3e0d3981bedb2fa4fc86e36d655ec70fdc8738`
and its CDHash is `ac112ed294a8718dc3c1a6b90d2adc0da9acf175`.

The startup smoke probe now forwards `--isolated-inspection-profile`; a source
test prevents regression to ordinary persisted-state startup. The user's
Watcher store retained SHA-256
`a59ca5375c6ee3c78de63773df68b20e80106ef15ad1fd7b85776ba78a584d71`,
891807 bytes, and mtime epoch 1786885277 across smoke and native inspection.

## Native proof

Computer Use inspected the exact packaged application under the isolated
profile. The Accessibility tree and visible UI both showed:

`Non-productive safety build · Transport-veto only · no productive provider is installed or authorized.`

The isolated-profile banner was visible at the same time, no persisted Watcher
was loaded, and Build Watcher remained disabled. The
[1060×752 native screenshot](../screenshots/packaged-loopforge-nonproductive-release-classification-20260816T1403Z.png)
has SHA-256
`e171e5ef2069cbfc52110efe458fd3dbb2718ae00293fbb56a8bf4d478a0fd58`.
Quit left zero packaged/helper processes and zero verification mounts.

EasyBusiness remained read-only at branch `codex/USA_Version`, HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, and NUL-delimited status
digest `2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.

## Boundary

This closes the alternative release gate that required either a separately
ratified productive-provider isolation architecture or an explicit
non-productive classification. It does not make the current package
mutation-capable. Later receipts close the disposable Watcher chain, explicitly
retain the non-mutation containment veto, and classify repository telemetry as
non-mutating/not-applicable; see the current package verification report.
