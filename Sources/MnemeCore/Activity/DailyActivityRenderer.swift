import Foundation

public struct DailyActivityRenderer: Sendable {
    public static let startMarker = "<!-- mneme:activity:start -->"
    public static let endMarker = "<!-- mneme:activity:end -->"

    public init() {}

    public func render(_ activity: DailyActivity) -> String {
        var lines: [String] = [
            Self.startMarker,
            "## 今日活动(自动)",
            ""
        ]

        if let summary = activity.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            lines.append("### 摘要")
            lines.append(summary)
            lines.append("")
        }

        if activity.projects.isEmpty {
            lines.append("- 今日暂无授权目录活动。")
        } else {
            for project in activity.projects {
                lines.append("### \(project.name)")
                if !project.commits.isEmpty {
                    let summaries = project.commits.map {
                        "`\($0.shortHash)` \($0.message) (\($0.filesChanged) files)"
                    }.joined(separator: " / ")
                    lines.append("- 提交 \(project.commits.count) 笔: \(summaries)")
                }
                if !project.filesTouched.isEmpty {
                    let files = project.filesTouched.map { "`\($0.relativePath)`" }
                        .joined(separator: ", ")
                    lines.append("- 改动文件 \(project.filesTouched.count): \(files)")
                }
                lines.append("")
            }
        }

        lines.append(Self.endMarker)
        return lines.joined(separator: "\n")
    }
}
