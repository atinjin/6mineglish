import AVFoundation
import Foundation
import Observation

/// 화면의 파형은 장식이 아니라 실제 오디오다. 디코딩해서 구간별 최대 진폭을 뽑고 파일로 캐시한다.
enum WaveformExtractor {
    static let defaultBuckets = 60

    static func cached(key: String) -> [Float]? {
        let url = FileVault.waveformURL(key)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }

    static func store(_ samples: [Float], key: String) {
        FileVault.prepare()
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try? data.write(to: FileVault.waveformURL(key), options: .atomic)
    }

    static func samples(for url: URL, key: String, buckets: Int = defaultBuckets) async -> [Float] {
        if let cached = cached(key: key), cached.count == buckets { return cached }
        let extracted = (try? await extract(url: url, buckets: buckets)) ?? synthesized(seed: key, count: buckets)
        store(extracted, key: key)
        return extracted
    }

    static func extract(url: URL, buckets: Int) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw FeedError.parseFailed
        }

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()

        // 1024프레임마다 피크 하나. 6분이면 만 개 남짓이라 메모리에 올려도 된다.
        let window = 1024
        var peaks: [Float] = []
        var index = 0
        var windowPeak: Int16 = 0

        while reader.status == .reading, let buffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &pointer
            ) == noErr, let pointer else { continue }

            pointer.withMemoryRebound(to: Int16.self, capacity: length / 2) { samples in
                for offset in 0..<(length / 2) {
                    let magnitude = Int16(truncatingIfNeeded: abs(Int(samples[offset])))
                    if magnitude > windowPeak { windowPeak = magnitude }
                    index += 1
                    if index == window {
                        peaks.append(Float(windowPeak) / Float(Int16.max))
                        windowPeak = 0
                        index = 0
                    }
                }
            }
            CMSampleBufferInvalidate(buffer)
        }

        if index > 0 { peaks.append(Float(windowPeak) / Float(Int16.max)) }
        guard reader.status != .failed, !peaks.isEmpty else { throw FeedError.parseFailed }

        return downsample(peaks, to: buckets)
    }

    static func downsample(_ peaks: [Float], to buckets: Int) -> [Float] {
        guard buckets > 0, !peaks.isEmpty else { return [] }
        guard peaks.count > buckets else {
            return peaks + Array(repeating: 0, count: buckets - peaks.count)
        }

        var result: [Float] = []
        result.reserveCapacity(buckets)
        let width = Double(peaks.count) / Double(buckets)

        for bucket in 0..<buckets {
            let lower = Int(Double(bucket) * width)
            let upper = min(peaks.count, Int(Double(bucket + 1) * width))
            guard lower < upper else { result.append(0); continue }
            result.append(peaks[lower..<upper].max() ?? 0)
        }

        // 조용한 녹음도 형태가 보이도록 최대치 기준으로 편다.
        let peak = result.max() ?? 1
        guard peak > 0.001 else { return result }
        return result.map { min(1, $0 / peak) }
    }

    /// 디코딩이 실패했을 때 자리를 채우는 파형. 키가 같으면 항상 같은 모양이 나온다.
    static func synthesized(seed: String, count: Int) -> [Float] {
        var state = UInt64(truncatingIfNeeded: seed.hashValue) | 1
        func random() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state % 10_000) / 10_000
        }
        return (0..<count).map { index in
            let envelope = sin(Double(index) / Double(count) * .pi * 3.1) * 0.3 + 0.62
            return Float(max(0.12, min(1, envelope * (0.45 + random() * 0.75))))
        }
    }
}

/// 여러 뷰가 같은 파형을 요구하므로 한 번만 뽑고 메모리에 들고 있는다.
@MainActor
@Observable
final class WaveformStore {
    private(set) var samples: [String: [Float]] = [:]
    @ObservationIgnored private var loading: Set<String> = []

    func samples(for key: String) -> [Float]? { samples[key] }

    func load(url: URL, key: String, buckets: Int = WaveformExtractor.defaultBuckets) {
        guard samples[key] == nil, !loading.contains(key) else { return }
        loading.insert(key)
        Task {
            let values = await WaveformExtractor.samples(for: url, key: key, buckets: buckets)
            self.samples[key] = values
            self.loading.remove(key)
        }
    }

    func placeholder(key: String, buckets: Int = WaveformExtractor.defaultBuckets) -> [Float] {
        samples[key] ?? WaveformExtractor.synthesized(seed: key, count: buckets)
    }
}
