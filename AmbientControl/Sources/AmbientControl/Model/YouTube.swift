import Foundation

struct YouTubeVideo: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var author: String
    var addedAt: Date

    var thumbnail: URL { URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")! }
}

enum YouTube {
    /// Accepts watch, youtu.be, shorts, embed, live and music links, or a bare 11-character ID.
    static func videoID(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isID(text) { return text }
        guard let comps = URLComponents(string: text.contains("://") ? text : "https://" + text),
              let host = comps.host?.lowercased() else { return nil }
        let parts = comps.path.split(separator: "/").map(String.init)
        var candidate: String?
        if host.hasSuffix("youtu.be") {
            candidate = parts.first
        } else if host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            candidate = comps.queryItems?.first { $0.name == "v" }?.value
            if candidate == nil, let i = parts.firstIndex(where: { ["shorts", "embed", "live", "v"].contains($0) }), i + 1 < parts.count {
                candidate = parts[i + 1]
            }
        }
        guard let c = candidate, isID(c) else { return nil }
        return c
    }

    private static func isID(_ s: String) -> Bool {
        s.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
    }

    /// Title and channel via YouTube's public oEmbed endpoint (no API key).
    static func info(for id: String) async -> (title: String, author: String)? {
        guard let url = URL(string: "https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=\(id)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let title = obj["title"] as? String else { return nil }
        return (title, obj["author_name"] as? String ?? "")
    }
}
