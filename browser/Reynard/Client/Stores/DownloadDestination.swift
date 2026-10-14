import Foundation

// Called on DownloadStore's serial queue. Keep directory grants alive for
// previews and sharing as well as writes; history owns its original bookmark.
final class DownloadDestination {
    struct SavedFile {
        let url: URL
        let folderBookmark: Data?
        let warning: String?
    }

    private let defaults: UserDefaults
    private let fileManager = FileManager.default
    private let key = "Downloads.SelectedFolderBookmark"
    private var grantedFolders: [Data: URL] = [:]

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    deinit {
        for url in grantedFolders.values { url.stopAccessingSecurityScopedResource() }
    }

    var folderName: String {
        guard let bookmark = defaults.data(forKey: key) else { return "Reynard / Downloads" }
        return folder(for: bookmark)?.lastPathComponent ?? NSLocalizedString("Choose folder again", comment: "")
    }

    func select(_ url: URL) throws {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw CocoaError(.fileReadUnsupportedScheme) }
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: key)
    }

    func reset() { defaults.removeObject(forKey: key) }

    private func folder(for bookmark: Data) -> URL? {
        if let cached = grantedFolders[bookmark] { return cached }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        let granted = url.startAccessingSecurityScopedResource()
        // Unsandboxed TrollStore/macOS may not need a grant; the coordinated
        // operation still reports inaccessible or revoked destinations.
        if granted { grantedFolders[bookmark] = url }
        return url
    }

    func fileURL(relativePath: String, folderBookmark: Data?, fallbackFolder: URL) -> URL? {
        guard !relativePath.isEmpty, relativePath != ".", relativePath != "..",
              (relativePath as NSString).lastPathComponent == relativePath else { return nil }
        let directory: URL
        if let folderBookmark {
            guard let selected = folder(for: folderBookmark) else { return nil }
            directory = selected
        } else { directory = fallbackFolder }
        return directory.appendingPathComponent(relativePath, isDirectory: false)
    }

    // The engine's authenticated response stays intact. Export only the
    // completed staging file, never refetch the website's URL.
    func saveCompletedFile(_ stagingURL: URL) -> SavedFile {
        guard let bookmark = defaults.data(forKey: key) else {
            return SavedFile(url: stagingURL, folderBookmark: nil, warning: nil)
        }
        let fallback = SavedFile(url: stagingURL, folderBookmark: nil,
                                 warning: NSLocalizedString("Saved in Reynard; chosen folder unavailable", comment: ""))
        guard let directory = folder(for: bookmark) else { return fallback }
        if directory.standardizedFileURL == stagingURL.deletingLastPathComponent().standardizedFileURL {
            return SavedFile(url: stagingURL, folderBookmark: bookmark, warning: nil)
        }
        var result: URL?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: directory, options: [], error: &coordinationError) { coordinatedDirectory in
            let base = stagingURL.deletingPathExtension().lastPathComponent
            let ext = stagingURL.pathExtension
            for index in 1...10_000 {
                let name = index == 1 ? stagingURL.lastPathComponent : base + " \(index)" + (ext.isEmpty ? "" : "." + ext)
                let target = coordinatedDirectory.appendingPathComponent(name)
                if fileManager.fileExists(atPath: target.path) { continue }
                do {
                    // Local Downloads is on the same volume: prefer an atomic
                    // move so a large file is not copied through the UI queue.
                    // Neither operation replaces an existing destination.
                    try fileManager.moveItem(at: stagingURL, to: target)
                    result = target
                    break
                } catch let error as NSError {
                    if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError { continue }
                    break
                }
            }
        }
        guard coordinationError == nil, let result else { return fallback }
        try? fileManager.removeItem(at: stagingURL)
        return SavedFile(url: result, folderBookmark: bookmark, warning: nil)
    }

    func removeRecordedFile(relativePath: String, folderBookmark: Data?, fallbackFolder: URL) {
        guard let url = fileURL(relativePath: relativePath, folderBookmark: folderBookmark, fallbackFolder: fallbackFolder) else { return }
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { coordinatedURL in
            try? fileManager.removeItem(at: coordinatedURL)
        }
    }
}
