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
    /// A credential given either inline or as a file.
    ///
    /// Throws when the file is named but cannot be read, rather than returning
    /// nil. Those two outcomes are not the same thing and treating them alike is
    /// what made this class of failure so hard to place: a path is a property of
    /// the machine, so a kubeconfig copied between Macs — or written by a tool
    /// whose certificates were later cleaned up — resolves on one and not the
    /// other. Silently, the cluster then looked like it had configured no CA and
    /// no client certificate at all, and the connection failed several layers
    /// later as a TLS error that named neither the file nor the setting.
    ///
    /// Reporting it is also the safe direction. This app deliberately refuses to
    /// fall back to the system trust store when a configured CA cannot be
    /// parsed, so that it never trusts a certificate the user did not ask for;
    /// returning nil here walked around that guarantee.
    private static func credential(
        _ map: [String: YAMLValue],
        dataKey: String,
        fileKey: String,
        configPath: String,
        context: String
    ) throws -> Data? {
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

        guard let data = FileManager.default.contents(atPath: path) else {
            let exists = FileManager.default.fileExists(atPath: path)
            throw K8sError.configParse(
                "\(context) sets \(fileKey): \(rawPath), but that file "
                + (exists ? "could not be read — check its permissions."
                          : "does not exist at \(path).")
                + " Kubeconfig paths point at this machine, so a config copied from "
                + "another one will name files that aren't here."
            )
        }
        return data
    }

    private static func parse(_ yaml: YAMLValue, relativeTo configPath: String) throws -> KubeConfig {
        guard let root = yaml.mapValue else {
            throw K8sError.configParse("\((configPath as NSString).lastPathComponent) isn't a valid kubeconfig (expected a YAML mapping at the top level)")
        }

        let currentCtx = root["current-context"]?.stringValue ?? ""

        var clusters: [ClusterEntry] = []
        for item in root["clusters"]?.sequenceValue ?? [] {
            guard let m = item.mapValue,
                  let name = m["name"]?.stringValue,
                  let cluster = m["cluster"]?.mapValue,
                  let server = cluster["server"]?.stringValue else { continue }
            clusters.append(ClusterEntry(
                name: name,
                server: server,
                certificateAuthorityData: try credential(
                    cluster,
                    dataKey: "certificate-authority-data",
                    fileKey: "certificate-authority",
                    configPath: configPath,
                    context: "Cluster \"\(name)\""
                ),
                insecureSkipTLSVerify: cluster["insecure-skip-tls-verify"]?.boolValue ?? false
            ))
        }

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

        var users: [UserEntry] = []
        for item in root["users"]?.sequenceValue ?? [] {
            guard let m = item.mapValue,
                  let name = m["name"]?.stringValue,
                  let user = m["user"]?.mapValue else { continue }

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
                // Same rule as the certificate files: named but unreadable is an
                // error, not an absence. Swallowing it produced a 401 that looked
                // like the user's credentials had been rejected, when in fact none
                // were ever sent.
                guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
                    throw K8sError.configParse(
                        "User \"\(name)\" sets tokenFile: \(tokenFile), but that file "
                        + (FileManager.default.fileExists(atPath: path)
                           ? "could not be read — check its permissions."
                           : "does not exist at \(path).")
                    )
                }
                token = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            users.append(UserEntry(
                name: name,
                token: token,
                clientCertificateData: try credential(
                    user,
                    dataKey: "client-certificate-data",
                    fileKey: "client-certificate",
                    configPath: configPath,
                    context: "User \"\(name)\""
                ),
                clientKeyData: try credential(
                    user,
                    dataKey: "client-key-data",
                    fileKey: "client-key",
                    configPath: configPath,
                    context: "User \"\(name)\""
                ),
                exec: exec,
                username: user["username"]?.stringValue,
                password: user["password"]?.stringValue
            ))
        }

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
