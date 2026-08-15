import SwiftData
import SwiftUI

/// 이 앱의 중심 화면. 문장 하나를 구간 반복하면서 바로 녹음하고 원본과 겹쳐 본다.
struct ShadowView: View {
    let episode: Episode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RoutineClock.self) private var clock
    @Environment(PlayerEngine.self) private var player
    @Environment(RecorderEngine.self) private var recorder
    @Environment(WaveformStore.self) private var waveforms

    @State private var selectedIndex = 0
    @State private var isLooping = true
    @State private var permissionDenied = false

    private let stage = Stage.shadow
    private var timer: RoutineClock.StageState { clock.state(stage) }
    private var lines: [TranscriptLine] { episode.sortedLines }
    private var current: TranscriptLine? {
        guard lines.indices.contains(selectedIndex) else { return nil }
        return lines[selectedIndex]
    }
    private var recordedCount: Int { lines.filter(\.hasTake).count }

    var body: some View {
        Group {
            if lines.isEmpty {
                EmptyHint(
                    icon: "text.alignleft",
                    title: "스크립트가 필요합니다",
                    message: "문장별 반복과 녹음은 타임스탬프에 기대고 있어, 스크립트를 먼저 생성해야 합니다."
                )
                .padding(.horizontal, 22)
            } else {
                content
            }
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("섀도잉")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Chip(text: "\(recordedCount) / \(lines.count)", color: stage.color, isActive: true)
            }
        }
        .task { await load() }
        .onDisappear { persist() }
        .onChange(of: clock.finishedStage) { _, finished in
            guard finished == stage else { return }
            complete()
            clock.finishedStage = nil
        }
    }

    private var content: some View {
        VStack(spacing: 13) {
            focusCard
            recordControls
            Divider().overlay(Palette.lineSoft)
            lineList
            PrimaryButton(title: "섀도잉 완료", color: stage.color) { complete() }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    // MARK: - 선택된 문장

    @ViewBuilder
    private var focusCard: some View {
        if let line = current {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("문장 \(line.index + 1)").microLabel(stage.color)
                    Spacer()
                    Text("\(line.start.clockLabel) – \(line.end.clockLabel)").microLabel()
                }

                Text(line.text)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .padding(.bottom, 16)

                WaveformComparison(
                    source: sourceSamples(line),
                    mine: takeSamples(line),
                    sourceDuration: line.duration,
                    mineDuration: line.latestTake?.duration
                )

                HStack(spacing: 7) {
                    Button {
                        playSource(line)
                    } label: {
                        Chip(text: "원본", color: Palette.listen, isActive: true, icon: "play.fill")
                    }
                    .buttonStyle(.plain)

                    Button {
                        playTake(line)
                    } label: {
                        Chip(text: "내 녹음", color: line.hasTake ? Palette.output : Palette.faint,
                             isActive: line.hasTake, icon: "play.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(!line.hasTake)

                    Button { player.rate = player.rate == 1.0 ? 0.75 : 1.0 } label: {
                        Chip(text: String(format: "%.2g×", player.rate), color: Palette.dim,
                             isActive: player.rate != 1.0)
                    }
                    .buttonStyle(.plain)

                    Button { isLooping.toggle() } label: {
                        Chip(text: "반복", color: isLooping ? stage.color : Palette.dim,
                             isActive: isLooping, icon: "repeat")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 13)
            }
            .cardSurface(border: stage.color)
        }
    }

    // MARK: - 녹음

    private var recordControls: some View {
        HStack(spacing: 16) {
            Text(current?.hasTake == true ? "다시 녹음" : "녹음")
                .font(.system(size: 13))
                .foregroundStyle(Palette.dim)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Button {
                toggleRecording()
            } label: {
                ZStack {
                    Circle().strokeBorder(Palette.output, lineWidth: 3)
                    RoundedRectangle(cornerRadius: recorder.isRecording ? 6 : 13, style: .continuous)
                        .fill(Palette.output)
                        .frame(width: 26, height: 26)
                }
                .frame(width: 64, height: 64)
            }
            .accessibilityLabel(recorder.isRecording ? "녹음 정지" : "녹음 시작")
            .sensoryFeedback(.impact, trigger: recorder.isRecording)

            Text(recorder.isRecording ? recorder.elapsed.clockLabel : (current?.latestTake?.duration.clockLabel ?? "—"))
                .font(.mono(12, .medium))
                .foregroundStyle(recorder.isRecording ? Palette.output : Palette.faint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottom) {
            if permissionDenied {
                Text("마이크 권한이 필요합니다. 설정에서 허용해 주세요.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.danger)
                    .offset(y: 16)
            }
        }
    }

    // MARK: - 문장 목록

    private var lineList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.index) { index, line in
                        Button {
                            select(index)
                        } label: {
                            HStack(spacing: 10) {
                                Text("\(line.index + 1)")
                                    .font(.mono(11))
                                    .foregroundStyle(Palette.faint)
                                    .frame(width: 22, alignment: .leading)

                                Text(line.text)
                                    .font(.system(size: 14))
                                    .foregroundStyle(index == selectedIndex ? Palette.text : Palette.dim)
                                    .lineLimit(1)

                                Spacer(minLength: 6)

                                Circle()
                                    .fill(line.hasTake ? Palette.output : Palette.line)
                                    .frame(width: 7, height: 7)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(line.index)

                        Divider().overlay(Palette.lineSoft)
                    }
                }
            }
            .onChange(of: selectedIndex) { _, index in
                guard lines.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lines[index].index, anchor: .center)
                }
            }
        }
    }

    // MARK: - 동작

    /// 에피소드 전체 파형을 촘촘하게 한 번만 뽑아두고, 문장 구간만 잘라 쓴다.
    private var detailKey: String { "\(episode.guid)#hi" }
    private static let segmentBuckets = 34

    private func sourceSamples(_ line: TranscriptLine) -> [Float] {
        let total = episode.durationSeconds > 0 ? episode.durationSeconds : player.duration
        guard let full = waveforms.samples(for: detailKey), !full.isEmpty, total > 0 else {
            return WaveformExtractor.synthesized(seed: "\(episode.guid)#\(line.index)", count: Self.segmentBuckets)
        }

        let count = Double(full.count)
        let lower = max(0, min(full.count - 1, Int((line.start / total) * count)))
        let upper = max(lower + 1, min(full.count, Int((line.end / total) * count)))
        return WaveformExtractor.downsample(Array(full[lower..<upper]), to: Self.segmentBuckets)
    }

    private func takeSamples(_ line: TranscriptLine) -> [Float]? {
        guard let take = line.latestTake else { return nil }
        return waveforms.samples(for: take.filename)
            ?? WaveformExtractor.synthesized(seed: take.filename, count: Self.segmentBuckets)
    }

    private func load() async {
        guard let url = episode.localAudioURL else { return }
        waveforms.load(url: url, key: episode.guid)
        waveforms.load(url: url, key: detailKey, buckets: 1200)
        try? player.load(url: url, owner: episode.guid)

        // 아직 녹음이 없는 첫 문장에서 시작한다.
        if let index = lines.firstIndex(where: { !$0.hasTake }) {
            selectedIndex = index
        }
        loadTakeWaveform()

        if !clock.state(stage).isRunning, clock.state(stage).remaining > 0 {
            clock.toggle(stage)
        }
    }

    private func loadTakeWaveform() {
        guard let take = current?.latestTake, let url = take.url else { return }
        waveforms.load(url: url, key: take.filename, buckets: Self.segmentBuckets)
    }

    private func select(_ index: Int) {
        guard lines.indices.contains(index) else { return }
        if recorder.isRecording { finishRecording() }
        selectedIndex = index
        loadTakeWaveform()
        if let line = current { playSource(line) }
    }

    private func playSource(_ line: TranscriptLine) {
        guard let url = episode.localAudioURL else { return }
        try? player.load(url: url, owner: episode.guid)
        waveforms.load(url: url, key: episode.guid)
        player.playSegment(from: line.start, to: line.end, looping: isLooping)
    }

    private func playTake(_ line: TranscriptLine) {
        guard let take = line.latestTake, let url = take.url else { return }
        try? player.load(url: url, owner: take.filename)
        player.clearSegment()
        waveforms.load(url: url, key: take.filename, buckets: Self.segmentBuckets)
        player.seek(to: 0)
        player.play()
    }

    private func toggleRecording() {
        if recorder.isRecording {
            finishRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard let line = current else { return }
        player.pause()

        Task {
            guard RecorderEngine.hasPermission || await RecorderEngine.requestPermission() else {
                permissionDenied = true
                return
            }
            permissionDenied = false
            let filename = "\(episode.guid.hashValue.magnitude)-\(line.index)-\(Int(Date().timeIntervalSince1970)).m4a"
            try? recorder.start(filename: filename)
        }
    }

    private func finishRecording() {
        guard let result = recorder.stop(), let line = current else { return }
        let take = ShadowTake(filename: result.filename, duration: result.duration, line: line)
        context.insert(take)
        try? context.save()
        waveforms.load(url: FileVault.takeURL(result.filename), key: result.filename, buckets: Self.segmentBuckets)
    }

    private func persist() {
        if recorder.isRecording { finishRecording() }
        clock.pause(stage)
        player.pause()
        player.clearSegment()
        StudyPlanner.recordStudyTime(clock.drainUnsavedSeconds(stage), stage: stage, context: context)
        try? context.save()
    }

    private func complete() {
        persist()
        StudyPlanner.markStage(stage, done: true, context: context)
        try? context.save()
        dismiss()
    }
}
