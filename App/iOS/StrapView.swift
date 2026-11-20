import SwiftUI
import TetherCore

struct StrapView: View {
    @Environment(AppModel.self) private var model
    @State private var pairing = false
    @State private var confirmForget = false

    var body: some View {
        TabScreen {
            ScreenHeader(eyebrow: "WHOOP 5.0 · standard heart-rate link", title: "Strap")
            if model.collector.isPaired {
                LiveCard()
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    NotYet(title: "No strap paired",
                           detail: "Pair it when you have it. Your history starts at that moment.")
                    PrimaryButton("Pair your strap", fullWidth: false) { pairing = true }
                }
                .card()
            }
            BedtimeCard(items: model.bedtimeItems)
            VStack(alignment: .leading, spacing: 6) {
                Text("Coverage, last 7 nights").font(.headline)
                Text("Shows after your first recorded night: how much of each night was captured, and where the gaps were.")
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
        .sheet(isPresented: $pairing) {
            ScanStep(choose: { strap in
                model.collector.pair(with: strap.id)
                pairing = false
            })
            .padding(20)
            .presentationDetents([.large])
        }
        .confirmationDialog("Forget this strap?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget strap", role: .destructive) { model.collector.forgetStrap() }
        } message: {
            Text("Tether stops reconnecting to it. Your recorded history stays.")
        }
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
            Text("Tonight's bedtime check").font(.headline)
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
            Text("Free Apple account. Plug the phone into your Mac and install again from Xcode to reset it to 7 days.")
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
