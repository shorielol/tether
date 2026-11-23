import SwiftUI
import TetherCore

/// Everything the Strap page and the toolbar say about the strap, as one value. Built from the
/// live recorder, or in Debug from a canned state so every look can be checked without a strap.
struct StrapStatus {
    struct Fact: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    var isPaired: Bool
    var holder: LinkHolder
    var handedOver: Bool
    var facts: [Fact]
    var problem: String?
    var canHandOver: Bool
    var canSendNow: Bool

    /// The live number, only while this Mac holds the strap and is getting beats.
    var bpm: Int? {
        if case .thisDevice(let bpm?) = holder, !handedOver { return bpm }
        return nil
    }

    /// A worded state for when there's no live number. Never a dash.
    var headline: String {
        if !isPaired { return "No strap on this Mac" }
        if handedOver { return "With your iPhone" }
        switch holder {
        case .thisDevice: return "Connected"
        case .otherDevice: return "With your iPhone"
        case .bluetoothOff: return "Bluetooth is off"
        case .nobody: return "Not in range"
        }
    }

    var sentence: String {
        if !isPaired { return "Pair it once and this Mac records whenever your iPhone isn't holding it." }
        if handedOver { return "Handed to your iPhone. This Mac takes it back once your iPhone goes quiet." }
        switch holder {
        case .thisDevice: return "Recording on this Mac. Your iPhone gets it every 5 minutes."
        case .otherDevice: return "Your iPhone has the strap. This Mac takes over when your phone is off."
        case .bluetoothOff: return "Turn on Bluetooth to record on this Mac."
        case .nobody: return "Waiting for your strap to come in range."
        }
    }

    /// The few words beside the toolbar tether.
    var toolbarText: String {
        if let bpm { return "\(bpm) bpm" }
        if handedOver { return "With your iPhone" }
        switch holder {
        case .thisDevice: return "Connected"
        case .otherDevice: return "With your iPhone"
        case .bluetoothOff: return "Bluetooth off"
        case .nobody: return isPaired ? "Strap not in range" : "No strap yet"
        }
    }

    @MainActor
    static func live(_ recorder: MacRecorder, folderConnected: Bool) -> StrapStatus {
        #if DEBUG
        if let fixture = DebugStrap.status { return fixture }
        #endif
        let collector = recorder.collector
        return StrapStatus(
            isPaired: collector.isPaired,
            holder: recorder.holder,
            handedOver: recorder.handedOverAt != nil,
            facts: [
                Fact(label: "Strap", value: StandardHRSource.rememberedName() ?? "Heart-rate strap"),
                Fact(label: "Battery", value: collector.batteryPercent.map { "\($0)%" } ?? "Shown while connected"),
                Fact(label: "Firmware", value: collector.firmware ?? "Shown while connected"),
                Fact(label: "Recording since", value: recorder.connectedSince.map(clock) ?? "Not recording now"),
                Fact(label: "Sent to your iPhone", value: recorder.lastExportAt.map { $0.formatted(.relative(presentation: .named)) }
                     ?? "Every 5 minutes while recording"),
            ],
            problem: recorder.exportError ?? collector.lastWriteError,
            canHandOver: recorder.isRecording,
            canSendNow: folderConnected)
    }

    static func clock(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .omitted, time: .shortened)
    }
}

#if DEBUG
/// Canned strap states for checking the Strap page by eye: `-tether.fixtureStrap recording` or `handed`.
enum DebugStrap {
    static var status: StrapStatus? {
        guard DebugFixture.isOn, let mode = UserDefaults.standard.string(forKey: "tether.fixtureStrap") else { return nil }
        let since = Int(Calendar.current.date(bySettingHour: 8, minute: 5, second: 0, of: .now)?.timeIntervalSince1970 ?? 0)
        let facts = [
            StrapStatus.Fact(label: "Strap", value: "WHOOP NAKV"),
            StrapStatus.Fact(label: "Battery", value: "78%"),
            StrapStatus.Fact(label: "Firmware", value: "41.17.1.0"),
            StrapStatus.Fact(label: "Recording since", value: StrapStatus.clock(since)),
            StrapStatus.Fact(label: "Sent to your iPhone", value: "2 minutes ago"),
        ]
        switch mode {
        case "recording":
            return StrapStatus(isPaired: true, holder: .thisDevice(bpm: 74), handedOver: false, facts: facts,
                               canHandOver: true, canSendNow: true)
        case "handed":
            return StrapStatus(isPaired: true, holder: .otherDevice, handedOver: true, facts: facts,
                               canHandOver: false, canSendNow: true)
        default:
            return nil
        }
    }
}
#endif

/// The strap from this Mac's side, as in the approved mockup: the tether large and centred, the
/// live number (or a worded state), one sentence, the facts in a quiet panel, then the actions.
struct StrapPane: View {
    @Environment(MacModel.self) private var model
    @State private var confirmForget = false

    var body: some View {
        let recorder = model.recorder!
        let status = StrapStatus.live(recorder, folderConnected: model.folderName != nil)
        VStack(spacing: Space.section) {
            hero(status)
            if status.isPaired {
                VStack(spacing: Space.xl) {
                    Panel { facts(status) }
                    actions(status, recorder)
                }
                .frame(maxWidth: 560)
            } else {
                StrapPicker(wantedName: model.phoneProfile?.strapName) { strap in recorder.pair(with: strap) }
                    .frame(maxWidth: 560)
            }
        }
        .frame(maxWidth: .infinity)
        .confirmationDialog("Forget this strap on this Mac?", isPresented: $confirmForget) {
            Button("Forget, keep what it recorded") { Task { await recorder.forget(erase: false) } }
            Button("Forget and erase this Mac's recording", role: .destructive) { Task { await recorder.forget(erase: true) } }
        } message: {
            Text("Your iPhone keeps its own pairing and history either way. Erase only if this Mac paired with the wrong device.")
        }
    }

    // MARK: Hero

    private func hero(_ status: StrapStatus) -> some View {
        VStack(spacing: Space.l) {
            LiveTether(holder: status.holder, handedOver: status.handedOver, scale: .large)
                .frame(maxWidth: 440)
                .padding(.bottom, Space.s)
            if let bpm = status.bpm {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(bpm)").font(.hero).monospacedDigit().contentTransition(.numericText())
                    Text("bpm").font(.sectionTitle.weight(.medium)).foregroundStyle(.secondary)
                }
            } else {
                Text(status.headline).font(.readout(28))
            }
            Text(status.sentence).font(.bodyText).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Facts

    private func facts(_ status: StrapStatus) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Space.xl, verticalSpacing: Space.m) {
            ForEach(status.facts) { fact in
                GridRow {
                    Text(fact.label).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
                    Text(fact.value).monospacedDigit().textSelection(.enabled)
                }
            }
            if let problem = status.problem {
                GridRow {
                    Text("Problem").foregroundStyle(.secondary)
                    Text(problem).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.bodyText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private func actions(_ status: StrapStatus, _ recorder: MacRecorder) -> some View {
        VStack(spacing: Space.l) {
            HStack(spacing: Space.m) {
                if status.handedOver {
                    Button("Use Strap on This Mac") { recorder.useOnThisMac() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Hand Strap to iPhone") { recorder.handToPhone() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!status.canHandOver)
                }
                Button("Send to iPhone Now") { recorder.saveNow() }
                    .disabled(!status.canSendNow)
                Spacer(minLength: Space.l)
                Button("Forget Strap…", role: .destructive) { confirmForget = true }
            }
            .controlSize(.large)
            Text("On battery, closing the lid sleeps the Mac and recording stops.")
                .font(.captionText).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Nearby heart-rate straps, WHOOP first and the iPhone's own strap marked, each with a Pair button.
struct StrapPicker: View {
    @Environment(MacModel.self) private var model
    var wantedName: String?
    var onPair: (DiscoveredStrap) -> Void

    var body: some View {
        let collector = model.recorder.collector
        let straps = sorted(collector.discovered)
        VStack(alignment: .leading, spacing: Space.l) {
            SectionHeader(title: "Straps nearby") {
                if collector.link == .scanning { ProgressView().controlSize(.small) }
            }
            if straps.isEmpty {
                Text(collector.link == .bluetoothOff
                     ? "Bluetooth is off. Turn it on in Control Center."
                     : "Looking… If your iPhone is holding the strap it won't show here. Turn off Bluetooth on the phone for a moment.")
                    .font(.bodyText).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(straps) { strap in
                        HStack(spacing: Space.m) {
                            Image(systemName: strap.isWhoop ? "heart.circle.fill" : "heart.circle")
                                .font(.title2).foregroundStyle(strap.isWhoop ? Theme.ember : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(strap.name).font(.bodyText.weight(.medium))
                                Text(strap.name == wantedName ? "The strap your iPhone uses" : signal(strap.rssi))
                                    .font(.captionText).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Pair") { onPair(strap) }
                                .buttonStyle(strap.name == wantedName ? AnyButtonStyle(.borderedProminent) : AnyButtonStyle(.bordered))
                        }
                        .padding(.vertical, Space.m).padding(.horizontal, Space.l)
                        if strap.id != straps.last?.id { Divider().padding(.leading, 52) }
                    }
                }
                .background(Theme.groupFill, in: .rect(cornerRadius: 14))
            }
        }
        .onAppear { model.recorder.startScan() }
        .onDisappear { model.recorder.stopScan() }
    }

    private func sorted(_ straps: [DiscoveredStrap]) -> [DiscoveredStrap] {
        let ordered = DiscoveredStrap.whoopFirst(straps)
        guard let wantedName, let mine = ordered.firstIndex(where: { $0.name == wantedName }) else { return ordered }
        var result = ordered
        result.insert(result.remove(at: mine), at: 0)
        return result
    }

    private func signal(_ rssi: Int) -> String {
        rssi > -60 ? "Close by" : rssi > -80 ? "In range" : "Far away"
    }
}

/// Lets one Button pick its style at runtime.
struct AnyButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
