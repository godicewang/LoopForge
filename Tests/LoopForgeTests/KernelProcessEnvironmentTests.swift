import XCTest
@testable import LoopForge

final class KernelProcessEnvironmentTests: XCTestCase {
    func testMinimalPolicyConstructsExactCredentialFreeEnvironmentAndReceipt() throws {
        let authorization = try KernelProcessEnvironmentAuthorizer().authorize(
            callerSuppliedEnvironment: [:],
            policy: .minimalKernelAllowlist
        )

        XCTAssertEqual(
            authorization.environment,
            [
                "LANG": "C",
                "LC_ALL": "C",
                "NO_COLOR": "1",
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
            ]
        )
        XCTAssertEqual(authorization.receipt.policy, .minimalKernelAllowlist)
        XCTAssertEqual(
            authorization.receipt.variableNames,
            ["LANG", "LC_ALL", "NO_COLOR", "PATH"]
        )
        XCTAssertEqual(
            authorization.receipt.environmentDigest,
            KernelProcessEnvironmentAuthorizer.environmentDigest(
                authorization.environment
            )
        )
    }

    func testCallerCannotInjectEvenAnAllowlistedOrCredentialVariable() {
        for proposed in [
            ["PATH": "/attacker/bin"],
            ["PRIVATE_API_KEY": "must-not-reach-worker"]
        ] {
            XCTAssertThrowsError(
                try KernelProcessEnvironmentAuthorizer().authorize(
                    callerSuppliedEnvironment: proposed,
                    policy: .minimalKernelAllowlist
                )
            ) { error in
                XCTAssertEqual(
                    error as? KernelProcessEnvironmentAuthorizationError,
                    .callerSuppliedEnvironmentForbidden
                )
            }
        }
    }

    func testDeclaredAllowlistFailsClosedWithoutTypedPerVariableGrant() {
        XCTAssertThrowsError(
            try KernelProcessEnvironmentAuthorizer().authorize(
                callerSuppliedEnvironment: [:],
                policy: .declaredAllowlist
            )
        ) { error in
            XCTAssertEqual(
                error as? KernelProcessEnvironmentAuthorizationError,
                .declaredAllowlistNotMaterialized
            )
        }
    }

    func testEnvironmentDigestIsOrderIndependentAndValueSensitive() {
        let first = ["B": "two=2", "A": "one"]
        let reordered = ["A": "one", "B": "two=2"]
        let changed = ["A": "one", "B": "two=3"]

        XCTAssertEqual(
            KernelProcessEnvironmentAuthorizer.environmentDigest(first),
            KernelProcessEnvironmentAuthorizer.environmentDigest(reordered)
        )
        XCTAssertNotEqual(
            KernelProcessEnvironmentAuthorizer.environmentDigest(first),
            KernelProcessEnvironmentAuthorizer.environmentDigest(changed)
        )
    }
}
