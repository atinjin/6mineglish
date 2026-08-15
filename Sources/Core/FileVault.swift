import Foundation

/// 오디오·녹음·파형 캐시가 사는 곳. 전부 Application Support 아래에 두고 iCloud 백업에서 제외한다.
enum FileVault {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SIXMIN", isDirectory: true)
    }()

    static var audio: URL { root.appendingPathComponent("Audio", isDirectory: true) }
    static var takes: URL { root.appendingPathComponent("Takes", isDirectory: true) }
    static var waveforms: URL { root.appendingPathComponent("Waveforms", isDirectory: true) }

    static func prepare() {
        for dir in [root, audio, takes, waveforms] {
            guard !FileManager.default.fileExists(atPath: dir.path) else { continue }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    static func audioURL(_ filename: String) -> URL {
        audio.appendingPathComponent(filename)
    }

    static func takeURL(_ filename: String) -> URL {
        takes.appendingPathComponent(filename)
    }

    static func waveformURL(_ key: String) -> URL {
        waveforms.appendingPathComponent("\(key).wave")
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// 저장 공간 표시용. 재귀 합계라 디렉터리가 커지면 백그라운드에서 부르는 게 낫다.
    static func size(of directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    static var totalSize: Int64 { size(of: root) }

    static func sizeLabel(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// 오래된 mp3만 지운다. 스크립트·카드·녹음은 남는다.
    @discardableResult
    static func pruneAudio(olderThan days: Int, keeping keepFilenames: Set<String>) -> Int {
        guard days > 0 else { return 0 }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: audio,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return 0 }

        var removed = 0
        for url in files where !keepFilenames.contains(url.lastPathComponent) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
            guard modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: url)
            removed += 1
        }
        return removed
    }
}
