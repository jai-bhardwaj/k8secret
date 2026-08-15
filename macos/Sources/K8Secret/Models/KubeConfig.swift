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
        var username: String?
        var password: String?
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

    // MARK: - Load

    /// Load and merge every file named by `KUBECONFIG`, falling back to `~/.kube/config`.
    ///
    /// `KUBECONFIG` is a colon-separated *list*, and kubectl merges all of it. Reading
    /// only the first entry meant anyone whose contexts are split across files — which
    /// is the normal setup once you have more than a couple of clusters — could see
    /// some of their clusters and not others, with no indication why.
    static func load() throws -> KubeConfig {
        let paths = configPaths()
        guard !paths.isEmpty else { throw K8sError.noConfig }

        var merged: KubeConfig?
        var loadedAny = false
        var firstError: Error?

        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            do {
                let text = try String(contentsOfFile: path, encoding: .utf8)
                let yaml = YAMLParser.parse(text)
                let parsed = try parse(yaml, relativeTo: path)
                loadedAny = true
                merged = merged.map { $0.merging(parsed) } ?? parsed
            } catch {
                // One unreadable file in a KUBECONFIG list shouldn't hide the others.
                if firstError == nil { firstError = error }
            }
        }

        guard let result = merged, loadedAny else {
            if let firstError { throw firstError }
            throw K8sError.noConfig
        }
        return result
    }

    /// kubectl's merge rule: for each named entry the *first* file to define it wins,
    /// and `current-context` comes from the first file that sets one.
    private func merging(_ other: KubeConfig) -> KubeConfig {
        var result = self

        for cluster in other.clusters where !result.clusters.contains(where: { $0.name == cluster.name }) {
            result.clusters.append(cluster)
        }
        for context in other.contexts where !result.contexts.contains(where: { $0.name == context.name }) {
            result.contexts.append(context)
        }
        for user in other.users where !result.users.contains(where: { $0.name == user.name }) {
            result.users.append(user)
        }
        if result.currentContext.isEmpty {
            result.currentContext = other.currentContext
        }
        return result
    }

    private static func configPaths() -> [String] {
        if let env = ProcessInfo.processInfo.environment["KUBECONFIG"], !env.isEmpty {
            let paths = env.components(separatedBy: ":")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { expandTilde($0) }
            if !paths.isEmpty { return paths }
        }
        return [NSHomeDirectory() + "/.kube/config"]
    }

    private static func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return NSHomeDirectory() + String(path.dropFirst())
    }

    /// Read a credential that may be given inline (base64) or as a file path.
    ///
    /// minikube, kind and `kubeadm` all write the file-path form by default, so
    /// supporting only `-data` keys meant those configs silently produced a client
    /// with no CA and no client certificate.
    private static func credential(
        _ map: [String: YAMLValue],
        dataKey: String,
        fileKey: String,
        configPath: String
    ) -> Data? {
        if let encoded = map[dataKey]?.stringValue, let decoded = Data(base64Encoded: encoded) {
            return decoded
        }
        guard let rawPath = map[fileKey]?.stringValue, !rawPath.isEmpty else { return nil }

        // Relative paths in a kubeconfig resolve against the file's own directory.
        var path = expandTilde(rawPath)
        if !path.hasPrefix("/") {
            let dir = (configPath as NSString).deletingLastPathComponent
            path = (dir as NSString).appendingPathComponent(path)
        }
        return FileManager.default.contents(atPath: path)
    }

    private static func parse(_ yaml: YAMLValue, relativeTo configPath: String) throws -> KubeConfig {
        guard let root = yaml.mapValue else {
            throw K8sError.configParse("\((configPath as NSString).lastPathComponent) isn't a valid kubeconfig (expected a YAML mapping at the top level)")
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
                certificateAuthorityData: credential(
                    cluster,
                    dataKey: "certificate-authority-data",
                    fileKey: "certificate-authority",
                    configPath: configPath
                ),
                insecureSkipTLSVerify: cluster["insecure-skip-tls-verify"]?.boolValue ?? false
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

            var exec: ExecConfig?
            if let execMap = user["exec"]?.mapValue {
                // `env` is a sequence of {name, value} pairs. Dropping it broke every
                // plugin that needs configuration passed through the environment —
                // AWS_PROFILE for aws-iam-authenticator being the common one.
                var env: [String: String]?
                if let entries = execMap["env"]?.sequenceValue {
                    var collected: [String: String] = [:]
                    for entry in entries {
                        guard let pair = entry.mapValue,
                              let key = pair["name"]?.stringValue else { continue }
                        collected[key] = pair["value"]?.stringValue ?? ""
                    }
                    if !collected.isEmpty { env = collected }
                }

                exec = ExecConfig(
                    command: execMap["command"]?.stringValue ?? "",
                    args: execMap["args"]?.sequenceValue?.compactMap(\.stringValue) ?? [],
                    env: env
                )
            }

            // `tokenFile` is how in-cluster and projected-token setups supply
            // credentials; it's read fresh so a rotated token is picked up.
            var token = user["token"]?.stringValue
            if token == nil, let tokenFile = user["tokenFile"]?.stringValue, !tokenFile.isEmpty {
                let path = expandTilde(tokenFile)
                token = (try? String(contentsOfFile: path, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            return UserEntry(
                name: name,
                token: token,
                clientCertificateData: credential(
                    user,
                    dataKey: "client-certificate-data",
                    fileKey: "client-certificate",
                    configPath: configPath
                ),
                clientKeyData: credential(
                    user,
                    dataKey: "client-key-data",
                    fileKey: "client-key",
                    configPath: configPath
                ),
                exec: exec,
                username: user["username"]?.stringValue,
                password: user["password"]?.stringValue
            )
        } ?? []

        // An empty parse almost always means the YAML shape wasn't understood.
        // Reporting that beats the downstream "No current-context set", which sent
        // people looking in the wrong place.
        if clusters.isEmpty && contexts.isEmpty && users.isEmpty {
            throw K8sError.configParse("No clusters, contexts or users found in \((configPath as NSString).lastPathComponent)")
        }

        return KubeConfig(
            currentContext: currentCtx,
            clusters: clusters,
            contexts: contexts,
            users: users
        )
    }
}
