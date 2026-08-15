import Foundation

struct FeedItem: Sendable, Identifiable {
    var guid: String
    var title: String
    var summary: String
    var publishedAt: Date
    var audioURL: URL
    var pageURL: URL?
    var duration: Double

    var id: String { guid }
}

enum FeedError: LocalizedError {
    case badResponse(Int)
    case parseFailed
    case empty

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): "피드를 불러오지 못했습니다 (\(code))"
        case .parseFailed: "피드 형식을 읽지 못했습니다"
        case .empty: "피드에 에피소드가 없습니다"
        }
    }
}

/// BBC가 재사용 조건을 명시해 공개한 공식 피드. 오디오 링크는 여기서만 가져온다.
struct RSSFeedService {
    static let feedURL = URL(string: "https://feeds.bbci.co.uk/learningenglish/english/features/6-minute-english/rss")!

    var url: URL = RSSFeedService.feedURL

    func fetch() async throws -> [FeedItem] {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FeedError.badResponse(http.statusCode)
        }

        let items = RSSParser().parse(data)
        guard !items.isEmpty else { throw FeedError.empty }
        return items
    }
}

final class RSSParser: NSObject, XMLParserDelegate {
    private var items: [FeedItem] = []
    private var inItem = false
    private var text = ""

    private var title = ""
    private var summary = ""
    private var pubDate = ""
    private var link = ""
    private var guid = ""
    private var duration = ""
    private var enclosureURL: String?
    private var mediaURL: String?

    func parse(_ data: Data) -> [FeedItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.parse()
        return items
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        text = ""

        switch elementName {
        case "item":
            inItem = true
            title = ""; summary = ""; pubDate = ""; link = ""; guid = ""; duration = ""
            enclosureURL = nil; mediaURL = nil

        case "enclosure" where inItem:
            let type = attributeDict["type"] ?? ""
            if type.hasPrefix("audio") || (attributeDict["url"] ?? "").hasSuffix(".mp3") {
                enclosureURL = attributeDict["url"]
            }

        case "media:content" where inItem:
            let type = attributeDict["type"] ?? ""
            if type.hasPrefix("audio") || (attributeDict["url"] ?? "").hasSuffix(".mp3") {
                mediaURL = attributeDict["url"]
                if let seconds = attributeDict["duration"], duration.isEmpty {
                    duration = seconds
                }
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer { text = "" }
        guard inItem else { return }

        let value = text.trimmed

        switch elementName {
        case "title": title = value
        case "description", "itunes:summary": if summary.isEmpty { summary = value.strippingHTML }
        case "pubDate": pubDate = value
        case "link": link = value
        case "guid": guid = value
        case "itunes:duration": if duration.isEmpty { duration = value }

        case "item":
            inItem = false
            guard let audio = (enclosureURL ?? mediaURL).flatMap(URL.init(string:)) else { return }
            let identifier = guid.isEmpty ? (link.isEmpty ? audio.absoluteString : link) : guid
            items.append(
                FeedItem(
                    guid: identifier,
                    title: title.isEmpty ? "제목 없음" : title,
                    summary: summary,
                    publishedAt: Self.parseDate(pubDate) ?? .now,
                    audioURL: audio,
                    pageURL: URL(string: link),
                    duration: Self.parseDuration(duration)
                )
            )

        default:
            break
        }
    }

    // MARK: - Helpers

    private static let dateFormats = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "dd MMM yyyy HH:mm:ss Z",
        "yyyy-MM-dd'T'HH:mm:ssZ",
    ]

    static func parseDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    /// `6:12`, `00:06:12`, `372` 세 형태를 모두 받는다.
    static func parseDuration(_ raw: String) -> Double {
        guard !raw.isEmpty else { return 0 }
        let parts = raw.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 1: return parts[0]
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return 0
        }
    }
}

private extension String {
    /// 피드 설명에 섞여 오는 태그를 걷어낸다.
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmed
    }
}
