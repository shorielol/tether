/// The stretches Tether for Mac recorded, as the phone remembers them after importing its files.
/// Kept merged and sorted; shading them on the chart is all they're for.
public enum MacSpans {
    /// Two spans this close are one stretch: export files are cut every 5 minutes.
    public static let joinGapSeconds = 120

    public static func adding(_ span: ClosedRange<Int>, to spans: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
        var merged: [ClosedRange<Int>] = []
        for next in (spans + [span]).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, next.lowerBound <= last.upperBound + joinGapSeconds {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, next.upperBound)
            } else {
                merged.append(next)
            }
        }
        return merged
    }

    public static func within(_ spans: [ClosedRange<Int>], day: ClosedRange<Int>) -> [ClosedRange<Int>] {
        spans.compactMap { span in
            let lower = max(span.lowerBound, day.lowerBound), upper = min(span.upperBound, day.upperBound)
            return lower <= upper ? lower...upper : nil
        }
    }

    public static func dropping(_ spans: [ClosedRange<Int>], before cutoff: Int) -> [ClosedRange<Int>] {
        spans.filter { $0.upperBound >= cutoff }
    }
}
