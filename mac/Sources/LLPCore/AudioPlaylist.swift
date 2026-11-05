import Foundation
import UniformTypeIdentifiers

public enum AudioPlaylistError: LocalizedError {
    case noAudioFiles
    case invalidSelection

    public var errorDescription: String? {
        switch self {
        case .noAudioFiles: return "No audio files were found in this selection."
        case .invalidSelection: return "This audio item is no longer available."
        }
    }
}

public enum AudioFileDiscovery {
    /// Lists regular audio files immediately inside a folder in natural filename order.
    public static func files(at url: URL) throws -> [URL] {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        let candidates = values.isDirectory == true
            ? try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            : [url]
        return try candidates.filter { candidate in
            let regular = try candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            let type = UTType(filenameExtension: candidate.pathExtension)
            return regular && (type?.conforms(to: .audio) == true || type?.conforms(to: .movie) == true)
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

/// Coordinates playlist selection and playback; failed loads preserve the existing selection.
public final class AudioPlaylist {
    public private(set) var files: [URL] = []
    public private(set) var currentIndex: Int?
    private let playback: AudioPlaybackControlling

    public init(playback: AudioPlaybackControlling) {
        self.playback = playback
    }

    public func open(_ files: [URL]) throws {
        guard let first = files.first else { throw AudioPlaylistError.noAudioFiles }
        try playback.load(url: first)
        self.files = files
        currentIndex = 0
        playback.currentTime = 0
        playback.play()
    }

    public func select(_ index: Int) throws {
        guard files.indices.contains(index) else { throw AudioPlaylistError.invalidSelection }
        try playback.load(url: files[index])
        currentIndex = index
        playback.currentTime = 0
        playback.play()
    }

    @discardableResult
    public func advanceAfterFinishing() throws -> Bool {
        playback.pause()
        guard let index = currentIndex, files.indices.contains(index + 1) else { return false }
        try playback.load(url: files[index + 1])
        currentIndex = index + 1
        playback.currentTime = 0
        return true
    }
}
