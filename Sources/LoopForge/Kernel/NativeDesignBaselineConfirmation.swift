import Foundation

/// Replayable candidate shown by the native baseline-selection surface. It is
/// deliberately missing both a design-authority receipt and a freeze time:
/// neither can exist until an explicit user action confirms the exact digest.
struct NativeDesignBaselineSelection: Codable, Hashable, Sendable {
    var id: DesignBaselineID
    var contractID: TaskContractID
    var protectedBaselineID: BaselineID
    var requirementIDs: Set<RequirementID>
    var sourceTree: ContentDigest
    var builtArtifact: ContentDigest
    var captureProtocol: ContentDigest
    var designTokenSnapshot: ContentDigest
    var semanticSurfaceManifest: ContentDigest
    var captures: [NativeCaptureReceipt]
    var protectedInvariants: [DesignInvariant]
    var knownDebt: [DesignDebt]
}

enum NativeDesignBaselineAuthoringError: Error, Equatable {
    case invalidRatification
    case invalidEnrollment
    case preparationPredatesEnrollment
    case invalidSelection([String])
    case digestConstructionFailed
}

enum NativeDesignBaselineConfirmationError: Error, Equatable {
    case displayedSelectionChanged
    case userIdentityMismatch
    case confirmationPredatesDisplay
    case alreadyConfirmed
    case digestConstructionFailed
}

/// Non-Codable display state. Its private initializer prevents a decoded
/// selection from bypassing exact ratification, enrollment, and protected
/// artifact validation before it reaches the native confirmation issuer.
struct NativeDesignBaselineConfirmationDraft: Sendable {
    let selection: NativeDesignBaselineSelection
    let selectionDigest: ContentDigest
    let runID: KernelRunID
    let contractCandidateDigest: ContentDigest
    let contractRatificationReceiptID: ReceiptID
    let enrollmentJournalFrameDigest: ContentDigest
    let confirmingUserID: ActorID
    let confirmingUserLineageDigest: ContentDigest
    let preparedAt: Date

    fileprivate init(
        selection: NativeDesignBaselineSelection,
        selectionDigest: ContentDigest,
        runID: KernelRunID,
        contractCandidateDigest: ContentDigest,
        contractRatificationReceiptID: ReceiptID,
        enrollmentJournalFrameDigest: ContentDigest,
        confirmingUserID: ActorID,
        confirmingUserLineageDigest: ContentDigest,
        preparedAt: Date
    ) {
        self.selection = selection
        self.selectionDigest = selectionDigest
        self.runID = runID
        self.contractCandidateDigest = contractCandidateDigest
        self.contractRatificationReceiptID = contractRatificationReceiptID
        self.enrollmentJournalFrameDigest = enrollmentJournalFrameDigest
        self.confirmingUserID = confirmingUserID
        self.confirmingUserLineageDigest = confirmingUserLineageDigest
        self.preparedAt = preparedAt
    }
}

/// Non-serializable authority for freezing one immutable product/design
/// baseline in one exact enrolled run. Durable baseline bytes and receipts are
/// replayable evidence; only the native issuer below can manufacture this live
/// command capability in production.
struct AuthorizedKernelDesignBaseline: Sendable {
    let baseline: DesignBaselineBundle
    let runID: KernelRunID
    let contractRatificationReceiptID: ReceiptID
    let enrollmentJournalFrameDigest: ContentDigest
    let selectionDigest: ContentDigest
    let confirmingUser: ActorIdentity

    fileprivate init(
        baseline: DesignBaselineBundle,
        runID: KernelRunID,
        contractRatificationReceiptID: ReceiptID,
        enrollmentJournalFrameDigest: ContentDigest,
        selectionDigest: ContentDigest,
        confirmingUser: ActorIdentity
    ) {
        self.baseline = baseline
        self.runID = runID
        self.contractRatificationReceiptID = contractRatificationReceiptID
        self.enrollmentJournalFrameDigest = enrollmentJournalFrameDigest
        self.selectionDigest = selectionDigest
        self.confirmingUser = confirmingUser
    }

#if DEBUG
    static func testOnly(
        baseline: DesignBaselineBundle
    ) -> AuthorizedKernelDesignBaseline {
        AuthorizedKernelDesignBaseline(
            baseline: baseline,
            runID: KernelRunID("test-only-unbound-run"),
            contractRatificationReceiptID:
                ReceiptID("test-only-unbound-ratification"),
            enrollmentJournalFrameDigest:
                ContentDigest("test-only-unbound-enrollment-frame"),
            selectionDigest: ContentDigest("test-only-unbound-selection"),
            confirmingUser: baseline.authority.authority
        )
    }
#endif
}

/// Pure preparation boundary for the native baseline-selection screen. It
/// binds the displayed selection to the exact non-forgeable ratified contract
/// and the exact enrollment frame that will later receive the freeze command.
enum NativeDesignBaselineAuthor {
    static func prepare(
        selection: NativeDesignBaselineSelection,
        ratifiedContract: RatifiedTaskContract,
        enrollment: KernelRunEnrollmentReceipt,
        preparedAt: Date
    ) -> Result<
        NativeDesignBaselineConfirmationDraft,
        NativeDesignBaselineAuthoringError
    > {
        let contract = ratifiedContract.contract
        let ratification = ratifiedContract.receipt
        guard ratification.contractID == contract.id,
              ratification.executionEligibility == .contractAuthorityCeiling,
              ratification.blockingAmbiguityIDs.isEmpty,
              !ratification.candidateDigest.rawValue.isEmpty,
              !ratification.receiptID.rawValue.isEmpty,
              !ratification.userActorID.rawValue.isEmpty,
              !ratification.userActorLineageDigest.rawValue.isEmpty,
              contract.validationIssues().isEmpty else {
            return .failure(.invalidRatification)
        }

        guard let evidence = enrollment.registration.enrollmentEvidence,
              evidence.authority == .ratifiedUserContract,
              enrollment.schemaVersion == 1,
              enrollment.runID == enrollment.registration.runID,
              enrollment.contractID == contract.id,
              enrollment.contractRevision == ratification.revision,
              enrollment.candidateDigest == ratification.candidateDigest,
              enrollment.ratificationReceiptID == ratification.receiptID,
              enrollment.userActorID == ratification.userActorID,
              evidence.runID == enrollment.runID,
              evidence.contractID == contract.id,
              evidence.contractRevision == ratification.revision,
              evidence.candidateDigest == ratification.candidateDigest,
              evidence.ratificationReceiptID == ratification.receiptID,
              evidence.userActorID == ratification.userActorID,
              evidence.userActorLineageDigest ==
                ratification.userActorLineageDigest,
              evidence.journalFrameDigest ==
                enrollment.journalTransaction.frameDigest,
              evidence.journalEndingSequence ==
                enrollment.journalTransaction.endingSequence else {
            return .failure(.invalidEnrollment)
        }
        guard preparedAt.timeIntervalSince1970.isFinite,
              preparedAt >= ratification.confirmedAt,
              preparedAt >= enrollment.registration.registeredAt else {
            return .failure(.preparationPredatesEnrollment)
        }

        let issues = validationIssues(
            selection: selection,
            contract: contract,
            preparedAt: preparedAt
        )
        guard issues.isEmpty else {
            return .failure(.invalidSelection(issues))
        }
        guard let digest = selectionDigest(selection) else {
            return .failure(.digestConstructionFailed)
        }
        return .success(NativeDesignBaselineConfirmationDraft(
            selection: selection,
            selectionDigest: digest,
            runID: enrollment.runID,
            contractCandidateDigest: ratification.candidateDigest,
            contractRatificationReceiptID: ratification.receiptID,
            enrollmentJournalFrameDigest:
                enrollment.journalTransaction.frameDigest,
            confirmingUserID: ratification.userActorID,
            confirmingUserLineageDigest:
                ratification.userActorLineageDigest,
            preparedAt: preparedAt
        ))
    }

    static func selectionDigest(
        _ selection: NativeDesignBaselineSelection
    ) -> ContentDigest? {
        let material = NativeDesignBaselineDigestMaterial(
            id: selection.id,
            contractID: selection.contractID,
            protectedBaselineID: selection.protectedBaselineID,
            requirementIDs: selection.requirementIDs.sorted {
                $0.rawValue < $1.rawValue
            },
            sourceTree: selection.sourceTree,
            builtArtifact: selection.builtArtifact,
            captureProtocol: selection.captureProtocol,
            designTokenSnapshot: selection.designTokenSnapshot,
            semanticSurfaceManifest: selection.semanticSurfaceManifest,
            captures: selection.captures.sorted {
                ($0.cellID.rawValue, $0.id.rawValue)
                    < ($1.cellID.rawValue, $1.id.rawValue)
            },
            protectedInvariants: selection.protectedInvariants.map {
                NativeDesignInvariantDigestMaterial(
                    id: $0.id,
                    dimension: $0.dimension,
                    cellIDs: $0.cellIDs.sorted {
                        $0.rawValue < $1.rawValue
                    }
                )
            }.sorted { ($0.id, $0.dimension.rawValue) < ($1.id, $1.dimension.rawValue) },
            knownDebt: selection.knownDebt.map {
                NativeDesignDebtDigestMaterial(
                    id: $0.id,
                    dimension: $0.dimension,
                    cellIDs: $0.cellIDs.sorted {
                        $0.rawValue < $1.rawValue
                    },
                    baselineSeverity: $0.baselineSeverity,
                    maximumInterimSeverity: $0.maximumInterimSeverity,
                    direction: $0.direction,
                    closureRequired: $0.closureRequired,
                    evidenceDigest: $0.evidenceDigest
                )
            }.sorted { $0.id.rawValue < $1.id.rawValue }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(material) else { return nil }
        return TaskContractCompiler.digest(data)
    }

    private static func validationIssues(
        selection: NativeDesignBaselineSelection,
        contract: TaskContract,
        preparedAt: Date
    ) -> [String] {
        var issues: [String] = []
        if !validIdentity(selection.id.rawValue)
            || selection.contractID != contract.id
            || !validIdentity(selection.protectedBaselineID.rawValue) {
            issues.append("baseline identities must be complete and contract-bound")
        }
        let knownRequirements = Set(contract.requirements.map(\.id))
        if selection.requirementIDs.isEmpty
            || !selection.requirementIDs.isSubset(of: knownRequirements) {
            issues.append("baseline requirements must be a non-empty contract subset")
        }
        let protectedReference = contract.protectedBaselines.first {
            $0.id == selection.protectedBaselineID
        }
        if protectedReference?.preservationRequired != true
            || protectedReference?.artifactDigest != selection.builtArtifact {
            issues.append("baseline artifact must match a preservation-required contract reference")
        }
        if !validSHA256(selection.sourceTree)
            || !validSHA256(selection.builtArtifact)
            || !validSHA256(selection.captureProtocol)
            || !validSHA256(selection.designTokenSnapshot)
            || !validSHA256(selection.semanticSurfaceManifest) {
            issues.append("baseline content identities must be exact lowercase SHA-256")
        }

        let captureIDs = selection.captures.map(\.id)
        let captureCells = selection.captures.map(\.cellID)
        if selection.captures.isEmpty
            || Set(captureIDs).count != captureIDs.count
            || Set(captureCells).count != captureCells.count {
            issues.append("native captures must be non-empty and unique by receipt and visual cell")
        }
        if selection.captures.contains(where: { capture in
            !capture.isComplete
                || capture.sourceTree != selection.sourceTree
                || capture.builtArtifact != selection.builtArtifact
                || capture.captureProtocol != selection.captureProtocol
                || capture.capturedAt > preparedAt
                || !capture.capturedAt.timeIntervalSince1970.isFinite
                || !validSHA256(capture.traits.fixtureDigest)
                || !validSHA256(capture.imageDigest)
                || !validSHA256(capture.accessibilityTreeDigest)
                || !validSHA256(capture.navigationRecipeDigest)
                || capture.componentBoundaryDigest.map(validSHA256) == false
                || capture.designTokenTraceDigest.map(validSHA256) == false
                || !validIdentity(capture.harnessIdentity)
        }) {
            issues.append("native capture provenance must be complete, exact, and pre-confirmation")
        }

        let invariantIDs = selection.protectedInvariants.map(\.id)
        let invariantCells = Set(selection.protectedInvariants.flatMap(\.cellIDs))
        if selection.protectedInvariants.isEmpty
            || invariantIDs.contains(where: { !validIdentity($0) })
            || Set(invariantIDs).count != invariantIDs.count
            || invariantCells.isEmpty
            || !invariantCells.isSubset(of: Set(captureCells))
            || selection.protectedInvariants.contains(where: { $0.cellIDs.isEmpty }) {
            issues.append("protected invariants must be unique and covered by native captures")
        }

        let debtIDs = selection.knownDebt.map(\.id)
        if Set(debtIDs).count != debtIDs.count
            || selection.knownDebt.contains(where: { debt in
                !validIdentity(debt.id.rawValue)
                    || debt.cellIDs.isEmpty
                    || !debt.cellIDs.isSubset(of: invariantCells)
                    || !debt.baselineSeverity.isFinite
                    || debt.baselineSeverity < 0
                    || !debt.maximumInterimSeverity.isFinite
                    || debt.maximumInterimSeverity < 0
                    || !validSHA256(debt.evidenceDigest)
            }) {
            issues.append("known design debt must be finite, unique, evidenced, and invariant-bound")
        }
        return issues
    }

    private static func validSHA256(_ digest: ContentDigest) -> Bool {
        digest.rawValue.utf8.count == 64
            && digest.rawValue.utf8.allSatisfy {
                (48...57).contains($0) || (97...102).contains($0)
            }
    }

    private static func validIdentity(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 512
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }
}

/// The only production issuer of `AuthorizedKernelDesignBaseline`. Callers
/// must invoke this method from an explicit native user action with the exact
/// digest displayed beside the captures and protected-artifact identity.
@MainActor
final class NativeDesignBaselineConfirmationIssuer {
    private struct ConfirmationKey: Hashable {
        var runID: KernelRunID
        var baselineID: DesignBaselineID
        var selectionDigest: ContentDigest
    }

    private var confirmedSelections: Set<ConfirmationKey> = []

    func confirmFromNativeUserAction(
        _ draft: NativeDesignBaselineConfirmationDraft,
        displayedSelectionDigest: ContentDigest,
        userActor: ActorIdentity,
        confirmedAt: Date
    ) -> Result<AuthorizedKernelDesignBaseline, NativeDesignBaselineConfirmationError> {
        guard displayedSelectionDigest == draft.selectionDigest,
              NativeDesignBaselineAuthor.selectionDigest(draft.selection) ==
                draft.selectionDigest else {
            return .failure(.displayedSelectionChanged)
        }
        guard userActor.id == draft.confirmingUserID,
              userActor.lineageDigest == draft.confirmingUserLineageDigest,
              !userActor.role.isEmpty else {
            return .failure(.userIdentityMismatch)
        }
        guard confirmedAt.timeIntervalSince1970.isFinite,
              confirmedAt >= draft.preparedAt else {
            return .failure(.confirmationPredatesDisplay)
        }
        let key = ConfirmationKey(
            runID: draft.runID,
            baselineID: draft.selection.id,
            selectionDigest: draft.selectionDigest
        )
        guard !confirmedSelections.contains(key) else {
            return .failure(.alreadyConfirmed)
        }

        let nonce = UUID().uuidString
        let receiptMaterial = Data([
            draft.runID.rawValue,
            draft.contractCandidateDigest.rawValue,
            draft.contractRatificationReceiptID.rawValue,
            draft.enrollmentJournalFrameDigest.rawValue,
            draft.selection.id.rawValue,
            draft.selectionDigest.rawValue,
            userActor.id.rawValue,
            userActor.lineageDigest.rawValue,
            String(confirmedAt.timeIntervalSinceReferenceDate.bitPattern),
            nonce
        ].joined(separator: "\u{1f}").utf8)
        let receiptDigest = TaskContractCompiler.digest(receiptMaterial)
        guard !receiptDigest.rawValue.isEmpty else {
            return .failure(.digestConstructionFailed)
        }
        let authority = DesignAuthorityReceipt(
            id: ReceiptID("design-baseline-confirmation-\(receiptDigest.rawValue)"),
            baselineID: draft.selection.id,
            authority: userActor,
            authorityRole: "productDesignAuthority",
            issuedAt: confirmedAt
        )
        let selection = draft.selection
        let baseline = DesignBaselineBundle(
            id: selection.id,
            contractID: selection.contractID,
            protectedBaselineID: selection.protectedBaselineID,
            requirementIDs: selection.requirementIDs,
            sourceTree: selection.sourceTree,
            builtArtifact: selection.builtArtifact,
            captureProtocol: selection.captureProtocol,
            designTokenSnapshot: selection.designTokenSnapshot,
            semanticSurfaceManifest: selection.semanticSurfaceManifest,
            captures: selection.captures,
            protectedInvariants: selection.protectedInvariants,
            knownDebt: selection.knownDebt,
            authority: authority,
            frozenAt: confirmedAt
        )
        confirmedSelections.insert(key)
        return .success(AuthorizedKernelDesignBaseline(
            baseline: baseline,
            runID: draft.runID,
            contractRatificationReceiptID:
                draft.contractRatificationReceiptID,
            enrollmentJournalFrameDigest:
                draft.enrollmentJournalFrameDigest,
            selectionDigest: draft.selectionDigest,
            confirmingUser: userActor
        ))
    }
}

private struct NativeDesignBaselineDigestMaterial: Codable {
    var id: DesignBaselineID
    var contractID: TaskContractID
    var protectedBaselineID: BaselineID
    var requirementIDs: [RequirementID]
    var sourceTree: ContentDigest
    var builtArtifact: ContentDigest
    var captureProtocol: ContentDigest
    var designTokenSnapshot: ContentDigest
    var semanticSurfaceManifest: ContentDigest
    var captures: [NativeCaptureReceipt]
    var protectedInvariants: [NativeDesignInvariantDigestMaterial]
    var knownDebt: [NativeDesignDebtDigestMaterial]
}

private struct NativeDesignInvariantDigestMaterial: Codable {
    var id: String
    var dimension: VisualGateDimension
    var cellIDs: [VisualCellID]
}

private struct NativeDesignDebtDigestMaterial: Codable {
    var id: DesignDebtID
    var dimension: VisualGateDimension
    var cellIDs: [VisualCellID]
    var baselineSeverity: Double
    var maximumInterimSeverity: Double
    var direction: DesignDebtDirection
    var closureRequired: Bool
    var evidenceDigest: ContentDigest
}
