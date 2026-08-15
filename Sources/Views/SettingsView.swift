import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(RoutineClock.self) private var clock

    @Query private var cards: [StudyCard]
    @Query private var episodes: [Episode]

    @State private var storageLabel = "계산 중…"
    @State private var exportDocument: CardExport?
    @State private var showsExporter = false
    @State private var pruneMessage: String?

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    ForEach(Stage.allCases) { stage in
                        Stepper(value: binding(for: stage), in: 5...90, step: 5) {
                            HStack {
                                Text(stage.title).foregroundStyle(stage.color)
                                Spacer()
                                Text("\(settings.minutes(for: stage))분").font(.mono(13))
                            }
                        }
                    }
                } header: {
                    Text("루틴 시간")
                } footer: {
                    Text("기본값이지 규칙이 아닙니다. 출퇴근 길이에 맞춰 바꾸세요.")
                }

                Section {
                    Toggle("오늘의 에피소드", isOn: $settings.episodeNotifyEnabled)
                    if settings.episodeNotifyEnabled {
                        timePicker("알림 시각", minute: $settings.episodeNotifyMinute)
                    }
                    Toggle("복습 알림", isOn: $settings.reviewNotifyEnabled)
                    if settings.reviewNotifyEnabled {
                        timePicker("알림 시각", minute: $settings.reviewNotifyMinute)
                    }
                    Toggle("연속 끊김 알림", isOn: $settings.streakNotifyEnabled)
                } header: {
                    Text("알림")
                } footer: {
                    Text("할 일이 남아 있을 때만 보냅니다. 오늘 몫을 끝내면 알림은 오지 않습니다.")
                }

                Section {
                    Toggle("기기 안에서만 생성", isOn: $settings.onDeviceTranscription)
                    Toggle("생성 후 직접 교정", isOn: $settings.manualCorrection)
                } header: {
                    Text("스크립트")
                } footer: {
                    Text("오디오는 BBC 공식 RSS에서 받고, 스크립트는 그 오디오로 기기 안에서 만듭니다. 기기 내 처리를 끄면 애플 서버로 오디오가 전송됩니다.")
                }

                Section {
                    Toggle("뜻 → 영어 카드도 만들기", isOn: $settings.makeProductionCards)
                    Toggle("듣고 맞히기 카드도 만들기", isOn: $settings.makeListeningCards)
                    Stepper(value: $settings.dailyNewLimit, in: 5...100, step: 5) {
                        HStack {
                            Text("하루 신규 상한")
                            Spacer()
                            Text("\(settings.dailyNewLimit)장").font(.mono(13))
                        }
                    }
                    Stepper(value: $settings.dailyReviewLimit, in: 20...500, step: 20) {
                        HStack {
                            Text("하루 복습 상한")
                            Spacer()
                            Text("\(settings.dailyReviewLimit)장").font(.mono(13))
                        }
                    }
                } header: {
                    Text("카드")
                } footer: {
                    Text("단어 하나에서 나온 카드들은 서로 다른 카드로 간격을 따로 셉니다.")
                }

                Section {
                    Toggle("Wi-Fi에서만 받기", isOn: $settings.wifiOnlyDownload)

                    HStack {
                        Text("저장 공간")
                        Spacer()
                        Text(storageLabel).font(.mono(13)).foregroundStyle(Palette.dim)
                    }

                    Stepper(value: $settings.audioRetentionDays, in: 7...180, step: 7) {
                        HStack {
                            Text("오디오 보관")
                            Spacer()
                            Text("\(settings.audioRetentionDays)일").font(.mono(13))
                        }
                    }

                    Button("오래된 오디오 정리") { prune() }
                        .foregroundStyle(Palette.danger)

                    Button("카드 내보내기 (CSV)") { export() }

                    if let pruneMessage {
                        Text(pruneMessage).font(.system(size: 12)).foregroundStyle(Palette.dim)
                    }
                } header: {
                    Text("데이터")
                } footer: {
                    Text("정리해도 스크립트·카드·녹음은 남고 오디오 파일만 지웁니다. 이 앱을 그만 써도 카드는 남습니다.")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                }
            }
            .task { await measureStorage() }
            .onDisappear {
                settings.persist()
                clock.syncDurations(with: settings)
                Task { await NotificationScheduler.refresh(context: context, settings: settings) }
            }
            .fileExporter(
                isPresented: $showsExporter,
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "sixmin-cards"
            ) { _ in }
        }
    }

    private func binding(for stage: Stage) -> Binding<Int> {
        switch stage {
        case .listen: Binding(get: { settings.listenMinutes }, set: { settings.listenMinutes = $0 })
        case .shadow: Binding(get: { settings.shadowMinutes }, set: { settings.shadowMinutes = $0 })
        case .output: Binding(get: { settings.outputMinutes }, set: { settings.outputMinutes = $0 })
        }
    }

    private func timePicker(_ title: String, minute: Binding<Int>) -> some View {
        DatePicker(
            title,
            selection: Binding(
                get: { DayKey.startOfDay().addingTimeInterval(TimeInterval(minute.wrappedValue * 60)) },
                set: { date in
                    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                    minute.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                }
            ),
            displayedComponents: .hourAndMinute
        )
    }

    private func measureStorage() async {
        let bytes = await Task.detached { FileVault.totalSize }.value
        storageLabel = FileVault.sizeLabel(bytes)
    }

    private func prune() {
        // 오늘 배정된 편과 아직 안 끝낸 편의 오디오는 남긴다.
        let keep = Set(
            episodes
                .filter { $0.assignedDayKey == DayKey.today || !$0.isCompleted }
                .compactMap(\.localAudioFilename)
        )
        let removed = FileVault.pruneAudio(olderThan: settings.audioRetentionDays, keeping: keep)

        for episode in episodes where episode.localAudioFilename != nil && episode.localAudioURL == nil {
            episode.localAudioFilename = nil
        }
        try? context.save()

        pruneMessage = removed == 0 ? "지울 오디오가 없습니다." : "오디오 \(removed)개를 정리했습니다."
        Task { await measureStorage() }
    }

    private func export() {
        exportDocument = CardExport(csv: CardExport.makeCSV(from: cards))
        showsExporter = true
    }
}

/// 내보내기는 내가 쓴 카드만 대상으로 한다. Anki가 그대로 읽는 CSV다.
struct CardExport: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var csv: String

    init(csv: String) { self.csv = csv }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        csv = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(csv.utf8))
    }

    static func makeCSV(from cards: [StudyCard]) -> String {
        var rows = ["front,back,note,example,kind,due,interval"]
        let formatter = ISO8601DateFormatter()

        for card in cards {
            let fields = [
                card.prompt,
                card.answer,
                card.note,
                card.example,
                card.kind.rawValue,
                formatter.string(from: card.dueAt),
                String(card.intervalDays),
            ]
            rows.append(fields.map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
