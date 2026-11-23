import SwiftUI
import TetherCore

/// Every moment you marked by double-tapping the strap: when, what you called it, and your heart rate
/// either side. Once a name has a few marks, what it usually does.
struct MarksView: View {
    @Environment(AppModel.self) private var model
    @State private var naming: Int?
    @State private var draft = ""

    var body: some View {
        TabScreen {
            effects
            settings
            if model.marks.isEmpty {
                NotYet(title: "No marks yet",
                       detail: model.marksNeedTwoTaps
                           ? "Double-tap your strap twice, within a few seconds, to mark a moment: a coffee, an exam, a nap. Your phone asks what it was, and the mark lands on your heart rate."
                           : "Double-tap your strap to mark a moment: a coffee, an exam, a nap. Your phone asks what it was, and the mark lands on your heart rate.")
                    .card()
            } else {
                list
            }
            HowItsWorkedOut(text: "A mark is the moment your strap felt the double-tap. Tap a mark to name it or delete it, or press and hold to delete. Each one compares your average heart rate in the 15 minutes before with the 30 minutes after, once there's at least 5 minutes of heart rate on each side. After \(MarkEffect.marksNeeded) marks with the same name, the usual effect is the average of their changes. Names stay on this phone.")
        }
        .navigationTitle("Marks")
        .navigationBarTitleDisplayMode(.large)
        .alert("Name this mark", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Coffee, exam, nap…", text: $draft)
            ForEach(model.markLabels.recent.prefix(3), id: \.self) { label in
                Button(label) { save(label) }
            }
            Button("Save") { save(draft) }
            Button("Delete mark", role: .destructive) {
                if let naming { model.deleteMark(naming) }
                naming = nil
            }
            Button("Cancel", role: .cancel) { naming = nil }
        }
    }

    @State private var confirmingClear = false
    @State private var confirmingDeleteAll = false

    /// How a mark is made, and a way to clear out accidental ones.
    private var settings: some View {
        let unnamed = model.marks.filter { model.label(for: $0) == nil }.count
        return VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { model.marksNeedTwoTaps }, set: { model.marksNeedTwoTaps = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Two double-taps make a mark").font(.subheadline.weight(.semibold))
                    Text("Tap-tap, then tap-tap again within \(MarkFilter.pairSeconds) seconds. The strap also feels knocks and bumps as double-taps; this keeps those out. Taps while you're asleep never count, and named marks always stay.")
                        .font(.caption).foregroundStyle(TetherBrand.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(TetherBrand.ember)
            if unnamed > 0 {
                Button("Clear \(unnamed) unnamed \(unnamed == 1 ? "mark" : "marks")", role: .destructive) {
                    confirmingClear = true
                }
                .font(.subheadline)
            }
            if !model.marks.isEmpty {
                Button("Delete all marks", role: .destructive) { confirmingDeleteAll = true }
                    .font(.subheadline)
            }
        }
        .card()
        .confirmationDialog("Delete all \(model.marks.count) marks?", isPresented: $confirmingDeleteAll,
                            titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { model.deleteAllMarks() }
        } message: {
            Text("Named ones too, and any taps the filter is hiding. This can't be undone.")
        }
        .confirmationDialog("Clear \(unnamed) unnamed marks?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear them", role: .destructive) { model.clearUnnamedMarks() }
        } message: {
            Text("Marks you've named stay. This can't be undone.")
        }
    }

    private var effects: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What your marks usually do").font(.headline)
            let effects = model.markEffects
            if effects.isEmpty {
                Text("After \(MarkEffect.marksNeeded) marks with the same name, this shows what it usually does to your heart rate.")
                    .font(.subheadline).foregroundStyle(TetherBrand.sub)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(effects) { effect in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(effect.label).font(.subheadline.weight(.semibold))
                            Text("heart rate in the half hour after · \(effect.marks) marks")
                                .font(.caption).foregroundStyle(TetherBrand.sub)
                        }
                        Spacer()
                        Text(signed(effect.bpmChange) + " bpm").font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .card()
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your marks").font(.headline).padding(.bottom, 6)
            ForEach(model.marks.reversed().prefix(40), id: \.self) { mark in
                Button { draft = model.label(for: mark) ?? ""; naming = mark } label: { row(mark) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete mark", systemImage: "trash", role: .destructive) { model.deleteMark(mark) }
                    }
                    .accessibilityAction(named: "Delete mark") { model.deleteMark(mark) }
                if mark != model.marks.reversed().prefix(40).last { Divider().overlay(TetherBrand.cardStroke) }
            }
        }
        .card()
    }

    private func row(_ mark: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.label(for: mark) ?? "Tap to name").font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.label(for: mark) == nil ? TetherBrand.ember : TetherBrand.text)
                Text(when(mark)).font(.caption).foregroundStyle(TetherBrand.sub)
            }
            Spacer()
            if let window = model.markWindows[mark] {
                Text("\(window.before) → \(window.after) bpm").font(.subheadline).monospacedDigit()
            } else {
                Text(Int(Date.now.timeIntervalSince1970) < mark + MarkWindow.afterSeconds ? "reading…" : "no heart rate")
                    .font(.caption).foregroundStyle(TetherBrand.sub)
            }
        }
        .padding(.vertical, 9)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Names this mark. Press and hold to delete it.")
    }

    private func save(_ label: String) {
        if let naming { model.setLabel(label, for: naming) }
        naming = nil
    }

    private func when(_ mark: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(mark))
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Today \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday \(time)" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " \(time)"
    }

    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : value < 0 ? "−\(-value)" : "±0" }
}

/// Today's line for marks: how many today, or how to make one.
struct MarksRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let today = model.marksToday
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Marks").font(.headline)
                Text(today.isEmpty ? (model.marksNeedTwoTaps ? "Double-tap your strap twice to mark a moment" : "Double-tap your strap to mark a moment") : detail(today))
                    .font(.subheadline).foregroundStyle(TetherBrand.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !today.isEmpty {
                Text("\(today.count)").font(.title3.weight(.semibold)).monospacedDigit()
            }
        }
        .card()
    }

    private func detail(_ marks: [Int]) -> String {
        let names = marks.compactMap { model.label(for: $0) }
        let unnamed = marks.count - names.count
        let named = names.isEmpty ? "" : names.joined(separator: ", ")
        switch (named.isEmpty, unnamed) {
        case (true, _): return "\(marks.count == 1 ? "1 mark" : "\(marks.count) marks") today, not named yet"
        case (false, 0): return named
        default: return "\(named) and \(unnamed) not named"
        }
    }
}
