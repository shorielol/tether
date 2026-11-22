import SwiftUI
import TetherCore

/// The day's workouts on the Effort screen: found from your heart rate or added by you. Tap one to change
/// its type or delete it.
struct WorkoutsCard: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Workout?
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Workouts").font(.headline)
                Spacer()
                Button("Add", systemImage: "plus") { adding = true }
                    .labelStyle(.titleAndIcon).font(.subheadline).tint(TetherBrand.text)
            }
            .padding(.bottom, 6)
            if model.workouts.isEmpty {
                Text("Twelve minutes or more with your heart rate clearly up shows here as a workout. You can add one too.")
                    .font(.subheadline).foregroundStyle(TetherBrand.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.workouts) { workout in
                Button { editing = workout } label: { row(workout) }.buttonStyle(.plain)
                if workout.id != model.workouts.last?.id { Divider().overlay(TetherBrand.cardStroke) }
            }
        }
        .card()
        .sheet(item: $editing) { workout in
            WorkoutEditSheet(workout: workout).presentationDetents([.medium])
        }
        .sheet(isPresented: $adding) { WorkoutAddSheet().presentationDetents([.medium]) }
    }

    private func row(_ workout: Workout) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(workout.kind.name + (workout.isManual ? " · added" : "")).font(.subheadline.weight(.semibold))
                Text("\(time(workout.start))–\(time(workout.end)) · \(workout.durationMin) min"
                     + (workout.averageBPM > 0 ? " · avg \(workout.averageBPM), peak \(workout.peakBPM)" : ""))
                    .font(.caption).foregroundStyle(TetherBrand.sub)
            }
            Spacer()
            if let effort = workout.effort {
                Text(String(format: "%.1f", effort)).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
        }
        .padding(.vertical, 9)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Change its type or delete it")
    }

    private func time(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .omitted, time: .shortened)
    }
}

private struct WorkoutEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    @State private var kind: Workout.Kind

    init(workout: Workout) {
        self.workout = workout
        _kind = State(initialValue: workout.kind)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(Workout.Kind.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                if !workout.kindIsYours {
                    Text("Tether guessed this from your heart rate and movement. Pick the right one and it stays.")
                        .font(.footnote).foregroundStyle(TetherBrand.sub)
                }
                Button("Delete workout", role: .destructive) {
                    model.editWorkouts { $0.delete(workout.start) }
                    dismiss()
                }
            }
            .navigationTitle(workout.kind.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.editWorkouts { $0.setKind(kind, for: workout.start) }
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct WorkoutAddSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind = Workout.Kind.run
    @State private var start = Date.now.addingTimeInterval(-3_600)
    @State private var minutes = 30

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(Workout.Kind.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                DatePicker("Started", selection: $start, in: Calendar.current.startOfDay(for: .now)...Date.now)
                Stepper("\(minutes) minutes", value: $minutes, in: 5...240, step: 5)
            }
            .navigationTitle("Add workout").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let from = Int(start.timeIntervalSince1970)
                        model.editWorkouts { $0.add(start: from, end: from + minutes * 60, kind: kind) }
                        dismiss()
                    }
                }
            }
        }
    }
}
