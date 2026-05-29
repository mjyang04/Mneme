import CoreServices
import Foundation
import MnemeCore

@MainActor
final class SourceFolderWatcher: ObservableObject {
    @Published private(set) var isWatching = false

    private var stream: FSEventStreamRef?
    private var queue: DispatchQueue?
    private var batcher: ActivityEventBatcher?
    private var debounceTask: Task<Void, Never>?
    private var onChange: (() async -> Void)?

    func start(sourceURLs: [URL], onChange: @escaping () async -> Void) {
        stop()
        guard !sourceURLs.isEmpty else { return }

        self.onChange = onChange
        let batcher = ActivityEventBatcher(workspaceRoots: sourceURLs)
        self.batcher = batcher

        let watcherPointer = Unmanaged.passUnretained(self).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: watcherPointer,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let paths = sourceURLs.map(\.path) as CFArray
        let queue = DispatchQueue(label: "mneme.sources.fsevents")
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, contextInfo, eventCount, eventPaths, _, _ in
                guard let contextInfo else { return }
                let watcher = Unmanaged<SourceFolderWatcher>
                    .fromOpaque(contextInfo)
                    .takeUnretainedValue()
                let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
                Task { @MainActor in
                    watcher.record(paths.prefix(eventCount).map { URL(fileURLWithPath: $0) })
                }
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        ) else {
            return
        }

        self.stream = stream
        self.queue = queue
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        isWatching = true
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        queue = nil
        batcher = nil
        onChange = nil
        isWatching = false
    }

    private func record(_ urls: [URL]) {
        guard let batcher else { return }
        let acceptedEvent = urls.reduce(false) { accepted, url in
            batcher.record(url) || accepted
        }
        if acceptedEvent {
            scheduleReindex()
        }
    }

    private func scheduleReindex() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }
            await self?.flush()
        }
    }

    private func flush() async {
        guard let batcher, !batcher.drain().isEmpty else { return }
        await onChange?()
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
