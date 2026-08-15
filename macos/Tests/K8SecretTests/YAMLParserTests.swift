import XCTest
@testable import K8Secret

/// The kubeconfig parser is the app's front door: if it misreads a field, the user
/// gets a connection error that points nowhere near the real cause.
final class YAMLParserTests: XCTestCase {

    private let sampleConfig = """
    apiVersion: v1
    kind: Config
    current-context: prod
    clusters:
    - cluster:
        server: https://prod.example.com:6443
        certificate-authority-data: Q0VSVA==
      name: prod-cluster
    - cluster:
        server: https://staging.example.com:6443
        insecure-skip-tls-verify: true
      name: staging-cluster
    contexts:
    - context:
        cluster: prod-cluster
        user: prod-user
        namespace: payments
      name: prod
    - context:
        cluster: staging-cluster
        user: staging-user
      name: staging
    users:
    - name: prod-user
      user:
        token: abc123
    - name: staging-user
      user:
        exec:
          command: aws
          args:
          - eks
          - get-token
    """

    func testParsesContextsClustersAndUsers() {
        let root = YAMLParser.parse(sampleConfig)

        XCTAssertEqual(root["current-context"]?.stringValue, "prod")
        XCTAssertEqual(root["clusters"]?.sequenceValue?.count, 2)
        XCTAssertEqual(root["contexts"]?.sequenceValue?.count, 2)
        XCTAssertEqual(root["users"]?.sequenceValue?.count, 2)

        let firstCluster = root["clusters"]?.sequenceValue?.first
        XCTAssertEqual(firstCluster?["name"]?.stringValue, "prod-cluster")
        XCTAssertEqual(firstCluster?["cluster"]?["server"]?.stringValue, "https://prod.example.com:6443")
    }

    func testParsesNamespaceOnContext() {
        let root = YAMLParser.parse(sampleConfig)
        let prod = root["contexts"]?.sequenceValue?.first
        XCTAssertEqual(prod?["context"]?["namespace"]?.stringValue, "payments")
    }

    func testParsesExecPluginArgs() {
        let root = YAMLParser.parse(sampleConfig)
        let staging = root["users"]?.sequenceValue?.last
        let exec = staging?["user"]?["exec"]
        XCTAssertEqual(exec?["command"]?.stringValue, "aws")
        XCTAssertEqual(exec?["args"]?.sequenceValue?.compactMap(\.stringValue), ["eks", "get-token"])
    }

    // MARK: - Inline comments

    func testStripsInlineComment() {
        // Regression: the comment used to be concatenated onto the value, producing
        // a server URL of "https://prod.example.com:6443 # production cluster".
        let yaml = "server: https://prod.example.com:6443  # production cluster"
        XCTAssertEqual(YAMLParser.parse(yaml)["server"]?.stringValue, "https://prod.example.com:6443")
    }

    func testKeepsHashThatIsNotAComment() {
        // A '#' only opens a comment when preceded by whitespace.
        let yaml = "token: abc#def"
        XCTAssertEqual(YAMLParser.parse(yaml)["token"]?.stringValue, "abc#def")
    }

    func testKeepsHashInsideQuotes() {
        let yaml = "token: \"pass # word\""
        XCTAssertEqual(YAMLParser.parse(yaml)["token"]?.stringValue, "pass # word")
    }

    func testIgnoresWholeLineComments() {
        let yaml = """
        # leading comment
        current-context: prod
        # trailing comment
        """
        XCTAssertEqual(YAMLParser.parse(yaml)["current-context"]?.stringValue, "prod")
    }

    // MARK: - Quoting

    func testUnquotesValues() {
        XCTAssertEqual(YAMLParser.parse("a: \"quoted\"")["a"]?.stringValue, "quoted")
        XCTAssertEqual(YAMLParser.parse("a: 'single'")["a"]?.stringValue, "single")
    }

    func testColonInsideValueIsNotTreatedAsKeySeparator() {
        let yaml = "server: https://example.com:6443"
        XCTAssertEqual(YAMLParser.parse(yaml)["server"]?.stringValue, "https://example.com:6443")
    }
}
