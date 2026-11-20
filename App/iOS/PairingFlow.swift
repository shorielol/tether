import SwiftUI
import TetherCore

/// First launch: pick the strap (or skip until it arrives), fill in the profile, then start the history.
struct PairingFlow: View {
    enum Step: Int { case scan, profile, start }

    @Environment(AppModel.self) private var model
    @State private var step = Step.scan
    @State private var strap: DiscoveredStrap?
    @State private var form = ProfileForm()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepBar(step: step.rawValue, back: back)
            switch step {
            case .scan:
                ScanStep(choose: { strap = $0; step = .profile },
                         skip: { strap = nil; step = .profile })
            case .profile:
                ProfileStep(form: $form) { step = .start }
            case .start:
                StartStep(strap: strap, start: start)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TetherBrand.ink)
        .animation(.smooth(duration: 0.3), value: step)
    }

    private func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func start() {
        guard case .success(let profile) = form.parsed else { return }
        model.finishOnboarding(profile: profile, strap: strap?.id)
    }
}

private struct StepBar: View {
    let step: Int
    let back: () -> Void

    var body: some View {
        HStack {
            Button(action: back) { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .opacity(step == 0 ? 0 : 1)
                .disabled(step == 0)
                .accessibilityLabel("Back")
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(index <= step ? TetherBrand.ember : Color.white.opacity(0.2))
                        .frame(width: index == step ? 22 : 8, height: 8)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(step + 1) of 3")
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }
}

// MARK: - Step 1

struct ScanStep: View {
    let choose: (DiscoveredStrap) -> Void
    var skip: (() -> Void)?
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Find your strap").font(.largeTitle.bold())
            Text("Wear it and keep it close. Tether listens to its standard heart-rate signal, so there's no account and no pairing code.")
                .foregroundStyle(TetherBrand.sub)
            scanState
            Spacer()
            if let skip {
                Button("Set up without a strap", action: skip)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(TetherBrand.sub)
                    .padding(.bottom, 8)
            }
        }
        .onAppear { model.collector.startScan() }
        .onDisappear { model.collector.stopScan() }
    }

    @ViewBuilder private var scanState: some View {
        switch model.collector.link {
        case .bluetoothOff:
            NotYet(title: "Bluetooth is off", detail: "Turn it on in Control Center to look for your strap.").card()
        case .unavailable:
            NotYet(title: "No Bluetooth on this device", detail: "Tether needs a phone with Bluetooth to read the strap.").card()
        case .unauthorized:
            VStack(alignment: .leading, spacing: 12) {
                NotYet(title: "Bluetooth access is off for Tether",
                       detail: "Tether needs it to read your strap. Allow it in Settings.")
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: url).fontWeight(.semibold)
                }
            }
            .card()
        default:
            if model.collector.discovered.isEmpty {
                Searching().card()
            } else {
                ForEach(model.collector.discovered) { found in
                    Button { choose(found) } label: { StrapRow(strap: found) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct Searching: View {
    @State private var ping = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(TetherBrand.ember.opacity(0.5), lineWidth: 2)
                    .scaleEffect(ping ? 1.6 : 0.6).opacity(ping ? 0 : 0.6)
                Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(TetherBrand.ember)
            }
            .frame(width: 36, height: 36)
            NotYet(title: "Looking for straps…",
                   detail: "Nothing yet? Check it's charged, on your wrist, and not connected to another phone.")
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { ping = true }
        }
    }
}

private struct StrapRow: View {
    let strap: DiscoveredStrap

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "heart.fill").foregroundStyle(TetherBrand.ember)
                .frame(width: 40, height: 40)
                .background(TetherBrand.ember.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(strap.name).font(.headline)
                Text(signal).font(.subheadline).foregroundStyle(TetherBrand.sub)
            }
            Spacer()
            Text("Use this strap").font(.subheadline.weight(.semibold)).foregroundStyle(TetherBrand.ember)
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }

    private var signal: String {
        switch strap.rssi {
        case (-60)...: "Strong signal"
        case (-75)...: "Good signal"
        default: "Weak signal · move closer"
        }
    }
}

// MARK: - Step 2

struct ProfileForm {
    var age = ""
    var height = ""
    var weight = ""
    var restingHR = ""
    var sex = Sex.male

    var parsed: Result<UserProfile, UserProfile.FieldError> {
        UserProfile.parse(age: age, heightCm: height, weightKg: weight, restingHR: restingHR, sex: sex)
    }
}

private struct ProfileStep: View {
    @Binding var form: ProfileForm
    let next: () -> Void
    @State private var error: UserProfile.FieldError?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("About you").font(.largeTitle.bold())
                Text("Used for your max heart rate, zones and calories. It stays on your phone and in your own folder.")
                    .foregroundStyle(TetherBrand.sub)
                VStack(spacing: 0) {
                    Field(label: "Age", unit: "years", text: $form.age, keyboard: .numberPad)
                    Divider().overlay(TetherBrand.cardStroke)
                    Field(label: "Height", unit: "cm", text: $form.height, keyboard: .numberPad)
                    Divider().overlay(TetherBrand.cardStroke)
                    Field(label: "Weight", unit: "kg", text: $form.weight, keyboard: .decimalPad)
                    Divider().overlay(TetherBrand.cardStroke)
                    Field(label: "Resting HR", unit: "optional", text: $form.restingHR, keyboard: .numberPad)
                }
                .card(padding: 4)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sex, for the heart-rate formulas").font(.subheadline).foregroundStyle(TetherBrand.sub)
                    Picker("Sex", selection: $form.sex) {
                        ForEach(Sex.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if let error {
                    Text(error.message).font(.subheadline).foregroundStyle(TetherBrand.headsUp)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton("Continue", action: submit)
                .padding(.vertical, 8)
        }
    }

    private func submit() {
        switch form.parsed {
        case .success: error = nil; next()
        case .failure(let failure): error = failure
        }
    }
}

private struct Field: View {
    let label: String
    let unit: String
    @Binding var text: String
    let keyboard: UIKeyboardType

    var body: some View {
        HStack {
            Text(label)
            TextField(unit, text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
    }
}

// MARK: - Step 3

private struct StartStep: View {
    let strap: DiscoveredStrap?
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(strap == nil ? "Ready when your strap is" : "Your history starts now").font(.largeTitle.bold())
            Text(strap == nil
                 ? "You can pair it from the Strap tab. Your history starts the moment you do, and nothing from before is kept."
                 : "Nothing recorded before this moment is kept, so a strap that had an owner before starts clean for you.")
                .foregroundStyle(TetherBrand.sub)
            VStack(spacing: 12) {
                row("First sample", strap == nil ? "When you pair" : "When you tap Start")
                row("Charge ready", "after \(BaselineProgress.chargeNights) nights")
                row("Sleep need learned", "after about 2 weeks")
            }
            .card()
            VStack(alignment: .leading, spacing: 6) {
                Text("Where your files go").font(.headline)
                Text("One markdown file per day, plus a raw backup, in a folder in iCloud Drive. Picking the folder comes with the file writer, in a later update.")
                    .font(.subheadline).foregroundStyle(TetherBrand.sub)
            }
            .card()
            Spacer()
            PrimaryButton(strap == nil ? "Open Tether" : "Start recording", action: start)
                .padding(.bottom, 8)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(TetherBrand.sub)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }
}
