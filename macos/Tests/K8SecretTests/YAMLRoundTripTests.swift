import XCTest
@testable import K8Secret

/// The resource editor reads a live object, renders it as YAML, takes the user's
/// edits, and `PUT`s the result back. Anything the round trip changes on its own is
/// an unrequested mutation of a running workload — so these tests assert the
/// pipeline is faithful, not merely that it runs.
final class YAMLRoundTripTests: XCTestCase {

    /// JSON → YAML → parsed → JSON, exactly as `applyRawYAML` does it.
    private func roundTrip(_ object: [String: Any]) -> [String: Any]? {
        let yaml = YAMLSerializer.serialize(object)
        return YAMLParser.parse(yaml).jsonObject as? [String: Any]
    }

    // MARK: - Scalar typing

    func testIntegersSurviveAsIntegers() {
        // The bug that made the editor unusable: `replicas: 3` came back as "3",
        // and the API server rejects a string where it wants an integer.
        let out = roundTrip(["apiVersion": "apps/v1", "kind": "Deployment", "replicas": 3])
        XCTAssertEqual(out?["replicas"] as? Int, 3)
        XCTAssertNil(out?["replicas"] as? String)
    }

    func testBooleansSurviveAsBooleans() {
        let out = roundTrip(["enabled": true, "disabled": false])
        XCTAssertEqual(out?["enabled"] as? Bool, true)
        XCTAssertEqual(out?["disabled"] as? Bool, false)
    }

    func testDoublesSurvive() {
        let out = roundTrip(["ratio": 0.5])
        XCTAssertEqual(out?["ratio"] as? Double, 0.5)
    }

    func testNullSurvives() {
        let out = roundTrip(["cleared": NSNull()])
        XCTAssertTrue(out?["cleared"] is NSNull)
    }

    func testNegativeAndZeroIntegers() {
        let out = roundTrip(["zero": 0, "negative": -5])
        XCTAssertEqual(out?["zero"] as? Int, 0)
        XCTAssertEqual(out?["negative"] as? Int, -5)
    }

    // MARK: - Strings that look like other types

    func testNumericStringStaysAString() {
        // An image tag or a port written as a string must not become a number.
        let out = roundTrip(["version": "3", "port": "8080"])
        XCTAssertEqual(out?["version"] as? String, "3")
        XCTAssertEqual(out?["port"] as? String, "8080")
    }

    func testBooleanLookingStringStaysAString() {
        let out = roundTrip(["value": "true", "other": "no"])
        XCTAssertEqual(out?["value"] as? String, "true")
        XCTAssertEqual(out?["other"] as? String, "no")
    }

    func testLeadingZeroStaysAString() {
        // Zero-padded values are identifiers, not numbers.
        let out = roundTrip(["code": "007"])
        XCTAssertEqual(out?["code"] as? String, "007")
    }

    func testColonBearingStringSurvives() {
        let out = roundTrip(["image": "registry.io/team/app:1.2.3"])
        XCTAssertEqual(out?["image"] as? String, "registry.io/team/app:1.2.3")
    }

    // MARK: - Structure

    func testNestedMapsAndSequences() {
        let input: [String: Any] = [
            "apiVersion": "apps/v1",
            "kind": "Deployment",
            "spec": [
                "replicas": 2,
                "template": [
                    "spec": [
                        "containers": [
                            ["name": "app", "image": "app:1", "ports": [["containerPort": 8080]]]
                        ]
                    ]
                ]
            ]
        ]

        let out = roundTrip(input)
        let spec = out?["spec"] as? [String: Any]
        XCTAssertEqual(spec?["replicas"] as? Int, 2)

        let containers = ((spec?["template"] as? [String: Any])?["spec"] as? [String: Any])?["containers"] as? [Any]
        let first = containers?.first as? [String: Any]
        XCTAssertEqual(first?["name"] as? String, "app")
        XCTAssertEqual(first?["image"] as? String, "app:1")

        let ports = first?["ports"] as? [Any]
        XCTAssertEqual((ports?.first as? [String: Any])?["containerPort"] as? Int, 8080)
    }

    func testLabelsMapSurvives() {
        let out = roundTrip(["metadata": ["labels": ["app": "api", "tier": "backend"]]])
        let labels = (out?["metadata"] as? [String: Any])?["labels"] as? [String: Any]
        XCTAssertEqual(labels?["app"] as? String, "api")
        XCTAssertEqual(labels?["tier"] as? String, "backend")
    }

    // MARK: - Block scalars

    func testMultiLineValueSurvivesExactly() {
        // Serialized as a `|-` block; without block-scalar reading the parser used
        // to return the header instead of the content.
        let pem = "-----BEGIN CERTIFICATE-----\nMIIB\nAgIC\n-----END CERTIFICATE-----"
        let out = roundTrip(["ca.crt": pem])
        XCTAssertEqual(out?["ca.crt"] as? String, pem)
    }

    func testMultiLineValueWithTrailingNewlineSurvives() {
        let text = "line one\nline two\n"
        let out = roundTrip(["config": text])
        XCTAssertEqual(out?["config"] as? String, text)
    }

    func testNestedMultiLineValueKeepsItsIndentation() {
        // The block body used to be hardcoded to two spaces regardless of depth,
        // so a nested multi-line value parsed back with the wrong structure.
        let out = roundTrip(["data": ["nested": ["cert": "a\nb\nc"]]])
        let nested = (out?["data"] as? [String: Any])?["nested"] as? [String: Any]
        XCTAssertEqual(nested?["cert"] as? String, "a\nb\nc")
    }

    func testLiteralBlockIsReadBack() {
        let yaml = """
        data:
          script: |
            #!/bin/sh
            echo hello
        """
        let script = YAMLParser.parse(yaml)["data"]?["script"]?.stringValue
        XCTAssertEqual(script, "#!/bin/sh\necho hello\n")
    }

    func testStrippedBlockDropsTrailingNewline() {
        let yaml = """
        data:
          script: |-
            echo hello
        """
        XCTAssertEqual(YAMLParser.parse(yaml)["data"]?["script"]?.stringValue, "echo hello")
    }

    // MARK: - Validation refuses what it can't represent

    func testValidatorAcceptsOrdinaryResources() {
        let yaml = """
        apiVersion: apps/v1
        kind: Deployment
        spec:
          replicas: 3
        """
        XCTAssertTrue(YAMLParser.validate(yaml).isEmpty)
    }

    func testValidatorRejectsAnchors() {
        let yaml = """
        base: &defaults
          replicas: 1
        """
        XCTAssertFalse(YAMLParser.validate(yaml).isEmpty)
    }

    func testValidatorRejectsFlowCollections() {
        XCTAssertFalse(YAMLParser.validate("args: [a, b]").isEmpty)
        XCTAssertFalse(YAMLParser.validate("meta: {x: 1}").isEmpty)
    }

    func testValidatorRejectsMultipleDocuments() {
        let yaml = """
        ---
        kind: A
        ---
        kind: B
        """
        XCTAssertFalse(YAMLParser.validate(yaml).isEmpty)
    }

    func testValidatorIgnoresHashInsideComments() {
        XCTAssertTrue(YAMLParser.validate("# args: [a, b]\nkind: Pod").isEmpty)
    }
}
