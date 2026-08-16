# Process and Simulator Lifecycle Forensic Finding

Status: confirmed systemic defect  
Scope: stopped Graph task `1ED2180F-FBE1-4BCA-9E79-701F40CC3483` and current dirty LoopForge resource-management implementation  
EasyBusiness handling: read-only evidence only

## Executive finding

LoopForge can report successful cleanup while leaving both a detached GUI process and task-created Simulator devices behind. The failure is not a single missed `kill`: the ownership model records a short-lived PID and a boot-state transition, while the actual durable resources are a launchd-owned Simulator application process and Simulator device records.

This is a direct explanation for the user's observation that the machine can remain hot after LoopForge exits. A surviving Simulator GUI process may be idle by the time it is inspected, but it keeps the Simulator subsystem alive; booted devices and related services can consume CPU earlier or later. The 19 remaining task-named devices prove that cleanup was not complete even when no device was currently booted.

## Exact orphan chain

1. At `2026-08-02T16:45:00Z`, node `reproduce-ios-us-baseline` iteration 5 ran the Simulator executable directly:

   ```text
   "$SIM" -CurrentDeviceUDID "$UDID" ... &
   GPID=$!
   ```

2. At `2026-08-02T16:45:19Z`, the node recorded `guiPid=40779`.
3. The currently surviving Simulator process is PID `40917`, PPID `1`, started at local `2026-08-03 00:45:25 +08:00` (`2026-08-02T16:45:25Z`)—six seconds after the recorded PID. This timing and executable path tie it to the same launch sequence.
4. At `2026-08-02T16:53:52Z`, cleanup iterated only over the recorded PIDs, including `40779`.
5. At `2026-08-02T16:53:53Z`, the evidence declared `ownedPidAbsent=40779`. That proves only that the launcher PID was gone, not that the Simulator application instance was gone.
6. On `2026-08-03`, later nodes repeatedly observed PID `40917` and classified it as pre-existing. A later agent summary explicitly said it had not terminated “pre-existing Simulator PID `40917`.” The prior node's ownership information had been lost across node boundaries.
7. On `2026-08-09T14:12:27Z`, PID `40917` still existed with PPID `1` and the same Simulator executable path.
8. After the ownership chain was preserved in this report, the audit sent `SIGTERM` to exactly PID `40917`. At `2026-08-09T14:14:58Z`, the PID was absent and the task-named booted-device count remained zero.

The cleanup check therefore produced a false negative: it checked the stored PID, while the owned durable application had already detached/relaunched under another PID.

## Persistent device evidence

A controlled `simctl list devices -j` inspection after deleting only the temporary device created by this forensic audit found:

- 19 custom devices whose names begin with `LoopForge` or `EasyBusiness`;
- 19 in `Shutdown` state;
- 0 in `Booted` state;
- names spanning community QA, evidence verification, six “Final Gaps” iterations, three MaxType/SafeArea variants, two XCUITest variants, and compact U.S. QA.

The devices are preserved as forensic evidence. They were not deleted during this audit because the current implementation cannot prove which task owns each device or whether its data is still needed for evidence.

## Why the current repair is insufficient

The dirty `HostResourceLeases.swift` implementation improves one narrow boundary but cannot close this leak:

- `GraphHostResourceKind` has only `iosSimulatorBoot`.
- Ownership distinguishes only `ownedTransition` from `borrowed`.
- The broker allows `declareIOSSimulatorBoot` and `markAcquired`; it has no typed device-create or Simulator-application operations.
- `IOSSimulatorHostResourceProvider.release` calls only `xcrun simctl shutdown <UUID>`.
- A device that LoopForge created and then shut down remains permanently registered.
- A Simulator GUI process that detaches from the recorded child PID is outside the lease registry.
- The node prompt forbids broad cleanup, which is correct, but there is no durable ownership manifest that makes exact cleanup possible.

The dirty `ProcessRunner.swift` descendant-tree escalation is directionally valuable for ordinary subprocess trees. It cannot by itself solve a macOS app that relaunches or becomes a launchd-owned singleton after the original process tree snapshot.

## Required redesign gates

The Graph runtime must not be considered resource-safe until it has all of the following:

1. Typed lifecycle resources for `iosSimulatorDevice`, `iosSimulatorBoot`, and `simulatorApplicationSession`.
2. Create-before-use ownership records containing task ID, node ID, exact UDID, device name, runtime, device type, creation timestamp, retention policy, and evidence references.
3. Broker-only `simctl create`, `boot`, `shutdown`, and `delete` operations. Raw agent calls must be rejected or treated as a task failure.
4. A Simulator app session identity resolved after launch using bundle identity and activation/session evidence—not `$!` alone.
5. Cleanup verification against durable state: exact UDID absent when deletion is required, no task-owned device booted, and no owned GUI session remaining.
6. Cross-node ownership continuity. A later node must not relabel a process as pre-existing merely because the current node did not launch it.
7. Crash recovery on LoopForge startup and task stop, with bounded retries and an explicit `releaseFailed` state that blocks success.
8. Evidence-retention semantics: devices required for evidence may be retained only by an explicit lease with expiry, never by accidental omission.
9. A low-thermal idle gate that samples owned process CPU after stop and refuses to report cleanup success while owned work remains active.
10. Tests that simulate PID detachment/reparenting and confirm cleanup follows the durable resource, not the launcher PID.

## Defect classification

| ID | Severity | Defect | Evidence-backed consequence |
|---|---:|---|---|
| F-010 | Critical | PID ownership collapses after GUI detachment/relaunch | Simulator PID `40917` survives while cleanup passed for PID `40779` |
| F-011 | Critical | Resource leases model boot state but not device creation/deletion | 19 task-named Simulator devices remain registered |
| F-012 | High | Node-local ownership does not survive across Graph nodes | Later node mislabeled the earlier task-owned PID as pre-existing |
| F-013 | High | Cleanup acceptance checks the stored proxy, not durable host state | False “owned process absent” result and misleading completion evidence |

## Immediate safety state

The forensic audit's own temporary Simulator device was shut down and deleted by exact UDID, and the deletion was verified. No Simulator device is currently booted. The proven task-owned PID `40917` was terminated by exact PID and verified absent. The 19 prior shutdown devices remain preserved while their per-device ownership and evidence-retention requirements are reconstructed; no broad deletion was performed.
