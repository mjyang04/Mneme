import Foundation

public struct FileTouch: Codable, Equatable, Sendable {
    public let relativePath: String
    public let touchCount: Int
    public let lastModifiedAt: Date

    public init(relativePath: String, touchCount: Int, lastModifiedAt: Date) {
        self.relativePath = relativePath
        self.touchCount = touchCount
        self.lastModifiedAt = lastModifiedAt
    }
}

public struct GitCommit: Codable, Equatable, Sendable {
    public let shortHash: String
    public let message: String
    public let filesChanged: Int

    public init(shortHash: String, message: String, filesChanged: Int) {
        self.shortHash = shortHash
        self.message = message
        self.filesChanged = filesChanged
    }
}

public struct ProjectActivity: Codable, Equatable, Sendable {
    public let name: String
    public let rootPath: String
    public let filesTouched: [FileTouch]
    public let commits: [GitCommit]

    public init(
        name: String,
        rootPath: String,
        filesTouched: [FileTouch],
        commits: [GitCommit]
    ) {
        self.name = name
        self.rootPath = rootPath
        self.filesTouched = filesTouched
        self.commits = commits
    }
}

public struct DailyActivity: Codable, Equatable, Sendable {
    public let day: String
    public let projects: [ProjectActivity]
    public let summary: String?

    public init(day: String, projects: [ProjectActivity], summary: String? = nil) {
        self.day = day
        self.projects = projects
        self.summary = summary
    }
}

public struct ActivityLogRefreshResult: Equatable, Sendable {
    public let activity: DailyActivity
    public let noteURL: URL

    public init(activity: DailyActivity, noteURL: URL) {
        self.activity = activity
        self.noteURL = noteURL
    }
}
