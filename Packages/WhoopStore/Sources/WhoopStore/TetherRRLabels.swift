import GRDB
import WhoopProtocol

// tether: labels a device's unlabelled R-R as one transport, for stores written before Tether's live
// link stamped its beats. Without it a WHOOP 5 owner's old live beats drop out of scoring as soon as any
// labelled beat exists (see the WHOOP 5 branch of `rrIntervals`). Only NULL rows change, so running it
// again is a no-op, and the strap's 500 ms fill beats are flagged exactly as `insert` flags them.
extension WhoopStore {
    public func labelLegacyRR(deviceId: String, as source: RRSourceChannel) async throws -> Int {
        try syncWrite { db in
            let fill = try Row.fetchOne(db, sql: """
                SELECT MIN(ts) AS lo, MAX(ts) AS hi FROM rrInterval
                WHERE deviceId = ? AND srcChannel IS NULL AND rrMs = 500
                """, arguments: [deviceId])
            try db.execute(sql: "UPDATE rrInterval SET srcChannel = ? WHERE deviceId = ? AND srcChannel IS NULL",
                           arguments: [source.rawValue, deviceId])
            let changed = db.changesCount
            if source == .whoop5Historical || source == .whoop5Standard,
               let lo: Int = fill?["lo"], let hi: Int = fill?["hi"] {
                try db.execute(sql: WhoopStore.whoop5RrFillFlagSQL,
                               arguments: ["deviceId": deviceId, "fromTs": lo, "toTs": hi])
            }
            return changed
        }
    }
}
