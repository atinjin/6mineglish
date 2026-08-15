import Foundation
import Observation
import SwiftData

/// URLSession 다운로드를 async/await로 감싸고 진행률을 흘려보낸다.
final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private var destination: URL?
    private var progressHandler: (@Sendable (Double) -> Void)?
    private var deferredError: Error?
    private let lock = NSLock()
    private var session: URLSession!

    init(allowsCellular: Bool) {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = allowsCellular
        configuration.timeoutIntervalForResource = 600
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func download(
        from url: URL,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        self.destination = destination
        self.progressHandler = onProgress
        self.deferredError = nil

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            session.downloadTask(with: url).resume()
        }
    }

    func invalidate() {
        session.invalidateAndCancel()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            deferredError = FeedError.badResponse(http.statusCode)
            return
        }
        guard let destination else { return }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            deferredError = error
        }
    }

    // didFinishDownloadingTo 다음에 항상 불리므로, 완료 신호는 여기 한 곳에서만 낸다.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()

        guard let pending else { return }
        if let failure = error ?? deferredError {
            pending.resume(throwing: failure)
        } else {
            pending.resume()
        }
    }
}

@MainActor
@Observable
final class DownloadCenter {
    private(set) var progress: [String: Double] = [:]
    private(set) var failures: [String: String] = [:]

    @ObservationIgnored private var downloaders: [String: FileDownloader] = [:]

    func isDownloading(_ guid: String) -> Bool { progress[guid] != nil }

    func progressValue(for guid: String) -> Double? { progress[guid] }

    @discardableResult
    func download(_ episode: Episode, allowsCellular: Bool) async -> Bool {
        let guid = episode.guid
        guard !isDownloading(guid), let remote = episode.audioURL else { return false }

        if let existing = episode.localAudioURL {
            episode.durationSeconds = AudioProbe.duration(of: existing) ?? episode.durationSeconds
            return true
        }

        FileVault.prepare()
        let filename = episode.audioFilenameCandidate
        let destination = FileVault.audioURL(filename)

        progress[guid] = 0
        failures[guid] = nil

        let downloader = FileDownloader(allowsCellular: allowsCellular)
        downloaders[guid] = downloader

        do {
            try await downloader.download(from: remote, to: destination) { [weak self] value in
                Task { @MainActor in self?.progress[guid] = value }
            }
            episode.localAudioFilename = filename
            if let measured = AudioProbe.duration(of: destination) {
                episode.durationSeconds = measured
            }
            progress[guid] = nil
            downloaders[guid] = nil
            downloader.invalidate()
            return true
        } catch {
            progress[guid] = nil
            failures[guid] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            downloaders[guid] = nil
            downloader.invalidate()
            return false
        }
    }
}
