import AVFoundation
import Foundation
import Observation

enum AudioSessionManager {
    static func activatePlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }

    static func activateRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

enum AudioProbe {
    static func duration(of url: URL) -> Double? {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        return player.duration
    }
}

/// 원본 오디오와 내 녹음을 모두 이 하나로 재생한다. `owner`로 어느 파일이 물려 있는지 구분한다.
@MainActor
@Observable
final class PlayerEngine {
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    private(set) var owner: String?

    var rate: Float = 1.0 {
        didSet {
            player?.enableRate = true
            player?.rate = rate
        }
    }

    /// 문장 구간 반복. nil이면 통재생.
    private(set) var segment: ClosedRange<Double>?
    private(set) var loops = false

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Timer?

    func load(url: URL, owner: String) throws {
        if self.owner == owner, player != nil { return }
        stop()
        AudioSessionManager.activatePlayback()
        let player = try AVAudioPlayer(contentsOf: url)
        player.enableRate = true
        player.rate = rate
        player.prepareToPlay()
        self.player = player
        self.owner = owner
        duration = player.duration
        currentTime = 0
    }

    func isLoaded(_ owner: String) -> Bool { self.owner == owner && player != nil }

    func play() {
        guard let player else { return }
        AudioSessionManager.activatePlayback()
        player.enableRate = true
        player.rate = rate
        player.play()
        isPlaying = true
        startTicker()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTicker()
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func stop() {
        stopTicker()
        player?.stop()
        player = nil
        owner = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        segment = nil
        loops = false
    }

    func seek(to time: Double) {
        guard let player else { return }
        let clamped = min(max(0, time), max(0, player.duration - 0.05))
        player.currentTime = clamped
        currentTime = clamped
    }

    func skip(_ delta: Double) {
        seek(to: currentTime + delta)
    }

    /// 문장 한 줄을 구간 반복한다. 섀도잉 화면의 기본 동작.
    func playSegment(from start: Double, to end: Double, looping: Bool) {
        guard player != nil, end > start else { return }
        segment = start...end
        loops = looping
        seek(to: start)
        play()
    }

    func clearSegment() {
        segment = nil
        loops = false
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let player else { return }
        currentTime = player.currentTime

        if let segment, currentTime >= segment.upperBound {
            if loops {
                seek(to: segment.lowerBound)
            } else {
                pause()
                seek(to: segment.lowerBound)
            }
            return
        }

        if !player.isPlaying && isPlaying {
            isPlaying = false
            stopTicker()
        }
    }
}

@MainActor
@Observable
final class RecorderEngine {
    private(set) var isRecording = false
    private(set) var elapsed: Double = 0
    private(set) var level: Float = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var destination: URL?

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static var hasPermission: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    @discardableResult
    func start(filename: String) throws -> URL {
        cancel()
        FileVault.prepare()
        AudioSessionManager.activateRecording()

        let url = FileVault.takeURL(filename)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.record()

        self.recorder = recorder
        self.destination = url
        isRecording = true
        elapsed = 0
        startTicker()
        return url
    }

    /// 녹음을 끝내고 파일명과 길이를 돌려준다. 파일은 문장에 붙어 남는다.
    func stop() -> (filename: String, duration: Double)? {
        guard let recorder, let destination else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        stopTicker()
        self.recorder = nil
        self.destination = nil
        isRecording = false
        elapsed = 0
        level = 0
        AudioSessionManager.activatePlayback()

        guard duration > 0.3, FileVault.exists(destination) else {
            FileVault.remove(destination)
            return nil
        }
        return (destination.lastPathComponent, duration)
    }

    func cancel() {
        guard let recorder else { return }
        recorder.stop()
        if let destination { FileVault.remove(destination) }
        stopTicker()
        self.recorder = nil
        self.destination = nil
        isRecording = false
        elapsed = 0
        level = 0
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        elapsed = recorder.currentTime
        // -60dB ~ 0dB를 0~1로 편다.
        let power = recorder.averagePower(forChannel: 0)
        level = max(0, min(1, (power + 60) / 60))
    }
}
