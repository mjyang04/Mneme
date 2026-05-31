import Foundation

public struct GitActivityCollector: Sendable {
    public let gitExecutable: String

    public init(gitExecutable: String = "/usr/bin/git") {
        self.gitExecutable = gitExecutable
    }

    public func collect(repository: URL, since: Date) throws -> [GitCommit] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitExecutable)
        process.currentDirectoryURL = repository
        process.arguments = [
            "log",
            "--since=\(Self.gitDateFormatter.string(from: since))",
            "--pretty=format:commit %H%n%s",
            "--numstat"
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        let outputReader = PipeReader(handle: outputPipe.fileHandleForReading)
        let errorReader = PipeReader(handle: errorPipe.fileHandleForReading)
        process.waitUntilExit()
        let data = outputReader.wait()
        _ = errorReader.wait()

        guard process.terminationStatus == 0 else {
            return []
        }

        let output = String(data: data, encoding: .utf8) ?? ""
        return Self.parseLog(output)
    }

    public static func parseLog(_ output: String) -> [GitCommit] {
        var commits: [GitCommit] = []
        var currentHash: String?
        var currentMessage: String?
        var currentFilesChanged = 0

        func flush() {
            guard let hash = currentHash else { return }
            commits.append(GitCommit(
                shortHash: String(hash.prefix(7)),
                message: currentMessage ?? "",
                filesChanged: currentFilesChanged
            ))
            currentHash = nil
            currentMessage = nil
            currentFilesChanged = 0
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("commit ") {
                flush()
                currentHash = String(line.dropFirst("commit ".count))
            } else if currentHash != nil, currentMessage == nil, !line.isEmpty {
                currentMessage = line
            } else if currentHash != nil, line.split(separator: "\t").count >= 3 {
                currentFilesChanged += 1
            }
        }
        flush()

        return commits
    }

    private static let gitDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private final class PipeReader: @unchecked Sendable {
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var data = Data()

    init(handle: FileHandle) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let output = handle.readDataToEndOfFile()
            self.lock.lock()
            self.data = output
            self.lock.unlock()
            self.group.leave()
        }
    }

    func wait() -> Data {
        group.wait()
        lock.lock()
        let output = data
        lock.unlock()
        return output
    }
}
