import Foundation

enum DiscoveredServerType: String {
    case jellyfin
    case emby
}

struct DiscoveredServer: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let address: String
    let serverType: DiscoveredServerType
}

@MainActor
final class LocalServerDiscovery: ObservableObject {
    @Published var discoveredServers: [DiscoveredServer] = []
    @Published var isScanning = false

    private let maxServers = 15
    private var scanTask: Task<Void, Never>?

    func startDiscovery() {
        guard !isScanning else { return }
        discoveredServers = []
        isScanning = true
        scanTask = Task { await scan() }
    }

    func stopDiscovery() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    private func scan() async {
        let rawResults: [(id: String, name: String, address: String, serverType: DiscoveredServerType)] =
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { [maxServers] in
                    continuation.resume(returning: Self.performBroadcast(maxServers: maxServers))
                }
            }

        var seen = Set<String>()
        for (id, name, address, serverType) in rawResults {
            guard !Task.isCancelled else { break }
            guard !seen.contains(id) else { continue }
            seen.insert(id)

            discoveredServers.append(DiscoveredServer(id: id, name: name, address: address, serverType: serverType))
        }

        isScanning = false
    }

    // MARK: - UDP broadcast via POSIX sockets

    private nonisolated static func performBroadcast(maxServers: Int) -> [(id: String, name: String, address: String, serverType: DiscoveredServerType)] {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return [] }
        defer { Darwin.close(sock) }

        var enable: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))

        var timeout = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var bindAddr = sockaddr_in()
        bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = 0
        bindAddr.sin_addr.s_addr = INADDR_ANY
        let bindOK = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindOK == 0 else { return [] }

        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = UInt16(7359).bigEndian
        dest.sin_addr.s_addr = UInt32(0xFFFF_FFFF)

        var results: [(id: String, name: String, address: String, serverType: DiscoveredServerType)] = []
        var seen = Set<String>()
        var buffer = [UInt8](repeating: 0, count: 4096)

        let queries: [(message: String, type: DiscoveredServerType)] = [
            ("who is JellyfinServer?", .jellyfin),
            ("who is EmbyServer?", .emby)
        ]

        for (message, serverType) in queries {
            let bytes = Array(message.utf8)
            _ = withUnsafePointer(to: &dest) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                    bytes.withUnsafeBufferPointer { buf in
                        sendto(sock, buf.baseAddress, buf.count, 0, sockAddr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }

            let deadline = Date().addingTimeInterval(1.5)

            while Date() < deadline && results.count < maxServers {
                let n = recv(sock, &buffer, buffer.count, 0)
                guard n > 0 else { continue }

                let data = Data(buffer[0..<n])
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let address = json["Address"] as? String,
                      let id = json["Id"] as? String,
                      let name = json["Name"] as? String,
                      !seen.contains(id) else { continue }

                seen.insert(id)
                results.append((id: id, name: name, address: address, serverType: serverType))
            }
        }

        return results
    }
}
