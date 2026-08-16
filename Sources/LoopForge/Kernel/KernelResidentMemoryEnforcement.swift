import Foundation

/// Stable reason carried by production resolution and durable launch vetoes.
/// The raw value preserves schema-v1 journal compatibility while the case
/// name records the narrower, evidence-backed conclusion: an ordinary macOS
/// process has no hard pre-exec physical-footprint primitive. This is a
/// terminal platform policy, not a missing optional dependency.
enum KernelResidentMemoryEnforcementUnavailabilityReason:
  String, Codable, Hashable, Sendable
{
  case ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit =
    "residentMemoryEnforcementUnavailable"
}

/// Non-serializable launch authority proving that a separate boundary can
/// enforce one exact resident-memory ceiling. No production issuer exists on
/// ordinary macOS today: RLIMIT_RSS is advisory/aliased to address space,
/// task_set_phys_footprint_limit is privilege-gated, and spawn jetsam flags do
/// not terminate ordinary macOS processes in the required process class.
/// Consequently production verifier launch fails closed before admission.
struct AuthorizedKernelResidentMemoryEnforcement: Sendable {
  let runID: KernelRunID
  let activationReceiptID: ReceiptID
  let maximumResidentBytes: UInt64

  private init(activation: KernelPostimageVerifierActivationReceipt) {
    runID = activation.runID
    activationReceiptID = activation.id
    maximumResidentBytes = activation.resourceLimits.maximumResidentBytes
  }

  private init(
    externalDependencyActivation:
      ExternalDependencyObservationActivationReceipt
  ) {
    runID = externalDependencyActivation.runID
    activationReceiptID = externalDependencyActivation.id
    maximumResidentBytes =
      externalDependencyActivation.resourceLimits
      .maximumResidentBytes
  }

  func authorizes(
    activation: KernelPostimageVerifierActivationReceipt
  ) -> Bool {
    runID == activation.runID
      && activationReceiptID == activation.id
      && maximumResidentBytes == activation.resourceLimits.maximumResidentBytes
      && maximumResidentBytes > 0
  }

  func authorizes(
    externalDependencyActivation:
      ExternalDependencyObservationActivationReceipt
  ) -> Bool {
    runID == externalDependencyActivation.runID
      && activationReceiptID == externalDependencyActivation.id
      && maximumResidentBytes
        == externalDependencyActivation
        .resourceLimits.maximumResidentBytes
      && maximumResidentBytes > 0
  }

  #if DEBUG
    /// Exercises verifier journal/replay composition without claiming that the
    /// host kernel installed a native memory ceiling. Unavailable in release.
    static func testOnly(
      activation: KernelPostimageVerifierActivationReceipt
    ) -> Self {
      Self(activation: activation)
    }

    static func testOnly(
      externalDependencyActivation:
        ExternalDependencyObservationActivationReceipt
    ) -> Self {
      Self(externalDependencyActivation: externalDependencyActivation)
    }
  #endif
}

/// Explicit result of resolving one activation's physical-memory boundary.
/// Production callers must name either exact authority or the ratified
/// ordinary-macOS veto; omission is no longer overloaded to mean both
/// "unsupported platform" and "resolver was never wired."
enum KernelResidentMemoryEnforcementResolution: Sendable {
  case unavailable(
    KernelResidentMemoryEnforcementUnavailabilityReason
  )
  case authorized(AuthorizedKernelResidentMemoryEnforcement)

  static let ordinaryMacOSUnavailable = Self.unavailable(
    .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit
  )
}

/// One exact executable-recipe containment requirement retained by the
/// pre-apply readiness capability. The full probe digest binds argv, inputs,
/// parser, environment, capture, network, result mapping, and all resource
/// limits; the explicit fields keep the safety-critical ceiling inspectable.
struct KernelPostimageContainmentRequirement: Codable, Hashable, Sendable {
  let evidenceRecipeID: EvidenceRecipeID
  let requirementID: RequirementID
  let verifierKind: RequirementVerifierKind
  let probeDigest: ContentDigest
  let executableContentDigest: ContentDigest
  let maximumResidentBytes: UInt64
  let maximumChildProcesses: UInt64
}

/// Non-serializable proof that one trusted host boundary can install the exact
/// containment route for every ratified verifier/reviewer recipe before its
/// target exec. Ordinary macOS has no Release issuer, so canonical apply must
/// stop before lease admission until a privileged helper or container can
/// issue this capability.
struct AuthorizedKernelPostimageContainmentReadiness: Sendable {
  let runID: KernelRunID
  let integrationTransactionID: IntegrationTransactionID
  let contractID: TaskContractID
  let contractDigest: ContentDigest
  let requirements: [KernelPostimageContainmentRequirement]

  private init?(
    runID: KernelRunID,
    integrationTransactionID: IntegrationTransactionID,
    contract: TaskContract
  ) {
    guard let requirements = Self.requiredRequirements(contract),
      !requirements.isEmpty
    else {
      return nil
    }
    self.runID = runID
    self.integrationTransactionID = integrationTransactionID
    contractID = contract.id
    contractDigest = contract.objectiveDigest
    self.requirements = requirements
  }

  func authorizes(
    runID: KernelRunID,
    integrationTransactionID: IntegrationTransactionID,
    contract: TaskContract
  ) -> Bool {
    guard let expected = Self.requiredRequirements(contract) else { return false }
    return self.runID == runID
      && self.integrationTransactionID == integrationTransactionID
      && contractID == contract.id
      && contractDigest == contract.objectiveDigest
      && requirements == expected
  }

  static func requiredRequirements(
    _ contract: TaskContract
  ) -> [KernelPostimageContainmentRequirement]? {
    guard contract.hasCompleteRequirementEvidenceRecipeProvenance,
      contract.validationIssues().isEmpty,
      let recipes = contract.requirementEvidenceRecipes
    else {
      return nil
    }
    var bindings: [KernelPostimageContainmentRequirement] = []
    for recipe in recipes {
      guard let probe = recipe.executableProbe,
        probe.validationIssues().isEmpty,
        probe.networkPolicy == .disabled,
        probe.resourceLimits.maximumResidentBytes > 0,
        probe.resourceLimits.maximumChildProcesses == 0,
        let probeDigest =
          KernelPostimageVerifierActivationCompiler
          .probeDigest(probe)
      else {
        return nil
      }
      bindings.append(
        KernelPostimageContainmentRequirement(
          evidenceRecipeID: recipe.id,
          requirementID: recipe.requirementID,
          verifierKind: recipe.verifierKind,
          probeDigest: probeDigest,
          executableContentDigest: probe.executableContentDigest,
          maximumResidentBytes:
            probe.resourceLimits.maximumResidentBytes,
          maximumChildProcesses:
            probe.resourceLimits.maximumChildProcesses
        ))
    }
    return bindings.sorted {
      if $0.evidenceRecipeID != $1.evidenceRecipeID {
        return $0.evidenceRecipeID.rawValue < $1.evidenceRecipeID.rawValue
      }
      return $0.requirementID.rawValue < $1.requirementID.rawValue
    }
  }

  #if DEBUG
    /// Test-only route proof. It exercises apply ordering but deliberately does
    /// not claim that the host installed a native physical-memory ceiling.
    static func testOnly(
      runID: KernelRunID,
      integrationTransactionID: IntegrationTransactionID,
      contract: TaskContract
    ) -> Self? {
      Self(
        runID: runID,
        integrationTransactionID: integrationTransactionID,
        contract: contract
      )
    }
  #endif
}

/// Contract-wide counterpart to the activation-exact resolution above. A
/// future privileged helper or VM boundary may return exact authority; the
/// ordinary app returns the typed terminal veto before workspace mutation.
enum KernelPostimageContainmentReadinessResolution: Sendable {
  case unavailable(
    KernelResidentMemoryEnforcementUnavailabilityReason
  )
  case authorized(AuthorizedKernelPostimageContainmentReadiness)

  static let ordinaryMacOSUnavailable = Self.unavailable(
    .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit
  )
}
