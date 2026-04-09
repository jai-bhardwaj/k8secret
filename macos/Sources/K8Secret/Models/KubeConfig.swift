import Foundation
import Security

struct KubeConfig {
    var currentContext: String
    var clusters: [ClusterEntry]
    var contexts: [ContextEntry]
    var users: [UserEntry]

    struct ClusterEntry {
        var name: String
        var server: String
        var certificateAuthorityData: Data?
        var insecureSkipTLSVerify: Bool
    }

    struct ContextEntry {
        var name: String
        var cluster: String
        var user: String
        var namespace: String?
    }

    struct UserEntry {
        var name: String
        var token: String?
        var clientCertificateData: Data?
        var clientKeyData: Data?
        var exec: ExecConfig?
    }

    struct ExecConfig {
        var command: String
        var args: [String]
        var env: [String: String]?
    }

    /// Resolve the active cluster + user for the current context.
    func activeCluster() -> ClusterEntry? {
        guard let ctx = contexts.first(where: { $0.name == currentContext }) else { return nil }
        return clusters.first(where: { $0.name == ctx.cluster })
    }

    func activeUser() -> UserEntry? {
        guard let ctx = contexts.first(where: { $0.name == currentContext }) else { return nil }
        return users.first(where: { $0.name == ctx.user })
    }

    func activeNamespace() -> String? {
        contexts.first(where: { $0.name == currentContext })?.namespace
    }

    // MARK: - Load from ~/.kube/config

    static func load() throws -> KubeConfig {
        let path = kubeConfigPath()
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let yaml = YAMLParser.parse(text)
        return try parse(yaml)
    }

    private static func kubeConfigPath() -> String {
        if let env = ProcessInfo.processInfo.environment["KUBECONFIG"], !env.isEmpty {
            return env.components(separatedBy: ":").first ?? env
        }
        return NSHomeDirectory() + "/.kube/config"
    }

    private static func parse(_ yaml: YAMLValue) throws -> KubeConfig {
        guard let root = yaml.mapValue else {
            throw K8sError.configParse("Invalid kubeconfig format")
        }

        let currentCtx = root["current-context"]?.stringValue ?? ""

        let clusters: [ClusterEntry] = root["clusters"]?.sequenceValue?.compactMap { item in
            guard let m = item.mapValue,
                  let name = m["name"]?.stringValue,
                  let cluster = m["cluster"]?.mapValue,
                  let server = cluster["server"]?.stringValue else { return nil }
            return ClusterEntry(
                name: name,
                server: server,
                certificateAuthorityData: cluster["certificate-authority-data"]?.stringValue.flatMap { Data(base64Encoded: $0) },
                insecureSkipTLSVerify: cluster["insecure-skip-tls-verify"]?.stringValue == "true"
            )
        } ?? []

        let contexts: [ContextEntry] = root["contexts"]?.sequenceValue?.compactMap { item in
            guard let m = item.mapValue,
                  let name = m["name"]?.stringValue,
                  let ctx = m["context"]?.mapValue,
                  let cluster = ctx["cluster"]?.stringValue,
                  let user = ctx["user"]?.stringValue else { return nil }
            return ContextEntry(
                name: name,
                cluster: cluster,
                user: user,
                namespace: ctx["namespace"]?.stringValue
            )
        } ?? []

        let users: [UserEntry] = root["users"]?.sequenceValue?.compactMap { item in
            guard let m = item.mapValue,
                  let name = m["name"]?.stringValue,
                  let user = m["user"]?.mapValue else { return nil }

            var exec: ExecConfig? = nil
            if let execMap = user["exec"]?.mapValue {
                exec = ExecConfig(
                    command: execMap["command"]?.stringValue ?? "",
                    args: execMap["args"]?.sequenceValue?.compactMap(\.stringValue) ?? [],
                    env: nil
                )
            }

            return UserEntry(
                name: name,
                token: user["token"]?.stringValue,
                clientCertificateData: user["client-certificate-data"]?.stringValue.flatMap { Data(base64Encoded: $0) },
                clientKeyData: user["client-key-data"]?.stringValue.flatMap { Data(base64Encoded: $0) },
                exec: exec
            )
        } ?? []

        return KubeConfig(
            currentContext: currentCtx,
            clusters: clusters,
            contexts: contexts,
            users: users
        )
    }
}
