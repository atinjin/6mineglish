import SwiftData
import SwiftUI

/// 첫 청취는 글자 없이. 스크립트는 깔려 있되 열려면 한 번 눌러야 한다.
struct ListenView: View {
    let episode: Episode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(RoutineClock.self) private var clock
    @Environment(PlayerEngine.self) private var player
    @Environment(WaveformStore.self) private var waveforms

    @State private var showsTranscript = false
    @State private var loadError: String?

    private let stage = Stage.listen
    private var timer: RoutineClock.StageState { clock.state(stage) }

    private var currentLineIndex: Int? {
        guard player.isLoaded(episode.guid) else { return nil }
        return episode.sortedLines.firstIndex { player.currentTime >= $0.start && player.currentTime < $0.end }
    }

    var body: some View {
        VStack(spacing: 13) {
            header
            playerCard
            transcriptSection
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("듣기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Chip(text: timer.remaining.timerLabel, color: stage.color, isActive: true)
                    .monospacedDigit()
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

    private var header: some View {
        VStack(spacing: 5) {
            Text(episode.shortCode).microLabel()
            Text(episode.title)
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var playerCard: some View {
        VStack(spacing: 0) {
            WaveformView(
                samples: waveforms.placeholder(key: episode.guid),
                progress: player.duration > 0 ? player.currentTime / player.duration : 0,
                color: stage.color
            )
            .frame(height: 56)
            .contentShape(Rectangle())
            .gesture(scrubGesture)

            HStack {
                Text(player.currentTime.clockLabel)
                    .font(.mono(11, .medium))
                    .foregroundStyle(stage.color)
                Spacer()
                Text((player.duration > 0 ? player.duration : episode.durationSeconds).clockLabel)
                    .font(.mono(11))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.top, 9)

            HStack(spacing: 26) {
                Button { player.skip(-15) } label: {
                    Image(systemName: "gobackward.15").font(.system(size: 21))
                }
                .foregroundStyle(Palette.dim)

                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 62, height: 62)
                        .background(stage.color, in: Circle())
                }
                .accessibilityLabel(player.isPlaying ? "일시정지" : "재생")

                Button { player.skip(15) } label: {
                    Image(systemName: "goforward.15").font(.system(size: 21))
                }
                .foregroundStyle(Palette.dim)
            }
            .padding(.top, 14)

            HStack(spacing: 7) {
                ForEach([0.75, 1.0, 1.25], id: \.self) { value in
                    Button {
                        player.rate = Float(value)
                    } label: {
                        Chip(
                            text: String(format: "%.2g×", value),
                            color: player.rate == Float(value) ? stage.color : Palette.dim,
                            isActive: player.rate == Float(value)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 14)

            if let loadError {
                Text(loadError)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.danger)
                    .padding(.top, 10)
            }
        }
        .cardSurface(border: stage.color.opacity(0.3))
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                guard player.duration > 0 else { return }
                let width = max(1, UIScreen.main.bounds.width - 44 - 32)
                let ratio = (value.location.x / width).clamped01
                player.seek(to: player.duration * ratio)
            }
    }

    @ViewBuilder
    private var transcriptSection: some View {
        HStack {
            SectionLabel(text: "스크립트")
            Spacer()
            if !showsTranscript {
                Chip(text: "먼저 소리만")
            }
        }

        if episode.hasTranscript {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(episode.sortedLines.enumerated()), id: \.element.index) { index, line in
                            Text(line.text)
                                .font(.system(size: index == currentLineIndex ? 16 : 15.5,
                                              weight: index == currentLineIndex ? .medium : .regular))
                                .foregroundStyle(index == currentLineIndex ? stage.color : Palette.faint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.index)
                                .onTapGesture {
                                    guard showsTranscript else { return }
                                    player.seek(to: line.start)
                                    if !player.isPlaying { player.play() }
                                }
                        }
                    }
                }
                .blur(radius: showsTranscript ? 0 : 3.4)
                .allowsHitTesting(showsTranscript)
                .onChange(of: currentLineIndex) { _, index in
                    guard showsTranscript, let index else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(episode.sortedLines[index].index, anchor: .center)
                    }
                }
            }
        } else {
            EmptyHint(
                icon: "waveform",
                title: "스크립트가 아직 없습니다",
                message: "오늘 화면에서 「스크립트 만들기」를 눌러 기기 안에서 생성할 수 있습니다."
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            if episode.hasTranscript, !showsTranscript {
                Button { showsTranscript = true } label: {
                    Text("스크립트 열기")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .foregroundStyle(Palette.text)
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Palette.line, lineWidth: 1)
                        )
                }
            }

            PrimaryButton(title: "듣기 완료", color: stage.color) { complete() }
        }
    }

    // MARK: - 동작

    private func load() async {
        guard let url = episode.localAudioURL else {
            loadError = "오디오를 먼저 내려받아야 합니다."
            return
        }
        waveforms.load(url: url, key: episode.guid)
        do {
            try player.load(url: url, owner: episode.guid)
            player.clearSegment()
            loadError = nil
        } catch {
            loadError = "오디오를 열지 못했습니다."
        }
        // 화면에 들어오면 타이머가 자동으로 돈다. 루틴을 시작하는 데 버튼 하나를 더 누르게 하지 않는다.
        if !clock.state(stage).isRunning, clock.state(stage).remaining > 0 {
            clock.toggle(stage)
        }
    }

    private func persist() {
        clock.pause(stage)
        player.pause()
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
