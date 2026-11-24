import Foundation

// Packaging helper: obtain native volume metadata or validate a portable bookmark.
do {
    let args = CommandLine.arguments
    guard args.count == 3 else { throw CocoaError(.fileReadInvalidFileName) }
    if args[1] == "create" {
        let url = URL(fileURLWithPath: args[2])
        let data = try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        FileHandle.standardOutput.write(data)
    } else {
        let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
    }
} catch {
    fputs("DMG background bookmark validation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
