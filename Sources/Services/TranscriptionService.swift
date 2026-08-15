import AVFoundation
import Foundation
import Observation
import Speech
import SwiftData

enum TranscriptionError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case onDeviceUnavailable
    case noAudio
    case empty

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "음성 인식 권한이 없습니다. 설정에서 허용해 주세요."
        case .recognizerUnavailable: "영어 음성 인식을 사용할 수 없습니다."
        case .onDeviceUnavailable: "기기 내 음성 인식 모델이 준비되지 않았습니다. 설정 › 일반 › 키보드에서 받아쓰기 언어를 내려받거나, 기기 내 처리를 꺼 주세요."
        case .noAudio: "먼저 오디오를 내려받아야 합니다."
        case .empty: "오디오에서 문장을 찾지 못했습니다."
        }
    }
}

struct TranscriptDraft {
    var text: String
    var start: Double
    var end: Double
}

/// 스크립트는 긁어오지 않고 만든다. 합법적으로 받은 오디오를 기기 안에서 처리해 문장과 타임스탬프를 뽑는다.
@MainActor
@Observable
final class TranscriptionService {
    private(set) var progress: [String: Double] = [:]
    private(set) var failures: [String: String] = [:]

    @ObservationIgnored private var tasks: [String: SFSpeechRecognitionTask] = [:]

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func isRunning(_ guid: String) -> Bool { progress[guid] != nil }

    func cancel(_ guid: String) {
        tasks[guid]?.cancel()
        tasks[guid] = nil
        progress[guid] = nil
    }

    @discardableResult
    func transcribe(episode: Episode, preferOnDevice: Bool, context: ModelContext) async -> Bool {
        let guid = episode.guid
        guard !isRunning(guid) else { return false }
        guard let audioURL = episode.localAudioURL else {
            failures[guid] = TranscriptionError.noAudio.errorDescription
            return false
        }

        guard Self.isAuthorized || await Self.requestAuthorization() else {
            failures[guid] = TranscriptionError.notAuthorized.errorDescription
            return false
        }

        progress[guid] = 0
        failures[guid] = nil
        episode.transcriptState = .running
        episode.transcriptProgress = 0

        let total = episode.durationSeconds > 0
            ? episode.durationSeconds
            : (AudioProbe.duration(of: audioURL) ?? 0)

        do {
            let drafts = try await recognize(url: audioURL, guid: guid, total: total, preferOnDevice: preferOnDevice)
            apply(drafts, to: episode, context: context)
            episode.transcriptState = .ready
            episode.transcriptProgress = 1
            progress[guid] = nil
            tasks[guid] = nil
            return true
        } catch {
            episode.transcriptState = .failed
            failures[guid] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            progress[guid] = nil
            tasks[guid] = nil
            return false
        }
    }

    /// 사람이 고친 문장과 녹음이 붙은 문장은 유지하고 나머지만 갈아 끼운다.
    private func apply(_ drafts: [TranscriptDraft], to episode: Episode, context: ModelContext) {
        let existing = Array(episode.lines)
        let keepers = existing.filter { $0.isEdited || $0.hasTake }
        let survivors = Set(keepers.map(\.index))

        for line in existing where !survivors.contains(line.index) {
            context.delete(line)
        }

        for (index, draft) in drafts.enumerated() where !survivors.contains(index) {
            let line = TranscriptLine(
                index: index,
                text: draft.text,
                start: draft.start,
                end: draft.end,
                episode: episode
            )
            context.insert(line)
        }
    }

    private func recognize(
        url: URL,
        guid: String,
        total: Double,
        preferOnDevice: Bool
    ) async throws -> [TranscriptDraft] {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
                ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable
        else { throw TranscriptionError.recognizerUnavailable }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true

        if preferOnDevice {
            guard recognizer.supportsOnDeviceRecognition else { throw TranscriptionError.onDeviceUnavailable }
            request.requiresOnDeviceRecognition = true
        }

        let segments: [SFTranscriptionSegment] = try await withCheckedThrowingContinuation { continuation in
            var settled = false

            let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let error {
                    guard !settled else { return }
                    settled = true
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else { return }

                let collected = result.bestTranscription.segments

                if result.isFinal {
                    guard !settled else { return }
                    settled = true
                    continuation.resume(returning: collected)
                    return
                }

                // 부분 결과의 마지막 위치로 진행률을 잡는다.
                if total > 0, let last = collected.last {
                    let value = min(0.99, (last.timestamp + last.duration) / total)
                    Task { @MainActor in
                        self?.progress[guid] = value
                    }
                }
            }

            Task { @MainActor in
                self.tasks[guid] = task
            }
        }

        let drafts = Self.makeDrafts(from: segments)
        guard !drafts.isEmpty else { throw TranscriptionError.empty }
        return drafts
    }

    /// 인식 결과를 문장으로 묶는다. 섀도잉 화면과 단어 카드의 구간 발음이 전부 이 경계에 기댄다.
    static func makeDrafts(
        from segments: [SFTranscriptionSegment],
        pauseThreshold: Double = 0.65,
        maxWords: Int = 18
    ) -> [TranscriptDraft] {
        guard !segments.isEmpty else { return [] }

        var drafts: [TranscriptDraft] = []
        var words: [String] = []
        var start = segments[0].timestamp
        var end = segments[0].timestamp

        func flush() {
            let text = words.joined(separator: " ").trimmed
            guard !text.isEmpty else { words.removeAll(); return }
            drafts.append(TranscriptDraft(text: text, start: start, end: max(end, start + 0.3)))
            words.removeAll()
        }

        for (index, segment) in segments.enumerated() {
            if words.isEmpty { start = segment.timestamp }
            words.append(segment.substring)
            end = segment.timestamp + segment.duration

            let endsSentence = segment.substring.hasSuffix(".")
                || segment.substring.hasSuffix("?")
                || segment.substring.hasSuffix("!")

            let gapAhead: Double = {
                guard index + 1 < segments.count else { return .greatestFiniteMagnitude }
                return segments[index + 1].timestamp - end
            }()

            if endsSentence || gapAhead > pauseThreshold || words.count >= maxWords {
                flush()
            }
        }
        flush()

        return drafts
    }
}
