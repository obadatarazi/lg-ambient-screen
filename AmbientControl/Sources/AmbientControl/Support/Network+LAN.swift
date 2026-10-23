import Darwin
import Foundation

enum LAN {
    /// First private IPv4 address on an active interface (Wi-Fi first).
    static func ipv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var found: [String: String] = [:]
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  (ifa.ifa_flags & UInt32(IFF_UP)) != 0,
                  (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                found[String(cString: ifa.ifa_name)] = String(cString: host)
            }
        }
        for name in ["en0", "en1", "en2"] { if let ip = found[name] { return ip } }
        return found.values.first { $0.hasPrefix("192.168.") || $0.hasPrefix("10.") || $0.hasPrefix("172.") }
    }
}
