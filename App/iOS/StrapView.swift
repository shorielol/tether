import SwiftUI
import TetherCore

struct StrapView: View {
    @Environment(AppModel.self) private var model
    @State private var pairing = false
    @State private var confirmForget = false
    @State private var pickingFolder = false

    var body: some View {
        TabScreen {
            ScreenHeader(eyebrow: model.collector.dataLink == .ready ? "WHOOP 5.0 · heart rate and history"
                                                                     : "WHOOP 5.0 · heart-rate link", title: "Strap")
            if model.collector.isPaired {
                LiveCard()
                AlarmCard(alarm: model.collector.alarm)
                HistoryCard()
                GapAlertToggle()
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    NotYet(title: "No strap paired",
                           detail: "Pair it when you have it. Your history starts at that moment.")
                    PrimaryButton("Pair your strap", fullWidth: false) { pairing = true }
                }
                .card()
            }
            BedtimeCard(items: model.bedtimeItems)
            FilesCard(picking: $pickingFolder)
            VStack(alignment: .leading, spacing: 6) {
                Label("Coverage, last 7 nights", systemImage: "chart.bar").font(.headline)
                Text("Shows after your first night.")
                    .font(.subheadline).foregroundStyle(TetherBrand.sub)
            }
            .card()
            if let expiry = model.installExpiry { ExpiryCard(status: expiry) }
            if model.collector.isPaired {
                Button("Forget this strap", role: .destructive) { confirmForget = true }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.setFolder(url) }
        }
        .sheet(isPresented: $pairing) {
            ScanStep(choose: { strap in
                model.collector.pair(with: strap.id)
                pairing = false
            })
            .padding(20)
            .presentationDetents([.large])
        }
        .confirmationDialog("Forget this strap?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget and erase what it recorded", role: .destructive) {
                Task { await model.collector.forgetStrap(erase: true) }
            }
            Button("Forget, keep the data") {
                Task { await model.collector.forgetStrap(erase: false) }
            }
        } message: {
            Text(forgetMessage)
        }
    }
}

extension StrapView {
    fileprivate var forgetMessage: String {
        guard let pairedAt = model.collector.pairedAt else { return "Tether stops reconnecting to it." }
        let since = Date(timeIntervalSince1970: TimeInterval(pairedAt)).formatted(date: .abbreviated, time: .shortened)
        return "It has been recording since \(since). Erase that if you picked the wrong device, so your history starts with the right strap."
    }
}

private struct LiveCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let collector = model.collector
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(collector.heartRate.map(String.init) ?? "–")
                        .font(.system(size: 56, weight: .bold)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("bpm").font(.headline).foregroundStyle(TetherBrand.sub)
                }
                Spacer()
                LinkPill(link: collector.link)
            }
            .animation(.smooth, value: collector.heartRate)
            HStack {
                stat("Strap battery", collector.batteryPercent.map { "\($0)%" } ?? "–")
                Spacer()
                stat("Firmware", collector.firmware ?? "–")
                Spacer()
                stat("Last beat", lastBeat(collector.lastSampleAt))
            }
            if let error = collector.lastWriteError {
                Text("Couldn't save the last samples. Tether keeps them and tries again. (\(error))")
                    .font(.footnote).foregroundStyle(TetherBrand.headsUp)
            }
        }
        .card()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(TetherBrand.sub)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
    }

    private func lastBeat(_ ts: Int?) -> String {
        guard let ts else { return "–" }
        return Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .omitted, time: .shortened)
    }
}

/// The strap's memory: skin temperature, motion and the minutes the phone missed. Synced on its own
/// every few hours and each morning; this card says where it stands and can start one now.
private struct HistoryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let collector = model.collector
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Strap history", systemImage: "arrow.triangle.2.circlepath").font(.headline)
                Spacer()
                if collector.isSyncingHistory { ProgressView().controlSize(.small) }
            }
            Text(status(collector)).font(.subheadline).foregroundStyle(TetherBrand.sub)
                .fixedSize(horizontal: false, vertical: true)
            if collector.lastHistoryOutcome == .saveFailed {
                Text("Couldn't save the last sync. The strap keeps that data, so the next sync picks it up.")
                    .font(.footnote).foregroundStyle(TetherBrand.headsUp)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if collector.dataLink == .ready, !collector.isSyncingHistory {
                Button("Sync now") { collector.syncHistoryNow() }
                    .buttonStyle(.bordered)
            }
            if case .declined(let reason) = collector.dataLink {
                Text("iOS said: \(reason)").font(.footnote).foregroundStyle(TetherBrand.sub)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { collector.retryDataLink() }
                    .buttonStyle(.bordered)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func status(_ collector: LiveCollector) -> String {
        switch collector.dataLink {
        case .pairing:
            return "Accept the pairing request to let Tether read the strap's memory: skin temperature, motion and any minutes your phone missed."
        case .declined:
            return "The strap didn't accept this phone, so Tether records live heart rate only. If another device (like a Mac) is paired with the strap, forget it there first, then try again."
        case .unavailable:
            return lastSynced(collector).map { "Last synced \($0). Syncs again when the strap is connected." }
                ?? "Skin temp, motion and missed minutes, once connected."
        case .ready:
            if collector.isSyncingHistory { return "Reading the strap's memory…" }
            return lastSynced(collector).map { "Up to date as of \($0)\(rowsNote(collector))." } ?? "Connected. First sync starting."
        }
    }

    private func lastSynced(_ collector: LiveCollector) -> String? {
        collector.lastHistorySync.map {
            Date(timeIntervalSince1970: TimeInterval($0)).formatted(date: .omitted, time: .shortened)
        }
    }

    private func rowsNote(_ collector: LiveCollector) -> String {
        switch collector.lastHistoryOutcome {
        case .caughtUp(let rows)?, .timedOut(let rows)?: rows > 0 ? " · \(rows.formatted()) readings added" : ""
        default: ""
        }
    }
}

struct LinkPill: View {
    let link: LinkState

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch link {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .reconnecting: "Reconnecting"
        case .scanning: "Searching"
        case .idle: "Not connected"
        case .bluetoothOff: "Bluetooth off"
        case .unauthorized: "No Bluetooth access"
        case .unavailable: "No Bluetooth"
        }
    }

    private var color: Color {
        switch link {
        case .connected: TetherBrand.good
        case .connecting, .reconnecting, .scanning: TetherBrand.headsUp
        case .idle, .bluetoothOff, .unauthorized, .unavailable: TetherBrand.sub
        }
    }
}

private struct BedtimeCard: View {
    let items: [BedtimeCheck.Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tonight's bedtime check", systemImage: "checklist").font(.headline)
            ForEach(items) { item in
                HStack {
                    Text(item.label)
                    Spacer()
                    Text(item.state).fontWeight(.semibold).foregroundStyle(color(item.status))
                }
                .font(.subheadline)
            }
        }
        .card()
    }

    private func color(_ status: BedtimeCheck.Status) -> Color {
        switch status {
        case .ok: TetherBrand.good
        case .warn: TetherBrand.headsUp
        case .unknown: TetherBrand.sub
        }
    }
}

private struct ExpiryCard: View {
    let status: InstallExpiry.Status

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(status.needsReinstallSoon ? TetherBrand.headsUp : TetherBrand.text)
            Text("Your Mac renews this on the same Wi-Fi. History stays on the phone if it lapses.")
                .font(.subheadline).foregroundStyle(TetherBrand.sub)
        }
        .card()
    }

    private var title: String {
        if status.isExpired { return "App install has expired" }
        let date = status.expires.formatted(.dateTime.weekday(.wide).hour().minute())
        return status.daysLeft == 1 ? "App install expires tomorrow · \(date)"
            : "App install expires in \(status.daysLeft) days · \(date)"
    }
}

private struct FilesCard: View {
    @Binding var picking: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Your files", systemImage: "folder").font(.headline)
            if let name = model.folderName {
                Text("iCloud Drive / \(name)").font(.subheadline.weight(.semibold))
                Text(model.lastSavedAt.map { "Saved at \($0.formatted(date: .omitted, time: .shortened)) · your Mac reads the same folder" }
                     ?? "Saving soon")
                    .font(.caption).foregroundStyle(TetherBrand.sub)
            } else {
                Text("One file a day in iCloud Drive, for Tether on your Mac.")
                    .font(.subheadline).foregroundStyle(TetherBrand.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.folderError {
                Text(error).font(.caption).foregroundStyle(TetherBrand.headsUp)
            }
            Button(model.folderName == nil ? "Choose folder" : "Change folder") { picking = true }
                .fontWeight(.semibold)
        }
        .card()
    }
}

/// The out-of-touch notification's switch.
private struct GapAlertToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Toggle(isOn: Binding(get: { model.gapAlerts }, set: { model.gapAlerts = $0 })) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Tell me when the strap is out of touch", systemImage: "bell").font(.subheadline.weight(.semibold))
                Text("After two hours without it. Never at night.")
                    .font(.caption).foregroundStyle(TetherBrand.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(TetherBrand.ember)
        .card()
    }
}
