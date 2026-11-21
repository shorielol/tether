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
        records = nights.map { night in
            DayRecord(day: night.day, savedAt: now, strapBatteryPct: 61,
                      today: night.day == DayScorer.dayKey(dayStart: Self.todayStart) ? today : nil, night: night)
        }
    }
    #endif
}
