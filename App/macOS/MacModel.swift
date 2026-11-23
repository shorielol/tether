import AppKit
import Foundation
import Observation
import TetherCore
import TetherFiles

/// The Mac side of the pair: reads the day files the phone writes into the shared iCloud Drive folder.
@MainActor
@Observable
final class MacModel {
    private static let folderKey = "tether.folder"
    private static let refreshSeconds: Double = 60
    private static let recentDays = 30

    private(set) var folderName: String?
    private(set) var records: [DayRecord] = []
    private(set) var readError: String?
    /// What the iPhone wrote in profile.md: the wearer, the history start and the strap's name.
    private(set) var phoneProfile: PhoneProfile?
    /// The day the Day and Sleep pages show. Starts on today.
    var selectedDay: Date = Calendar.current.startOfDay(for: .now) {
        didSet { Task { await refreshMacMinutes() } }
    }
    /// Minutes this Mac recorded on the selected day that the phone hasn't folded in yet.
    private(set) var macMinutes: [TodaySnapshot.MinutePoint] = []
    /// This Mac's own strap link. Created once the model exists, because it reads the folder through it.
    private(set) var recorder: MacRecorder!
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?

    struct PhoneProfile: Equatable {
        let profile: UserProfile
        let historyStarts: Int?
        let strapName: String?
    }

    init() {
        folderName = folder?.url.lastPathComponent
        recorder = MacRecorder(folder: { [weak self] in self?.folder },
                               phoneSavedAt: { [weak self] in self?.lastSyncedAt.map { Int($0.timeIntervalSince1970) } },
                               wantedStrapName: { [weak self] in self?.phoneProfile?.strapName })
        #if DEBUG
        if DebugFixture.isOn { loadFixture(); return }
        #endif
        startRefreshing()
        recorder.start()
    }

    var selectedStart: Int { Int(selectedDay.timeIntervalSince1970) }
    var selectedKey: String { DayScorer.dayKey(dayStart: selectedStart) }
    var selectedRecord: DayRecord? { records.first { $0.day == selectedKey } }
    var isShowingToday: Bool { Calendar.current.isDateInToday(selectedDay) }
    var canGoBack: Bool {
        guard let oldest = Calendar.current.date(byAdding: .day, value: -Self.recentDays, to: .now) else { return false }
        return selectedDay > oldest
    }

    func moveDay(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: selectedDay) else { return }
        let today = Calendar.current.startOfDay(for: .now)
        selectedDay = min(next, today)
    }

    func goToToday() { selectedDay = Calendar.current.startOfDay(for: .now) }

    /// The phone's minutes for the selected day, continued by this Mac's own where the phone has none yet.
    var dayMinutes: [TodaySnapshot.MinutePoint] {
        let phone = selectedRecord?.today?.minuteSeries ?? []
        let lastPhone = phone.last?.ts ?? Int.min
        let gapSegment = (phone.map(\.segment).max() ?? 0) + 1
        return phone + macMinutes.filter { $0.ts > lastPhone }.map {
            .init(ts: $0.ts, bpm: $0.bpm, segment: $0.segment + gapSegment)
        }
    }

    /// Spans the phone already credited to this Mac, plus what this Mac holds that the phone hasn't imported.
    var dayMacSpans: [ClosedRange<Int>] {
        var spans = selectedRecord?.macSpans ?? []
        let lastPhone = selectedRecord?.today?.minuteSeries.last?.ts ?? Int.min
        let pending = macMinutes.filter { $0.ts > lastPhone }
        if let first = pending.first?.ts, let last = pending.last?.ts { spans.append(first...(last + 59)) }
        return spans
    }

    private func refreshMacMinutes() async {
        guard let recorder, recorder.collector.isPaired else { macMinutes = []; return }
        let start = selectedStart
        let end = min(start + 86_399, Int(Date().timeIntervalSince1970))
        guard end > start else { macMinutes = []; return }
        macMinutes = await recorder.minutes(in: start...end, profile: phoneProfile?.profile)
    }

    var today: TodaySnapshot? { records.first { $0.day == DayScorer.dayKey(dayStart: Self.todayStart) }?.today }
    var nights: [NightSummary] { records.compactMap(\.night) }
    var lastNight: NightSummary? { nights.last { $0.sleepStart != nil } }
    var baseline: BaselineProgress { BaselineProgress(scoredNights: nights.filter { $0.hrv != nil }.count) }

    /// When the phone last wrote anything.
    var lastSyncedAt: Date? {
        records.map(\.savedAt).max().map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        panel.message = "Pick the same iCloud Drive folder you chose on your iPhone."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            UserDefaults.standard.set(try SharedFolder.bookmark(for: url), forKey: Self.folderKey)
            folderName = url.lastPathComponent
            readError = nil
            refresh()
        } catch {
            readError = "Couldn't keep access to that folder: \(error.localizedDescription)"
        }
    }

    func refresh() {
        guard let folder else { records = []; return }
        let loaded: [DayRecord]
        do {
            loaded = try folder.withAccess {
                try folder.dayFiles().suffix(Self.recentDays).map { try DayFile.read(folder.read(url: $0)) }
            }
            phoneProfile = try? folder.withAccess {
                let read = try ProfileFile.read(folder.read(ProfileFile.relativePath))
                return PhoneProfile(profile: read.profile, historyStarts: read.pairedAt, strapName: read.strapName)
            }
            readError = nil
        } catch {
            readError = "Couldn't read a day file: \(error.localizedDescription)"
            return
        }
        records = loaded.sorted { $0.day < $1.day }
        Task { await refreshMacMinutes() }
    }

    private var folder: SharedFolder? {
        UserDefaults.standard.data(forKey: Self.folderKey).flatMap(SharedFolder.resolve)?.folder
    }

    private func startRefreshing() {
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(Self.refreshSeconds))
            }
        }
    }

    private static var todayStart: Int { Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970) }

    #if DEBUG
    private func loadFixture() {
        folderName = "Tether"
        let nights = DebugFixture.nights()
        let today = DebugFixture.today(profile: UserProfile(age: 17, heightCm: 178, weightKg: 68, restingHR: nil, sex: .male))
        let now = Int(Date().timeIntervalSince1970) - 180
        let start = Self.todayStart
        records = nights.map { night in
            let isToday = night.day == DayScorer.dayKey(dayStart: start)
            return DayRecord(day: night.day, savedAt: now, strapBatteryPct: 61, today: isToday ? today : nil, night: night,
                             macSpans: isToday ? [(start + 8 * 3600 + 300)...(start + 14 * 3600 + 2400)] : [])
        }
        phoneProfile = PhoneProfile(profile: UserProfile(age: 17, heightCm: 178, weightKg: 68, restingHR: nil, sex: .male),
                                    historyStarts: start - 6 * 86_400, strapName: "WHOOP NAKV")
    }
    #endif
}
