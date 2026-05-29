import Foundation

public protocol ActivitySummaryGenerator: Sendable {
    func summarize(_ activity: DailyActivity) async throws -> String
}

public struct ActivitySummaryPromptBuilder: Sendable {
    public init() {}

    public func prompt(for activity: DailyActivity) -> String {
        let facts = activity.projects.map { project in
            var lines = ["项目: \(project.name)"]
            if !project.commits.isEmpty {
                let commits = project.commits.map {
                    "- commit \($0.shortHash): \($0.message), \($0.filesChanged) files"
                }
                lines.append("提交:")
                lines.append(contentsOf: commits)
            }
            if !project.filesTouched.isEmpty {
                let files = project.filesTouched.map {
                    "- \($0.relativePath), touched \($0.touchCount)x"
                }
                lines.append("文件:")
                lines.append(contentsOf: files)
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")

        return """
        你是本地科研日志助手。只依据【活动事实】写 2-3 句当天摘要，不要杜撰未出现的项目、文件、commit 或结果。
        语言使用中文，句子短，直接说明今天主要推进了什么。

        【日期】
        \(activity.day)

        【活动事实】
        \(facts.isEmpty ? "今日暂无授权目录活动。" : facts)

        【摘要】
        """
    }
}

public struct ExtractiveActivitySummaryGenerator: ActivitySummaryGenerator {
    public init() {}

    public func summarize(_ activity: DailyActivity) async throws -> String {
        guard !activity.projects.isEmpty else {
            return "今天授权目录没有记录到文件改动或 git 提交。"
        }

        let projectNames = activity.projects.map(\.name).joined(separator: "、")
        let commitCount = activity.projects.reduce(0) { $0 + $1.commits.count }
        let fileCount = activity.projects.reduce(0) { $0 + $1.filesTouched.count }
        var parts = ["今天主要活动集中在 \(projectNames)。"]
        if commitCount > 0 {
            parts.append("记录到 \(commitCount) 笔 git 提交。")
        }
        if fileCount > 0 {
            parts.append("记录到 \(fileCount) 个文件改动。")
        }
        return parts.joined(separator: "")
    }
}

public struct ResilientActivitySummaryGenerator: ActivitySummaryGenerator {
    private let primary: any ActivitySummaryGenerator
    private let fallback: ExtractiveActivitySummaryGenerator

    public init(
        primary: any ActivitySummaryGenerator,
        fallback: ExtractiveActivitySummaryGenerator = ExtractiveActivitySummaryGenerator()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    public func summarize(_ activity: DailyActivity) async throws -> String {
        do {
            let summary = try await primary.summarize(activity).trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                return summary
            }
        } catch {
            return try await fallback.summarize(activity)
        }
        return try await fallback.summarize(activity)
    }
}
