import Foundation

/// The iCloud Drive folder both apps share. The phone writes `profile.md` and `days/`; the Mac writes
/// only `inbox/mac/`. Every read and write goes through `NSFileCoordinator`, so iCloud never sees a
/// half-written file.
public struct SharedFolder: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public enum FolderError: Error { case coordination(String) }

    // MARK: - Bookmarks (keep access to the folder the user picked)

    public static func bookmark(for url: URL) throws -> Data {
        #if os(macOS)
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    /// Resolves a saved bookmark. `isStale` means it should be saved again.
    public static func resolve(_ data: Data) -> (folder: SharedFolder, isStale: Bool)? {
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = .withSecurityScope
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        guard let url = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        return (SharedFolder(url: url), stale)
    }

    /// Runs `body` with the picked folder's security scope open.
    public func withAccess<T>(_ body: () throws -> T) rethrows -> T {
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    // MARK: - Files

    public func write(_ text: String, to relativePath: String) throws {
        let target = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try coordinate(writing: target) { destination in
            try Data(text.utf8).write(to: destination, options: .atomic)
        }
    }

    public func read(_ relativePath: String) throws -> String {
        try read(url: url.appendingPathComponent(relativePath))
    }

    public func read(url file: URL) throws -> String {
        var text = ""
        try coordinate(reading: file) { source in
            text = try String(contentsOf: source, encoding: .utf8)
        }
        return text
    }

    /// Every day file, oldest first.
    public func dayFiles() -> [URL] {
        let days = url.appendingPathComponent("days")
        guard let walker = FileManager.default.enumerator(at: days, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Mac recordings the phone hasn't imported yet, oldest first.
    public func pendingInbox() -> [URL] {
        let inbox = url.appendingPathComponent("inbox/mac")
        let files = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "csv" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Moves an imported inbox file to `inbox/done/`, so it's never imported twice.
    public func markImported(_ file: URL) throws {
        let done = url.appendingPathComponent("inbox/done")
        try FileManager.default.createDirectory(at: done, withIntermediateDirectories: true)
        let destination = done.appendingPathComponent(file.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: file, to: destination)
    }

    // MARK: - Coordination

    private func coordinate(writing file: URL, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { target in
            do { try body(target) } catch { bodyError = error }
        }
        if let coordinationError { throw FolderError.coordination(coordinationError.localizedDescription) }
        if let bodyError { throw bodyError }
    }

    private func coordinate(reading file: URL, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { source in
            do { try body(source) } catch { bodyError = error }
        }
        if let coordinationError { throw FolderError.coordination(coordinationError.localizedDescription) }
        if let bodyError { throw bodyError }
    }
}
