import Foundation

public struct ActivityLogService: Sendable {
    private let workspaceRoots: [URL]
    private let gitRepositories: [URL]
    private let dailyNotesDirectory: URL
    private let fileCollector: FileActivityCollector
    private let gitCollector: GitActivityCollector
    private let renderer: DailyActivityRenderer
    private let writer: DailyNoteWriter

    public init(
        workspaceRoots: [URL],
        gitRepositories: [URL],
        dailyNotesDirectory: URL,
        fileCollector: FileActivityCollector = FileActivityCollector(),
        gitCollector: GitActivityCollector = GitActivityCollector(),
        renderer: DailyActivityRenderer = DailyActivityRenderer()
    ) {
        self.workspaceRoots = workspaceRoots
        self.gitRepositories = gitRepositories
        self.dailyNotesDirectory = dailyNotesDirectory
        self.fileCollector = fileCollector
        self.gitCollector = gitCollector
        self.renderer = renderer
        self.writer = DailyNoteWriter(dailyDirectory: dailyNotesDirectory)
    }

    public func refresh(day: String, since: Date) throws -> ActivityLogRefreshResult {
        var projectsByRoot: [String: ProjectActivity] = [:]

        for root in workspaceRoots {
            let touches = try fileCollector.collect(root: root, since: since)
            if !touches.isEmpty {
                projectsByRoot[root.standardizedFileURL.path] = ProjectActivity(
                    name: root.lastPathComponent,
                    rootPath: root.path,
                    filesTouched: touches,
                    commits: []
                )
            }
        }

        for repository in gitRepositories {
            let commits = (try? gitCollector.collect(repository: repository, since: since)) ?? []
            guard !commits.isEmpty else { continue }
            let key = repository.standardizedFileURL.path
            let existing = projectsByRoot[key]
            projectsByRoot[key] = ProjectActivity(
                name: existing?.name ?? repository.lastPathComponent,
                rootPath: existing?.rootPath ?? repository.path,
                filesTouched: existing?.filesTouched ?? [],
                commits: commits
            )
        }

        let projects = projectsByRoot.values.sorted { $0.name < $1.name }
        let activity = DailyActivity(day: day, projects: projects)
        let noteURL = try writer.writeManagedBlock(renderer.render(activity), day: day)
        return ActivityLogRefreshResult(activity: activity, noteURL: noteURL)
    }
}
