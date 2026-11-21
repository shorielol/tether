// tether: added for Tether (not in NOOP). Removes live samples from one moment onward, used when a
// strap paired by mistake is forgotten and what it recorded is erased.
import Foundation
import GRDB

extension WhoopStore {
    /// Deletes heart-rate and R-R rows for `deviceId` with `ts >= from`, in one transaction.
    /// Returns the number of rows removed.
    @discardableResult
    public func deleteLiveSamples(deviceId: String, from: Int) async throws -> Int {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM hrSample WHERE deviceId = ? AND ts >= ?", arguments: [deviceId, from])
            let hr = db.changesCount
            try db.execute(sql: "DELETE FROM rrInterval WHERE deviceId = ? AND ts >= ?", arguments: [deviceId, from])
            return hr + db.changesCount
        }
    }
}
